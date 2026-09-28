/*
 * PREPARE FOR UNINSTALL — run this BEFORE uninstalling the "CMDB Discovery Reference" package.
 *
 * WHY: the package's registration (SampleRegistrationQueueable) creates, at runtime, CI-type
 * bindings that reference the package's OWN packaged components:
 *   - CnfgItemTypeRelationDef  'Sample_Compute_Vulnerability'  (targets the packaged
 *                                                               SampleVulnerability CI type)
 *   - CnfgItemTypeAttrRelDef   'Sample_Compute_*'              (reference the packaged Sample
 *                                                               attribute defs)
 * A non-packaged record that references a packaged component BLOCKS the uninstall with:
 *   "Can't uninstall package because an external component is referencing a component in this
 *    package." (reasonCode 10)
 * The platform validates these references BEFORE the package's UninstallHandler runs, so the
 * package cannot clear them for you during uninstall — they must be removed first, here.
 *
 * HOW TO RUN (as an admin, before Setup > Installed Packages > Uninstall):
 *   sf apex run --file scripts/apex/prepare-for-uninstall.apex --target-org <your-org>
 * or paste this into Developer Console > Debug > Open Execute Anonymous Window.
 *
 * This script is self-contained (no namespace dependency). Equivalently, if you prefer to call
 * the packaged helper, run this one line instead (prefix with your package namespace):
 *   sfcmdbSample.SampleUninstall.prepareForUninstall();
 *
 * Idempotent: safe to run more than once; a no-op once the records are gone. After it succeeds,
 * uninstall the package normally — SampleUninstall.onUninstall then disables the Sample source.
 */
List<SObject> toDelete = new List<SObject>();
toDelete.addAll([SELECT Id FROM CnfgItemTypeRelationDef WHERE DeveloperName = 'Sample_Compute_Vulnerability']);
toDelete.addAll([SELECT Id FROM CnfgItemTypeAttrRelDef  WHERE DeveloperName LIKE 'Sample_Compute_%']);

if (toDelete.isEmpty()) {
    System.debug(LoggingLevel.INFO, 'prepare-for-uninstall: no blocking Sample CI-type bindings found — nothing to delete.');
} else {
    delete toDelete;
    System.debug(LoggingLevel.INFO, 'prepare-for-uninstall: deleted ' + toDelete.size()
        + ' blocking Sample CI-type binding(s). You can now uninstall the package.');
}
