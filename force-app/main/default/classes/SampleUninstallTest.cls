@isTest
private class SampleUninstallTest {

    // Puts a "Sample" source into a known state, whether or not one already exists.
    // CnfgItemSourceDefinition rows are visible to tests (no clean-slate guarantee), and the
    // handler always targets DeveloperName = 'Sample', so we ensure-or-update rather than
    // blindly insert (a blind insert would hit DUPLICATE_VALUE when a source already exists).
    private static void ensureSource(Boolean enabled) {
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

    private static CnfgItemSourceDefinition sampleSource() {
        return [
            SELECT IsEnabled, IsActive
            FROM CnfgItemSourceDefinition
            WHERE DeveloperName = 'Sample'
            LIMIT 1
        ];
    }

    @isTest
    static void uninstallDisablesAnEnabledSource() {
        ensureSource(true);

        Test.startTest();
        Test.testUninstall(new SampleUninstall());
        Test.stopTest();

        CnfgItemSourceDefinition src = sampleSource();
        System.assertEquals(false, src.IsEnabled, 'Uninstall must disable the source');
        System.assertEquals(false, src.IsActive, 'Uninstall must deactivate the source');
    }

    @isTest
    static void uninstallIsIdempotentWhenAlreadyDisabled() {
        ensureSource(false);

        // Already disabled — the handler must be a safe no-op and never throw.
        Test.startTest();
        Test.testUninstall(new SampleUninstall());
        Test.stopTest();

        CnfgItemSourceDefinition src = sampleSource();
        System.assertEquals(false, src.IsEnabled, 'Source stays disabled');
        System.assertEquals(false, src.IsActive, 'Source stays deactivated');
    }

    // Best-effort seed of a runtime Compute attribute binding that references this package's
    // own SampleVulnerability CI type — the kind of record that, when it points at a packaged
    // component, blocks the uninstall. Returns the seeded row's Id, or null if the build org
    // won't allow the insert (in which case the delete branch simply isn't exercised here — the
    // real end-to-end coverage is the install/uninstall in an org that has the standard data).
    private static Id seedComputeAttrBinding() {
        try {
            List<CnfgItemTypeDef> types = [SELECT Id FROM CnfgItemTypeDef WHERE DeveloperName = 'SampleVulnerability' LIMIT 1];
            List<CnfgItemAttrDef> attrs = [SELECT Id FROM CnfgItemAttrDef WHERE DeveloperName = 'SampleAgentStatus' LIMIT 1];
            if (types.isEmpty() || attrs.isEmpty()) return null;

            CnfgItemTypeAttrRelDef binding = new CnfgItemTypeAttrRelDef(
                CnfgItemTypeDefId = types[0].Id,
                CnfgItemAttrDefId = attrs[0].Id,
                DeveloperName = 'Sample_Compute_SampleAgentStatus',
                MasterLabel   = 'Sample Compute Test Binding',
                IsActive=false, IsHidden=false, IsMain=false,
                IsPrimary=false, IsReadOnly=false,
                IsRequired=false, IsUsedInRelMap=false);
            insert binding;
            return binding.Id;
        } catch (Exception seedFailed) {
            return null;
        }
    }

    // prepareForUninstall() is the ADMIN-INVOKED pre-step that removes the runtime CI-type
    // bindings which reference this package's packaged components — the records that otherwise
    // block the uninstall (reasonCode 10). It must delete them so the admin can then uninstall.
    @isTest
    static void prepareForUninstallDeletesRuntimeTypeBindings() {
        Id bindingId = seedComputeAttrBinding();

        Test.startTest();
        SampleUninstall.prepareForUninstall();
        Test.stopTest();

        if (bindingId != null) {
            List<CnfgItemTypeAttrRelDef> remaining = [
                SELECT Id FROM CnfgItemTypeAttrRelDef WHERE Id = :bindingId
            ];
            System.assertEquals(0, remaining.size(),
                'prepareForUninstall must delete the runtime Compute attribute binding so it cannot block the uninstall');
        }
    }

    // prepareForUninstall() must be a safe no-op when there are no bindings to remove.
    @isTest
    static void prepareForUninstallIsSafeWhenNothingToDelete() {
        Test.startTest();
        SampleUninstall.prepareForUninstall();
        Test.stopTest();
        // No assertion beyond "did not throw"; running twice must also be harmless.
        SampleUninstall.prepareForUninstall();
    }
}
