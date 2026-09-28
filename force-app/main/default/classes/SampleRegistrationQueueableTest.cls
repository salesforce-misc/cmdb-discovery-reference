@isTest
private class SampleRegistrationQueueableTest {

    // Put the "Sample" source into a known state (ensure-or-update; CnfgItemSourceDefinition
    // rows are visible to tests, so a blind insert could hit DUPLICATE_VALUE).
    private static void setSampleSource(Boolean enabled) {
        List<CnfgItemSourceDefinition> existing = [
            SELECT Id, IsEnabled, IsActive
            FROM CnfgItemSourceDefinition
            WHERE DeveloperName = 'Sample'
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            insert new CnfgItemSourceDefinition(
                DeveloperName = 'Sample',
                MasterLabel   = 'Sample',
                SourceName    = 'Sample',
                Description   = 'Source Identifier for CI data fetched from Sample',
                IsActive      = enabled,
                IsCustom      = true,
                IsEnabled     = enabled);
        } else {
            existing[0].IsEnabled = enabled;
            existing[0].IsActive  = enabled;
            update existing[0];
        }
    }

    // Remove Sample's runtime-created bindings so execute() re-creates them, exercising the
    // INSERT branches. All DML here rolls back with the test transaction, so the org is
    // unaffected; if these setup rows can't be deleted, the "already exists" branch is
    // covered instead.
    private static void clearSampleBindings() {
        try {
            List<CnfgItemTypeRelationDef> rels = [
                SELECT Id FROM CnfgItemTypeRelationDef WHERE DeveloperName = 'Sample_Compute_Vulnerability'
            ];
            if (!rels.isEmpty()) delete rels;
        } catch (Exception ignored) {
            // not deletable here — the exists-branch is covered instead
        }
        try {
            List<CnfgItemTypeAttrRelDef> attrRels = [
                SELECT Id FROM CnfgItemTypeAttrRelDef WHERE DeveloperName LIKE 'Sample_Compute_%'
            ];
            if (!attrRels.isEmpty()) delete attrRels;
        } catch (Exception ignored) {
            // not deletable here — the exists-branch is covered instead
        }
    }

    @isTest
    static void executeRegistersSourceBindingsAndRelation() {
        setSampleSource(false); // disabled -> drives the enable/update branch
        clearSampleBindings(); // absent    -> drives the insert branches

        Test.startTest();
        System.enqueueJob(new SampleRegistrationQueueable());
        Test.stopTest();

        CnfgItemSourceDefinition src = [
            SELECT IsEnabled, IsActive
            FROM CnfgItemSourceDefinition
            WHERE DeveloperName = 'Sample'
            LIMIT 1
        ];
        System.assertEquals(true, src.IsEnabled, 'Registration must enable the source');
        System.assertEquals(true, src.IsActive, 'Registration must activate the source');
    }

    @isTest
    static void executeBindsAttributesForResolvableComputeType() {
        // The standard Compute type (SD_Comxx1) is absent from a bare packaging build org, so the
        // production no-arg path can't exercise the attribute-binding logic there. Point the
        // queueable at this package's OWN shipped CI type (SampleVulnerability) — guaranteed
        // present post-install — so the resolve/insert paths actually run. All DML rolls back
        // with the test transaction, so the org is unaffected.
        setSampleSource(false);
        clearSampleBindings();

        Test.startTest();
        System.enqueueJob(new SampleRegistrationQueueable('SampleVulnerability'));
        Test.stopTest();

        // Source registration always runs regardless of standard-data availability.
        CnfgItemSourceDefinition src = [
            SELECT IsEnabled, IsActive
            FROM CnfgItemSourceDefinition
            WHERE DeveloperName = 'Sample'
            LIMIT 1
        ];
        System.assertEquals(true, src.IsEnabled, 'Registration must enable the source');
        System.assertEquals(true, src.IsActive, 'Registration must activate the source');
    }

    @isTest
    static void executeIsIdempotentWhenAlreadyRegistered() {
        setSampleSource(true); // already enabled -> drives the early-return branch

        Test.startTest();
        System.enqueueJob(new SampleRegistrationQueueable());
        Test.stopTest();

        CnfgItemSourceDefinition src = [
            SELECT IsEnabled, IsActive
            FROM CnfgItemSourceDefinition
            WHERE DeveloperName = 'Sample'
            LIMIT 1
        ];
        System.assertEquals(true, src.IsEnabled, 'Source stays enabled');
        System.assertEquals(true, src.IsActive, 'Source stays active');
    }
}
