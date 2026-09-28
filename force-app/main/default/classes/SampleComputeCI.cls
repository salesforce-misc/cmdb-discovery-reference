/**
 * Parent Configuration Item DTO for a discovered compute device.
 *
 * A parent CI extends ItSvcAssetDcvr.BaseParentCnfgItem. The discovery Flow builds one of
 * these per device and hands it to the CMDB bulk-persist action. Child inventory hangs off
 * it as @AuraEnabled List<> collections, so one device round-trips as a single graph. Here
 * the device carries its discovered security vulnerabilities as one child collection; add
 * more collections the same way.
 *
 * This class shows the TWO ways to extend CMDB, and both are exercised by the Flow:
 *   - Reuse a STANDARD type + add attributes: this parent maps to the built-in Compute type
 *     and adds SampleAgentStatus / SampleComplianceState, bound to Compute at runtime by
 *     SampleRegistrationQueueable.
 *   - Introduce a NEW type: the Vulnerabilities child uses SampleVulnerabilityCI, a custom
 *     CI type this package defines entirely in metadata (see that class's header).
 *
 * Keep the field set small and generic — this is a sample. Add your own @AuraEnabled fields
 * and, for source-specific ones, a matching cnfgItemAttrDefs/ file.
 *
 * The label map passed to super() drives display names in the discovery preview UI; each
 * key must match an @AuraEnabled field name on this class.
 */
global class SampleComputeCI extends ItSvcAssetDcvr.BaseParentCnfgItem {

    private static final Map<String, String> SAMPLE_COMPUTE_LABELS = new Map<String, String>{
        'AssetName' => 'Asset Name',
        'SerialNumber' => 'Serial Number',
        'HostName' => 'Host Name',
        'OperatingSystem' => 'Operating System',
        'IpAddress' => 'IP Address',
        'MacAddress' => 'MAC Address',
        'SampleAgentStatus' => 'Sample Agent Status',
        'SampleComplianceState' => 'Sample Compliance State'
    };

    global SampleComputeCI() {
        super(SAMPLE_COMPUTE_LABELS);
    }

    // Child inventory: security vulnerabilities found on this device. Populated only when
    // "Sync Vulnerabilities" is enabled on the template. Each element is a NEW custom CI
    // type — see SampleVulnerabilityCI. Add more collections following this pattern.
    @AuraEnabled global List<SampleVulnerabilityCI> Vulnerabilities;

    // Standard asset-identity attributes (map to platform SD_* attribute developer names).
    @AuraEnabled global String AssetName;
    @AuraEnabled global String SerialNumber;
    @AuraEnabled global String HostName;
    @AuraEnabled global String OperatingSystem;
    @AuraEnabled global String IpAddress;
    @AuraEnabled global String MacAddress;

    // Source-specific custom attributes added to the STANDARD Compute type
    // (see cnfgItemAttrDefs/Sample*.cnfgItemAttrDef-meta.xml + SampleRegistrationQueueable).
    @AuraEnabled global String SampleAgentStatus;
    @AuraEnabled global String SampleComplianceState;

    // Set by the Flow to the CI type developer name this record should resolve to.
    @AuraEnabled global String cnfgItemTypeName;
}
