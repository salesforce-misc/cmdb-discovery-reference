@isTest
private class SamplePostInstallTest {

    @isTest
    static void firstInstallInsertsRegistrationRecords() {
        Test.startTest();
        Test.testInstall(new SamplePostInstall(), null);
        Test.stopTest();

        List<CnfgMgmtDiscoveryProbe> probes = [
            SELECT Id, Name, ExternalProbeType
            FROM CnfgMgmtDiscoveryProbe
            WHERE Name = 'Sample'
        ];
        System.assertEquals(1, probes.size(), 'One probe row expected after install');

        List<CnfgMgmtProbeFlowTmpl> tmpls = [
            SELECT Id FROM CnfgMgmtProbeFlowTmpl
            WHERE CnfgMgmtDiscoveryProbeId = :probes[0].Id
        ];
        System.assertEquals(1, tmpls.size(), 'One flow template row expected');

        List<CnfgMgmtProbePrvwAttrDef> attrs = [
            SELECT Id, CnfgItmAttrDevName, DisplayOrder
            FROM CnfgMgmtProbePrvwAttrDef
            WHERE CnfgMgmtDiscoveryProbeId = :probes[0].Id
            ORDER BY DisplayOrder
        ];
        System.assertEquals(5, attrs.size(), 'Five preview attribute rows expected');

        List<CnfgItemSourceDefinition> sources = [
            SELECT IsEnabled, IsActive FROM CnfgItemSourceDefinition WHERE DeveloperName = 'Sample'
        ];
        System.assertEquals(1, sources.size(), 'Install must register the Sample source');
        System.assertEquals(true, sources[0].IsEnabled, 'Source must be enabled');
        System.assertEquals(true, sources[0].IsActive, 'Source must be active');
    }

    // An upgrade must add probe rows that are missing — e.g. a preview column added in a later
    // version — not just update the existing probe's CPE / icon references.
    @isTest
    static void upgradeAddsMissingProbeRows() {
        // Simulate an org on an older version: the probe exists, but without a flow template
        // row or preview columns. runAs isolates this setup-object DML from the test's other DML.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<CnfgMgmtDiscoveryProbe> probes = [
                SELECT Id FROM CnfgMgmtDiscoveryProbe WHERE ExternalProbeType = 'Sample' LIMIT 1
            ];
            if (probes.isEmpty()) {
                insert new CnfgMgmtDiscoveryProbe(
                    Name = 'Sample',
                    Description = 'Discover devices and inventory from Sample.',
                    Category = 'MDM_DEVICE_MANAGEMENT',
                    ProbeType = 'external',
                    ExternalProbeType = 'Sample',
                    ExtlCnctrDevlName = 'Sample',
                    ExtlProbeCpntName = 'oldCpe',
                    ProbeIconPath = 'oldIcon');
            } else {
                delete [SELECT Id FROM CnfgMgmtProbeFlowTmpl WHERE CnfgMgmtDiscoveryProbeId = :probes[0].Id];
                delete [SELECT Id FROM CnfgMgmtProbePrvwAttrDef WHERE CnfgMgmtDiscoveryProbeId = :probes[0].Id];
            }
        }

        Test.startTest();
        Test.testInstall(new SamplePostInstall(), new Version(1, 0));
        Test.stopTest();

        List<CnfgMgmtDiscoveryProbe> probes = [
            SELECT Id FROM CnfgMgmtDiscoveryProbe WHERE ExternalProbeType = 'Sample'
        ];
        System.assertEquals(1, probes.size(), 'Upgrade must reuse the existing probe');
        Integer tmpls = [
            SELECT COUNT() FROM CnfgMgmtProbeFlowTmpl WHERE CnfgMgmtDiscoveryProbeId = :probes[0].Id
        ];
        System.assertEquals(1, tmpls, 'Upgrade must add the missing flow template row');
        Integer attrs = [
            SELECT COUNT() FROM CnfgMgmtProbePrvwAttrDef WHERE CnfgMgmtDiscoveryProbeId = :probes[0].Id
        ];
        System.assertEquals(5, attrs, 'Upgrade must add the missing preview attribute rows');
    }

    @isTest
    static void upgradeDoesNotDuplicate() {
        Test.testInstall(new SamplePostInstall(), null);

        Test.startTest();
        Test.testInstall(new SamplePostInstall(), new Version(1, 0));
        Test.stopTest();

        Integer probeCount = [SELECT COUNT() FROM CnfgMgmtDiscoveryProbe WHERE Name = 'Sample'];
        System.assertEquals(1, probeCount, 'Upgrade must not create duplicate probe rows');
    }
}
