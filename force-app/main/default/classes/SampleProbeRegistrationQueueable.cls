/**
 * Registers the discovery probe that ties this package's flow template, custom property
 * editor, and icon together in the CMDB discovery UI. Runs the CnfgMgmt* probe DML in its
 * OWN async transaction, enqueued from SamplePostInstall.onInstall.
 *
 * WHY THIS IS A SEPARATE ASYNC JOB (MIXED-DML)
 * --------------------------------------------
 * The platform classifies CnfgMgmtDiscoveryProbe / CnfgMgmtProbeFlowTmpl /
 * CnfgMgmtProbePrvwAttrDef as *setup* objects, while CnfgItemSourceDefinition /
 * CnfgItemTypeAttrRelDef / CnfgItemTypeRelationDef (handled by SampleRegistrationQueueable)
 * are *non-setup* objects. A single transaction cannot DML both. The package install
 * transaction itself performs DML, so doing this probe DML synchronously in onInstall throws
 * MIXED_DML_OPERATION and aborts the whole install ("The post install script failed.").
 * Deferring each family to its own Queueable puts every insert/update in a clean transaction:
 * no mixing against the install tx, and no mixing between the two families.
 *
 * ACCESS MODE
 * -----------
 * Everything runs in AccessLevel.SYSTEM_MODE: the async context runs as the Automated
 * Process user, which has no org-wide profile granting access to these entities.
 *
 * IDEMPOTENCY
 * -----------
 * Enqueued on first install and on upgrades, so every insert is guarded by an existence
 * check — upgrades must never create duplicate rows.
 */
