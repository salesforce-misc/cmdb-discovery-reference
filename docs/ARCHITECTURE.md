# Architecture & extension guide

How the pieces fit together, and exactly what you swap out when you build your own package
from this reference.

## Runtime flow (discovery → CMDB)

```
   CMDB Discovery UI
        │  (customer picks the "Sample" probe, supplies a connection)
        ▼
   SyncSampleToCMDB  (App Framework flow template)
        │  [1] TRIGGER  triggerType = EnterpriseScaleExternalSystemChange
        ▼
   Generate_Scan_Id ─▶ Get_Device_Details ─▶ Map_Sample_Data_to_CI ─▶ Create_Sample_CI_Records
    [2] (platform)   [3] (externalConnector,  [4] TRANSFORM           [5] CMDB ACTION (platform:
                         bring-your-own            $Event.ObjectType.*     createIntegrationRecordsInCmdb)
                         connection)               -> SampleComputeCI
        │
        ▼
   SampleComputeCI ─────────────has──▶ Vulnerabilities[]
   (BaseParentCnfgItem)                (SampleVulnerabilityCI : BaseComponentCnfgItem)
   type: "Compute" (standard)          type: "Sample Vulnerability" (NEW custom type)
   + Sample Agent Status attr
   + Sample Compliance State attr
```

The chain is the canonical shape of a discovery flow: **trigger → transform → CMDB action**,
with a scan-id step and a bring-your-own connection step in between.

