/**
 * Post-install handler invoked by the platform after the managed package installs — and
 * on EVERY upgrade. It kicks off registration of the discovery probe that ties this
 * package's flow template, custom property editor, and icon together in the CMDB
 * discovery UI, plus the CI-type source/relationship definitions.
 *
 * WHY THIS DOES NO DML ITSELF (MIXED-DML + INSTALL-ABORT)
 * ------------------------------------------------------
 * Two independent facts force all registration DML into async jobs enqueued from here:
 *
 *  1. A post-install handler must NEVER throw. An uncaught exception aborts the whole
 *     package install for the subscriber ("The post install script failed.") — and the
 *     platform surfaces no stack trace in logs or the failure email, so it's undebuggable
 *     from the outside.
 *  2. The registration touches two DML families the platform will not mix in one
 *     transaction: CnfgMgmt* probe entities are *setup* objects; CnfgItem* source/relation
 *     definitions are *non-setup* objects. The install transaction itself does DML, so any
 *     DML here — of either family — risks MIXED_DML_OPERATION and aborts the install.
 *
 * The fix for both: onInstall performs no DML. It only enqueues two Queueables, one per
 * family. System.enqueueJob is not DML, so it's safe in the install transaction, and each
 * job then runs its inserts in its own clean transaction:
 *   - SampleProbeRegistrationQueueable  -> CnfgMgmt* (setup) probe rows
 *   - SampleRegistrationQueueable       -> CnfgItem*  (non-setup) source / relation defs
 *
 * Both jobs are idempotent and safe to re-run on upgrade. Diagnose failures in-org via
 * AsyncApexJob.ExtendedStatus (async Apex, unlike the install pipeline, is queryable).
 */
global without sharing class SamplePostInstall implements InstallHandler {

    global void onInstall(InstallContext ctx) {
        // Belt-and-suspenders: even enqueuing must not throw out of the install pipeline.
        try {
            Boolean isUpgrade = ctx.previousVersion() != null;
            // Two separate jobs -> two separate transactions -> setup and non-setup DML
            // never mix with each other or with the install transaction.
            System.enqueueJob(new SampleProbeRegistrationQueueable(isUpgrade));
            System.enqueueJob(new SampleRegistrationQueueable());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                '[SamplePostInstall] Failed to enqueue registration; install will still complete: '
                + e.getTypeName() + ' - ' + e.getMessage() + ' | line ' + e.getLineNumber()
                + '\n' + e.getStackTraceString());
        }
    }
}
