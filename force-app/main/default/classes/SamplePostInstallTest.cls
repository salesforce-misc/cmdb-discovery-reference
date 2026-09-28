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
