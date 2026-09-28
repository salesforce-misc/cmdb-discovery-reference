/**
 * Uninstall support — two distinct jobs, run at two distinct times:
 *
 *   1. prepareForUninstall()  — an ADMIN-INVOKED pre-step, run BEFORE the admin clicks
 *      Uninstall. It deletes the runtime CI-type bindings that reference this package's OWN
 *      packaged components, because those references BLOCK the uninstall (see below).
 *   2. onUninstall()          — the platform's UninstallHandler hook, run DURING a successful
 *      uninstall. It only tidies the source; it cannot clear the blocking references itself.
 *
 * WHY A PRE-STEP IS REQUIRED (and why onUninstall can't do this)
 * -------------------------------------------------------------
 * SampleRegistrationQueueable creates, at runtime, non-packaged records that point at this
 * package's own PACKAGED components:
 *   - CnfgItemTypeRelationDef 'Sample_Compute_Vulnerability' — its TARGET is the packaged
 *     SampleVulnerability CI type.
 *   - CnfgItemTypeAttrRelDef  'Sample_Compute_*'             — reference the packaged Sample
 *     attribute defs (SampleAgentStatus / SampleComplianceState).
 * A non-packaged record that references a packaged component makes the uninstall fail outright:
 * "Can't uninstall package because an external component is referencing a component in this
 * package" (reasonCode 10). This happens on ANY org where registration actually ran (any org
 * with the standard Compute type) — it was not seen in a bare scratch org only because
 * SampleRegistrationQueueable degrades there and never creates the references.
 *
 * These records CANNOT be cleared from onUninstall: the platform validates external references
 * BEFORE it invokes the UninstallHandler, so a handler that deletes them never gets to run — the
 * uninstall is already rejected. (Verified empirically; there is no pre-uninstall Apex hook that
 * runs before the reference check.) The references must therefore be removed OUT OF BAND, by an
 * admin, before initiating the uninstall — that is what prepareForUninstall() is for. Ship it as
 * the documented "prepare for uninstall" step (see README / docs/ARCHITECTURE.md and
 * scripts/apex/prepare-for-uninstall.apex).
 *
 * WHAT onUninstall DELIBERATELY DOESN'T DO
 * ----------------------------------------
 * It DISABLES the source (clears IsEnabled / IsActive) rather than DELETING it. Disabling stops
 * the probe from surfacing/polling, while the CnfgItemSourceDefinition record — and the
 * discovered CIs that carry its SourceName — stay intact. Deleting the source would orphan that
 * discovered data, which is exactly what the runtime-not-metadata design set out to avoid.
 *
 * Everything touched here (CnfgItemSourceDefinition / CnfgItemTypeRelationDef /
 * CnfgItemTypeAttrRelDef) is a CnfgItem* *non-setup* object, so it all runs cleanly in one
 * transaction — no MIXED_DML against the setup-object CnfgMgmt* probe rows, which are left
 * untouched here. Each step is best-effort and self-contained: a failure is logged, never
 * rethrown, so a cleanup hiccup can't itself abort the work.
 */
global without sharing class SampleUninstall implements UninstallHandler {

    private static final String SOURCE_DEVNAME       = 'Sample';
    private static final String REL_DEVNAME          = 'Sample_Compute_Vulnerability';
    private static final String ATTR_REL_DEVNAME_PFX = 'Sample_Compute_%';

    /**
     * ADMIN-INVOKED pre-uninstall cleanup. Run this BEFORE uninstalling the package (e.g. via
     * scripts/apex/prepare-for-uninstall.apex, or `<namespace>.SampleUninstall.prepareForUninstall();`
     * in Execute Anonymous). It deletes the runtime CI-type bindings that reference this package's
     * packaged components — the records that otherwise block the uninstall with reasonCode 10.
     * Idempotent: safe to run more than once, and a no-op if the records are already gone.
     */
    global static void prepareForUninstall() {
        deleteRuntimeTypeBindings();
    }

    global void onUninstall(UninstallContext context) {
        // NOTE: this runs only AFTER the platform's external-reference validation passes, so by
        // the time we're here the blocking bindings must already be gone (prepareForUninstall()).
        // All we can usefully do at uninstall time is tidy the source.
        disableSource();
    }

    /**
     * Deletes the runtime CI-type bindings that reference this package's packaged components —
     * the CnfgItemTypeRelationDef 'Sample_Compute_Vulnerability' and the 'Sample_Compute_*'
     * CnfgItemTypeAttrRelDef rows. Clearing these removes the external references so the packaged
     * CI type and attribute defs they point at can be torn down with the package.
     */
    private static void deleteRuntimeTypeBindings() {
        try {
            List<SObject> toDelete = new List<SObject>();
            toDelete.addAll(Database.query(
                'SELECT Id FROM CnfgItemTypeRelationDef WHERE DeveloperName = :REL_DEVNAME',
                AccessLevel.SYSTEM_MODE));
            toDelete.addAll(Database.query(
                'SELECT Id FROM CnfgItemTypeAttrRelDef WHERE DeveloperName LIKE :ATTR_REL_DEVNAME_PFX',
                AccessLevel.SYSTEM_MODE));
            if (!toDelete.isEmpty()) {
                Database.delete(toDelete, AccessLevel.SYSTEM_MODE);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'SampleUninstall: failed to delete runtime CI-type bindings: ' + e.getMessage());
        }
    }

    private void disableSource() {
        try {
            List<CnfgItemSourceDefinition> existing = Database.query(
                'SELECT Id, IsEnabled, IsActive FROM CnfgItemSourceDefinition '
                + 'WHERE DeveloperName = :SOURCE_DEVNAME LIMIT 1',
                AccessLevel.SYSTEM_MODE);
            if (existing.isEmpty()) return;

            CnfgItemSourceDefinition src = existing[0];
            if (src.IsEnabled == false && src.IsActive == false) return;

            src.IsEnabled = false;
            src.IsActive  = false;
            Database.update(src, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'SampleUninstall: failed to disable source ' + SOURCE_DEVNAME + ': ' + e.getMessage());
        }
    }
}
