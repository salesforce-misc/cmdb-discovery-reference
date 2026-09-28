/**
 * Inserts the CnfgItem* CI-type source/relationship definitions (all *non-setup* objects)
 * in their own async transaction — enqueued from SamplePostInstall.onInstall alongside
 * SampleProbeRegistrationQueueable. The probe entities it handles (CnfgMgmt*) are *setup*
 * objects, so the two families run as separate jobs: setup and non-setup DML cannot share a
 * transaction, and neither may run inside the install transaction (both would trip
 * MIXED_DML_OPERATION and abort the install). Running here, in its own transaction, is what
 * keeps this non-setup DML clean.
 *
 * WHY THESE THREE THINGS ARE CREATED AT RUNTIME (AND NOT SHIPPED AS METADATA)
 * --------------------------------------------------------------------------
 * The Schema describe confirms all three objects are DML-createable, and each is kept out
 * of packaged metadata for one of two reasons:
 *   - CnfgItemSourceDefinition   (the discovery source) — a runtime registration record that
 *                                discovered CI data becomes associated with; kept out of
 *                                packaged metadata so an UNINSTALL doesn't remove records the
 *                                discovered data depends on. See below.
 *   - CnfgItemTypeAttrRelDef     (attach this package's attributes to standard Compute) — and
 *   - CnfgItemTypeRelationDef    (declare the new Vulnerability type as a child of Compute) —
 *                                both reference platform-standard data (the built-in Compute
 *                                type SD_Comxx1 and the standard "Parent/Child" relationship
 *                                type SD_PaCh) that exists in a real Agentforce for IT Service
 *                                org but is NOT part of this package; shipping them as static
 *                                metadata would make the package fail to install where that
 *                                standard data is absent, so they bind at runtime instead.
 * By contrast the new CI type itself (CnfgItemTypeDef), its identity rule, its own
 * attributes, and their property groups ship as static metadata, because they reference only
 * this package's own definitions. See docs/ARCHITECTURE.md ("What ships as metadata vs.
 * what's created at runtime") for the full ship-vs-runtime table.
 *
 * GRACEFUL DEGRADATION
 * --------------------
 * The two standard-data-dependent steps return quietly under Test.isRunningTest() when that
 * standard data is missing (so the package still installs and its tests still pass in a bare
 * org) and otherwise throw a clear RegistrationException naming the missing developer name.
 * Source creation has no standard-data dependency, so it always runs. All queries and DML run
 * idempotently in AccessLevel.SYSTEM_MODE.
 */