global without sharing class SampleProbeRegistrationQueueable implements Queueable {

    private static final String PROBE_NAME          = 'Sample';
    private static final String PROBE_DESC          = 'Discover devices and inventory from Sample.';
    private static final String PROBE_CATEGORY      = 'MDM_DEVICE_MANAGEMENT';
    private static final String PROBE_TYPE          = 'external';
    private static final String EXTERNAL_PROBE_TYPE = 'Sample';
    private static final String CONNECTOR_DEVNAME   = 'Sample';

    // Standard platform attribute developer names shown in the discovery preview grid.
    private static final List<String> PREVIEW_ATTR_DEVNAMES = new List<String>{
        'SD_AsNa', 'SD_HoNa', 'SD_OpSy', 'SD_IpAd', 'SD_SeNu'
    };
    private static final List<String> PREVIEW_ATTR_NAMES = new List<String>{
        'SmplPrvw_SD_AsNa', 'SmplPrvw_SD_HoNa', 'SmplPrvw_SD_OpSy', 'SmplPrvw_SD_IpAd', 'SmplPrvw_SD_SeNu'
    };

    // On upgrade we reconcile the string component references (CPE / icon) rather than
    // re-create the probe; on first install we create everything.
    private final Boolean isUpgrade;

    global SampleProbeRegistrationQueueable() {
        this(false);
    }

    // global so SamplePostInstall can distinguish first-install (create) from upgrade
    // (reconcile). Passing true routes execute() to reconcileExistingRegistration().
    global SampleProbeRegistrationQueueable(Boolean isUpgrade) {
        this.isUpgrade = isUpgrade;
    }

    global void execute(QueueableContext qc) {
        // Let exceptions propagate. A failed Queueable does NOT abort or roll back the
        // already-completed package install, and the platform records the exception in this
        // job's AsyncApexJob.ExtendedStatus — the one place post-install async failures are
        // queryable (trace flags capture nothing here). Swallowing and only logging would
        // recreate the original silent 0-rows failure that made this bug so hard to find.
        if (isUpgrade) {
            reconcileExistingRegistration();
        } else {
            insertProbeRegistration();
        }
    }

    // The namespace this package is installed under, detected at runtime: "" for a
    // no-namespace install (unlocked package or plain source deploy) and "<ns>__" for a
    // managed package. Component references stored as strings (the CPE, the icon, and the
    // flow template below) must carry this prefix to resolve, so the same code is correct
    // however the package ships — no hard-coded namespace to edit when you fork.
    private static String nsPrefix;
    private static String nsPrefix() {
        if (nsPrefix == null) {
            // Derive the namespace from the class's own runtime type name — NOT from a SOQL
            // query on ApexClass. SOQL on ApexClass is unsupported in the post-install async
            // context (throws "sObject type 'ApexClass' is not supported"), which silently
            // aborted this job at install time before any DML ran. Type.getName() does no
            // SOQL and returns "<ns>.SampleProbeRegistrationQueueable" for a managed package
            // or bare "SampleProbeRegistrationQueueable" for a no-namespace deploy.
            String typeName = SampleProbeRegistrationQueueable.class.getName();
            Integer dot = typeName.indexOf('.');
            String ns = dot > 0 ? typeName.substring(0, dot) : '';
            nsPrefix = String.isEmpty(ns) ? '' : ns + '__';
        }
        return nsPrefix;
    }

    private static String cpeDevName()      { return nsPrefix() + 'sampleSyncSettings'; }
    private static String iconDevName()     { return nsPrefix() + 'SampleIcon'; }
    private static String templateApiName() { return nsPrefix() + 'SyncSampleToCMDB'; }

    private static void insertProbeRegistration() {
        Id probeId;
        List<CnfgMgmtDiscoveryProbe> existingProbes = Database.query(
            'SELECT Id FROM CnfgMgmtDiscoveryProbe WHERE ExternalProbeType = :EXTERNAL_PROBE_TYPE LIMIT 1',
            AccessLevel.SYSTEM_MODE);
        if (!existingProbes.isEmpty()) {
            probeId = existingProbes[0].Id;
        } else {
            CnfgMgmtDiscoveryProbe probe = new CnfgMgmtDiscoveryProbe();
            probe.Name              = PROBE_NAME;
            probe.Description       = PROBE_DESC;
            probe.Category          = PROBE_CATEGORY;
            probe.ProbeType         = PROBE_TYPE;
            probe.ExternalProbeType = EXTERNAL_PROBE_TYPE;
            probe.ExtlCnctrDevlName = CONNECTOR_DEVNAME;
            probe.ExtlProbeCpntName = cpeDevName();
            probe.ProbeIconPath     = iconDevName();
            Database.insert(probe, AccessLevel.SYSTEM_MODE);
            probeId = probe.Id;
        }

        List<CnfgMgmtProbeFlowTmpl> existingTmpl = Database.query(
            'SELECT Id FROM CnfgMgmtProbeFlowTmpl WHERE CnfgMgmtDiscoveryProbeId = :probeId LIMIT 1',
            AccessLevel.SYSTEM_MODE);
        if (existingTmpl.isEmpty()) {
            CnfgMgmtProbeFlowTmpl tmpl = new CnfgMgmtProbeFlowTmpl();
            tmpl.CnfgMgmtDiscoveryProbeId = probeId;
            tmpl.FlowTemplateApiName      = templateApiName();
            tmpl.CnfgItmDataScope         = 'Compute';
            // DiscoveryMode was added in a later API version — set it only if the field
            // exists at runtime, so this package still installs on older orgs.
            Map<String, Schema.SObjectField> tmplFlds =
                Schema.SObjectType.CnfgMgmtProbeFlowTmpl.fields.getMap();
            if (tmplFlds.containsKey('discoverymode')) {
                tmpl.put('DiscoveryMode', 'Pull');
            }
            Database.insert(tmpl, AccessLevel.SYSTEM_MODE);
        }

        Set<String> existingAttrs = new Set<String>();
        for (CnfgMgmtProbePrvwAttrDef a : Database.query(
            'SELECT CnfgItmAttrDevName FROM CnfgMgmtProbePrvwAttrDef WHERE CnfgMgmtDiscoveryProbeId = :probeId',
            AccessLevel.SYSTEM_MODE)) {
            existingAttrs.add((String) a.get('CnfgItmAttrDevName'));
        }
        List<CnfgMgmtProbePrvwAttrDef> attrs = new List<CnfgMgmtProbePrvwAttrDef>();
        for (Integer i = 0; i < PREVIEW_ATTR_DEVNAMES.size(); i++) {
            if (existingAttrs.contains(PREVIEW_ATTR_DEVNAMES[i])) continue;
            CnfgMgmtProbePrvwAttrDef a = new CnfgMgmtProbePrvwAttrDef();
            a.CnfgMgmtDiscoveryProbeId = probeId;
            a.CnfgItmAttrDevName       = PREVIEW_ATTR_DEVNAMES[i];
            a.DisplayOrder             = i + 1;
            a.Name                     = PREVIEW_ATTR_NAMES[i];
            attrs.add(a);
        }
        if (!attrs.isEmpty()) Database.insert(attrs, AccessLevel.SYSTEM_MODE);
    }

    private static void reconcileExistingRegistration() {
        List<CnfgMgmtDiscoveryProbe> existing = Database.query(
            'SELECT Id FROM CnfgMgmtDiscoveryProbe WHERE ExternalProbeType = :EXTERNAL_PROBE_TYPE LIMIT 1',
            AccessLevel.SYSTEM_MODE);
        if (existing.isEmpty()) {
            insertProbeRegistration();
            return;
        }
        CnfgMgmtDiscoveryProbe probe = new CnfgMgmtDiscoveryProbe(
            Id                = existing[0].Id,
            ExtlProbeCpntName = cpeDevName(),
            ProbeIconPath     = iconDevName());
        Database.update(probe, AccessLevel.SYSTEM_MODE);
    }
}