**The trigger is a binding, not just a type.** An `EnterpriseScaleExternalSystemChange` start
node only fires because it is bound to an event and a connection — `eventType` (`externalEvent`),
`eventName` (your connector's `<Connector>.<Operation>`, e.g. an "on new/updated device" op), and
`connection` (`${Variables.FlowConnection_Sample}`, resolved to the customer's registered External
Service when the template is instantiated). A start node with only `<triggerType>` deploys but
never fires. When you fork this, replace the placeholder `Sample.OnNewOrUpdatedDevice` event name
with the real operation your External Service exposes. The same connection reference is passed to
the fetch action (`Get_Device_Details`) via `setupReference` / `ExternalServiceRegistration` — this
sample follows the "event notifies, then fetch details" pattern; a connector whose event already
carries the full payload can drop the fetch step and map straight off `$Event.ObjectType.*`.

The transform node
(`Map_Sample_Data_to_CI`) maps the Compute fields, the two Sample attributes, and the
Vulnerability children — so every attribute and CI type the package ships is exercised there.
It shows the mapping idioms you'll use: direct field copy, a constant, a formula, and per-item
child mapping with `[$EachItem]`.

## The new CI type ("Sample Vulnerability") and its metadata

An incoming CI is matched to a CI type by NAME (`cnfgItemTypeName`); if the name doesn't
resolve to a type the org knows, the row is rejected. So a brand-new type must ship its full
definition. These files together define "Sample Vulnerability":

```
cnfgItemTypeDefs/SampleVulnerability            the type (isComponent = true → a child type)
        ▲
        ├── cnfgItemAttrDefs/SampleVulnerability{Id,Severity,Status}   its attributes
        ├── cnfgItemTypeAttrRelDefs/SampleVuln_*                       bind those attrs to the type
        ├── cnfgItemTypeIdentRules/Sample_IR_Vulnerability             identity rule (dedupe)
        │     └── cnfgItemTypeIdentFieldMaps/Sample_IF_Vuln_VulnerabilityId  identity = VulnerabilityId
        ├── contentassets/SampleVulnerabilityIcon                      UI icon (see below)
        └── SampleRegistrationQueueable (runtime)                      Compute ──part-of──▶ Vulnerability
```

Give the new type an icon so it doesn't fall back to the platform default: the type def's
`<contentAsset>` element names a `ContentAsset` by its `masterLabel`
(`SampleVulnerabilityIcon`), which ships as a `contentassets/` pair — the SVG bytes
(`SampleVulnerabilityIcon.asset`) plus its `.asset-meta.xml`. Swap in your own artwork when
you fork.

The type and its identity rule ship as metadata because they reference only this package's
own attributes. The Compute → Vulnerability link cannot: it points at the standard Compute
type and the standard Parent/Child relationship type, so `SampleRegistrationQueueable`
creates it at runtime (both objects are DML-createable) and degrades gracefully if that
standard data is absent.

Why the identity rule matters: a _component_ CI is identified relative to its parent. Without
an identity rule (or a primary attribute), every vulnerability under one computer would
collapse into a single record. The rule + field map make `VulnerabilityId` the match key, so
distinct CVEs on the same device stay distinct and re-sync as updates.

Why the relation def matters: it declares Vulnerability as a _possible child component_ of
Compute, so the children actually attach to the parent.

Contrast this with the two Compute attributes (Agent Status / Compliance State): they extend a
_standard_ type, so there's no new type def — just attribute defs, bound to Compute at runtime
by the Queueable (see below).

## Install-time registration (package install / upgrade)

```
   Package install ─▶ SamplePostInstall.onInstall(ctx)
        │
        ├─ previousVersion == null (first install)
        │     ├─ insert CnfgMgmtDiscoveryProbe / CnfgMgmtProbeFlowTmpl / CnfgMgmtProbePrvwAttrDef   (non-setup, synchronous)
        │     └─ System.enqueueJob(SampleRegistrationQueueable)                                     (setup, separate txn)
        │            ├─ create CnfgItemSourceDefinition "Sample"
        │            └─ bind the 2 Sample attributes to the standard Compute type (CnfgItemTypeAttrRelDef)
        │
        │  (The NEW Sample Vulnerability type ships as metadata — the cnfgItem* files — so it
        │   needs no runtime registration. Only the binding to the STANDARD Compute type is
        │   done here, because you can't package a binding against a standard type as metadata.)
        │
        └─ previousVersion != null (upgrade)
              └─ reconcileExistingRegistration()  (idempotent — no duplicates)
```

Everything runs in `AccessLevel.SYSTEM_MODE`. The non-setup / setup split is what avoids the
mixed-DML exception — that's why the source-enable + attribute-binding work is deferred to a
`Queueable` rather than done inline in `onInstall`.

## Uninstall (package removal)

Uninstall is a **two-step** operation — a required admin pre-step, then the uninstall itself:

```
   [STEP 1 — admin, BEFORE uninstall]  SampleUninstall.prepareForUninstall()
        ├─ delete CnfgItemTypeRelationDef 'Sample_Compute_Vulnerability'   (targets packaged type)
        └─ delete CnfgItemTypeAttrRelDef  'Sample_Compute_*'               (reference packaged attrs)

   [STEP 2 — platform, DURING a successful uninstall]  SampleUninstall.onUninstall(ctx)
        └─ disable the CnfgItemSourceDefinition "Sample"  (IsEnabled = false, IsActive = false)
```

**Why a pre-step is required.** `SampleRegistrationQueueable` creates, at runtime, records that
reference this package's **own packaged components**: the `Sample_Compute_Vulnerability` relation
_targets_ the packaged `SampleVulnerability` CI type, and the `Sample_Compute_*` attribute
bindings reference the packaged `Sample*` attribute defs. A non-packaged record that references a
packaged component makes the uninstall **fail outright**:

> Can't uninstall package because an external component is referencing a component in this
> package. (reasonCode 10)

This bites on **any org where registration actually ran** (any org with the standard Compute
type) — a bare scratch org never sees it because the Queueable degrades there and never creates
the references.

**Why `onUninstall` can't fix this itself.** The platform validates external references **before**
it invokes the `UninstallHandler`, so a handler that deletes the references never gets to run —
the uninstall is already rejected. There is no pre-uninstall Apex hook that runs before the
reference check. The references must therefore be removed **out of band, by an admin, before
initiating the uninstall** — that is what `prepareForUninstall()` is for. Run it via
`scripts/apex/prepare-for-uninstall.apex` (self-contained, no namespace dependency), or in
Execute Anonymous as `<namespace>.SampleUninstall.prepareForUninstall();`. It is idempotent.

**What `onUninstall` does (step 2).** Once the blocking references are gone and the uninstall
proceeds, `onUninstall` **disables** (does not delete) the source: disabling stops the probe from
surfacing/polling, while the `CnfgItemSourceDefinition` record — and the discovered CIs that carry
its `SourceName` — stay intact (deleting it would orphan that data, the very thing the
runtime-not-metadata design avoids). The `CnfgMgmt*` probe rows are _setup_ objects and are left
untouched (an uninstall context can't reliably split setup/non-setup DML across transactions while
the package's own Apex is being torn down), so `onUninstall` is kept to this one self-contained,
best-effort step — any failure is logged, never rethrown. Registered via `"uninstallScript"` in
`sfdx-project.json` (alongside `"postInstallScript"`, both inside the `packageDirectories` entry).

## What ships as metadata vs. what's created at runtime

Definitions you fully **own** ship as metadata. Anything that binds to a **standard** type the
package doesn't own is created at runtime by `SampleRegistrationQueueable`, against whatever the
target org actually has (with a graceful guard when the standard data isn't present).

| Definition                                                                                              | Ships as…                                                              |
| ------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Attributes (`CnfgItemAttrDef`) and their property groups (`CnfgItemAttrSetDef` + `CnfgItemAttrSetAttr`) | metadata                                                               |
| The new type and its identity (`CnfgItemTypeDef`, `CnfgItemTypeIdentRule`, `CnfgItemTypeIdentFieldMap`) | metadata                                                               |
| Attribute bindings to **your own** type (`CnfgItemTypeAttrRelDef` → Sample Vulnerability)               | metadata                                                               |
| The discovery source (`CnfgItemSourceDefinition`)                                                       | **runtime** (`SampleRegistrationQueueable`) — see uninstall note below |
| The discovery probe (`CnfgMgmtDiscoveryProbe` + flow template + preview attrs)                          | **runtime** (`SamplePostInstall`) — see uninstall note below           |
| Attribute bindings to the **standard** Compute type (`CnfgItemTypeAttrRelDef` → Compute)                | **runtime** (`SampleRegistrationQueueable`)                            |
| Relationship to a **standard** type (`CnfgItemTypeRelationDef` → Compute / `SD_PaCh`)                   | **runtime** (`SampleRegistrationQueueable`)                            |

Rule of thumb: **your own definitions ship as metadata; two things are deliberately created at
runtime instead** —

1. **Anything that references a standard type the package doesn't own** (the Compute attribute
   bindings and the Compute → Vulnerability relation), because the target org may not have that
   standard content yet — hence the `Test.isRunningTest()` guards in the Queueable.
2. **The discovery source and the discovery probe** (`CnfgItemSourceDefinition`,
   `CnfgMgmtDiscoveryProbe` + its flow template and preview attributes). These are runtime
   registration records that discovered data becomes associated with after install (CI records
   carry the source's `SourceName`; scans point at the probe). Keep them **out of packaged
   metadata** so that uninstalling the package doesn't remove records the discovered CI data
   depends on — create them at runtime instead (the source in `SampleRegistrationQueueable`, the
   probe in `SamplePostInstall`), and make the inserts **idempotent** so re-install/upgrade never
   duplicates them.

> Property groups: every attribute belongs to a property group (`CnfgItemAttrSetAttr` →
> `CnfgItemAttrSetDef`) — see the CMDB object-modeling documentation for the data model. This
> sample ships one group per concept (`Sample_Compute_Attributes`, `Sample_Vulnerability_Attributes`)
> and binds each attribute to it.

## What to change when you fork this

| You want to…                        | Change                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Rename the vendor                   | Replace `Sample` / `sfcmdbSample` everywhere; rename the `Sample*` classes, the LWC folder, the template folder, and the `cnfgItem*` files                                                                                                                                                                                                                                                                                                                                |
| Set your namespace                  | `sfdx-project.json` → `namespace`; the `apexClass` refs in the flow. `SamplePostInstall` detects the namespace at runtime, so there is no constant to edit                                                                                                                                                                                                                                                                                                                |
| Add an attribute to a standard type | Add an `@AuraEnabled` field to `SampleComputeCI` + a label-map entry; add a `cnfgItemAttrDefs/` file; register it in `SampleRegistrationQueueable.SAMPLE_ATTR_DEVNAMES`; map it in the transform                                                                                                                                                                                                                                                                          |
| Add a **new** CI type               | Follow the `SampleVulnerability` set: a `cnfgItemTypeDefs/` file, its `cnfgItemAttrDefs/`, `cnfgItemTypeAttrRelDefs/` bindings, and a `cnfgItemTypeIdentRules/` + `cnfgItemTypeIdentFieldMaps/` identity (all metadata); link it to its parent at runtime in `SampleRegistrationQueueable` (the link references the standard parent type, so it can't ship as metadata); add the matching `*CI` Apex class + a `List<>` on the parent + a `[$EachItem]` transform mapping |
| Real API calls                      | Replace `Sample.GetDeviceDetails` in the flow with your External Service operations; the connection stays bring-your-own                                                                                                                                                                                                                                                                                                                                                  |
| Config UI options                   | Edit `lwc/sampleSyncSettings/` and the matching entries in `variables.json` / `layout.json`                                                                                                                                                                                                                                                                                                                                                                               |

## What is deliberately NOT here

- **Custom enrichment / mapper Apex actions.** A real integration often adds an
  `@InvocableMethod` to reshape or enrich its specific payload. That is integration-specific,
  so the sample doesn't include it. If your payload needs it, add your own invocable action and
  drop it into the flow between the transform and the CMDB action.
- **Vendor API pagination, rate-limiting, auth, and error handling.**
- **The full ~100-field device model** (kept to a representative handful).
- **Deep relationship graphs** — one new type with one identity attribute is enough to show
  the pattern without the clutter.
- **Any credentials, endpoints, or connection secrets** — connections are bring-your-own via
  an External Service Registration you create in your own org.