global without sharing class SampleRegistrationQueueable implements Queueable {

    private static final String SOURCE_DEVNAME  = 'Sample';
    private static final String SOURCE_LABEL     = 'Sample';
    private static final String SOURCE_DESC      = 'Source Identifier for CI data fetched from Sample';
    private static final String DEFAULT_CI_TYPE_COMPUTE = 'SD_Comxx1';
    private static final String CI_TYPE_VULN      = 'SampleVulnerability';
    private static final String REL_TYPE_PARENT_CHILD = 'SD_PaCh';

    // Source-specific attribute developer names shipped in cnfgItemAttrDefs/.
    private static final List<String> SAMPLE_ATTR_DEVNAMES = new List<String>{
        'SampleAgentStatus',
        'SampleComplianceState'
    };

    // Developer name of the standard Compute CI type this package's attributes attach to.
    // Injected via constructor so it can be overridden in unit tests: the standard Compute type
    // is absent from a bare packaging build org, so a test can instead point the binding logic at
    // a CI type that IS present there — e.g. this package's own shipped SampleVulnerability type —
    // and exercise the real resolve/insert paths. Production always uses the no-arg constructor,
    // which binds to the standard Compute type.
    private final String computeTypeDevName;

    global SampleRegistrationQueueable() {
        this(DEFAULT_CI_TYPE_COMPUTE);
    }

    @TestVisible
    private SampleRegistrationQueueable(String computeTypeDevName) {
        this.computeTypeDevName = computeTypeDevName;
    }

    global void execute(QueueableContext qc) {
        ensureSourceRegistered();
        upsertTypeAttrRelDefs();
        upsertComputeToVulnerabilityRelation();
    }

    /**
     * Creates this package's discovery source at runtime (idempotently), rather than
     * shipping it as a CnfgItemSourceDefinition metadata file.
     *
     * WHY NOT METADATA: the source is a runtime registration record that discovered CI data
     * becomes associated with (each CI carries its SourceName). A managed-package uninstall
     * tears down every packaged component, so shipping the source as metadata would remove it
     * on uninstall along with records the discovered data depends on. Creating it here keeps it
     * outside the package's deletable footprint, so an uninstall leaves the source — and the
     * CIs pointing at it — intact.
     */
    private void ensureSourceRegistered() {
        List<CnfgItemSourceDefinition> existing = Database.query(
            'SELECT Id, IsEnabled, IsActive FROM CnfgItemSourceDefinition WHERE DeveloperName = :SOURCE_DEVNAME LIMIT 1',
            AccessLevel.SYSTEM_MODE);
        if (existing.isEmpty()) {
            CnfgItemSourceDefinition src = new CnfgItemSourceDefinition(
                DeveloperName = SOURCE_DEVNAME,
                MasterLabel   = SOURCE_LABEL,
                SourceName    = SOURCE_DEVNAME,
                Description   = SOURCE_DESC,
                IsActive      = true,
                IsCustom      = true,
                IsEnabled     = true);
            Database.insert(src, AccessLevel.SYSTEM_MODE);
            return;
        }
        CnfgItemSourceDefinition src = existing[0];
        if (src.IsEnabled == true && src.IsActive == true) return;
        src.IsEnabled = true;
        src.IsActive  = true;
        Database.update(src, AccessLevel.SYSTEM_MODE);
    }

    private void upsertTypeAttrRelDefs() {
        Set<String> wantAttrDevNames = new Set<String>(SAMPLE_ATTR_DEVNAMES);

        List<CnfgItemTypeDef> types = Database.query(
            'SELECT Id FROM CnfgItemTypeDef WHERE DeveloperName = :computeTypeDevName LIMIT 1',
            AccessLevel.SYSTEM_MODE);
        if (types.isEmpty()) {
            if (Test.isRunningTest()) return;
            throw new RegistrationException('Missing CnfgItemTypeDef DeveloperName: ' + computeTypeDevName);
        }
        Id typeId = types[0].Id;

        Map<String, Id> attrIdByDevName = new Map<String, Id>();
        for (CnfgItemAttrDef a : Database.query(
            'SELECT Id, DeveloperName FROM CnfgItemAttrDef WHERE DeveloperName IN :wantAttrDevNames',
            AccessLevel.SYSTEM_MODE)) {
            attrIdByDevName.put((String) a.get('DeveloperName'), (Id) a.get('Id'));
        }
        if (attrIdByDevName.size() != wantAttrDevNames.size()) {
            Set<String> missing = new Set<String>(wantAttrDevNames);
            missing.removeAll(attrIdByDevName.keySet());
            throw new RegistrationException('Missing CnfgItemAttrDef DeveloperNames: ' + missing);
        }

        Set<Id> attrIdSet = new Set<Id>(attrIdByDevName.values());
        Set<Id> existingAttrIds = new Set<Id>();
        for (CnfgItemTypeAttrRelDef r : Database.query(
            'SELECT CnfgItemAttrDefId FROM CnfgItemTypeAttrRelDef '
            + 'WHERE CnfgItemTypeDefId = :typeId AND CnfgItemAttrDefId IN :attrIdSet',
            AccessLevel.SYSTEM_MODE)) {
            existingAttrIds.add((Id) r.get('CnfgItemAttrDefId'));
        }

        List<CnfgItemTypeAttrRelDef> rows = new List<CnfgItemTypeAttrRelDef>();
        for (String devName : attrIdByDevName.keySet()) {
            Id attrId = attrIdByDevName.get(devName);
            if (existingAttrIds.contains(attrId)) continue;
            rows.add(new CnfgItemTypeAttrRelDef(
                CnfgItemTypeDefId = typeId,
                CnfgItemAttrDefId = attrId,
                DeveloperName = 'Sample_Compute_' + devName,
                MasterLabel   = devName.replace('_', ' '),
                IsActive=false, IsHidden=false, IsMain=false,
                IsPrimary=false, IsReadOnly=false,
                IsRequired=false, IsUsedInRelMap=false));
        }
        if (!rows.isEmpty()) Database.insert(rows, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Declares that a standard Compute CI can have Sample Vulnerability CIs as children,
     * via the standard "Parent/Child" relationship type (SD_PaCh, source = parent). This is
     * what makes the new component type actually attach to Compute; without it the
     * discovered vulnerabilities have nowhere to hang. Created here rather than shipped as
     * metadata because it points at the standard Compute type and standard relationship
     * type, neither of which is part of this package.
     */
    private void upsertComputeToVulnerabilityRelation() {
        Map<String, Id> typeIdByDevName = new Map<String, Id>();
        for (CnfgItemTypeDef t : Database.query(
            'SELECT Id, DeveloperName FROM CnfgItemTypeDef '
            + 'WHERE DeveloperName IN (:computeTypeDevName, :CI_TYPE_VULN)',
            AccessLevel.SYSTEM_MODE)) {
            typeIdByDevName.put((String) t.get('DeveloperName'), (Id) t.get('Id'));
        }
        Id computeTypeId = typeIdByDevName.get(computeTypeDevName);
        Id vulnTypeId    = typeIdByDevName.get(CI_TYPE_VULN);

        List<CnfgMgmtRelationTypeDef> relTypes = Database.query(
            'SELECT Id FROM CnfgMgmtRelationTypeDef WHERE DeveloperName = :REL_TYPE_PARENT_CHILD LIMIT 1',
            AccessLevel.SYSTEM_MODE);
        Id relTypeId = relTypes.isEmpty() ? null : relTypes[0].Id;

        if (computeTypeId == null || vulnTypeId == null || relTypeId == null) {
            if (Test.isRunningTest()) return;
            List<String> missing = new List<String>();
            if (computeTypeId == null) missing.add('CnfgItemTypeDef:' + computeTypeDevName);
            if (vulnTypeId == null)    missing.add('CnfgItemTypeDef:' + CI_TYPE_VULN);
            if (relTypeId == null)     missing.add('CnfgMgmtRelationTypeDef:' + REL_TYPE_PARENT_CHILD);
            throw new RegistrationException('Missing standard definitions: ' + missing);
        }

        List<CnfgItemTypeRelationDef> existing = Database.query(
            'SELECT Id FROM CnfgItemTypeRelationDef '
            + 'WHERE SourceConfigurationItemTypeId = :computeTypeId '
            + 'AND TargetConfigurationItemTypeId = :vulnTypeId '
            + 'AND CnfgMgmtRelationTypeDefId = :relTypeId LIMIT 1',
            AccessLevel.SYSTEM_MODE);
        if (!existing.isEmpty()) return;

        CnfgItemTypeRelationDef rel = new CnfgItemTypeRelationDef(
            DeveloperName                  = 'Sample_Compute_Vulnerability',
            MasterLabel                    = 'Sample Compute Vulnerability',
            CnfgMgmtRelationTypeDefId      = relTypeId,
            SourceConfigurationItemTypeId  = computeTypeId,
            TargetConfigurationItemTypeId  = vulnTypeId);
        Database.insert(rel, AccessLevel.SYSTEM_MODE);
    }

    public class RegistrationException extends Exception {}
}
