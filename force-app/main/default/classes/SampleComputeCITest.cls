@isTest
private class SampleComputeCITest {

    @isTest
    static void testInstantiation() {
        SampleComputeCI ci = new SampleComputeCI();
        System.assertNotEquals(null, ci, 'Compute instance should not be null');
    }

    @isTest
    static void testPropertiesAssignment() {
        SampleComputeCI ci = new SampleComputeCI();
        ci.AssetName = 'LAPTOP-001';
        ci.SerialNumber = 'SN12345';
        ci.HostName = 'laptop-001.example.com';
        ci.OperatingSystem = 'Windows';
        ci.IpAddress = '10.0.0.1';
        ci.MacAddress = 'AA:BB:CC:DD:EE:FF';
        ci.SampleAgentStatus = 'Online';
        ci.SampleComplianceState = 'Compliant';

        System.assertEquals('LAPTOP-001', ci.AssetName);
        System.assertEquals('SN12345', ci.SerialNumber);
        System.assertEquals('Online', ci.SampleAgentStatus);
        System.assertEquals('Compliant', ci.SampleComplianceState);
    }

    @isTest
    static void testChildCollection() {
        SampleComputeCI ci = new SampleComputeCI();
        SampleVulnerabilityCI vuln = new SampleVulnerabilityCI();
        vuln.VulnerabilityId = 'CVE-2024-0001';
        vuln.Severity = 'High';
        vuln.Status = 'Open';
        ci.Vulnerabilities = new List<SampleVulnerabilityCI>{ vuln };

        System.assertEquals(1, ci.Vulnerabilities.size());
        System.assertEquals('CVE-2024-0001', ci.Vulnerabilities[0].VulnerabilityId);
        System.assertEquals('High', ci.Vulnerabilities[0].Severity);
    }
}
