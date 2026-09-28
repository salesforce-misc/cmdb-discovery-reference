# CMDB Discovery Integration — Reference Package

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE.txt)
[![CI](https://github.com/salesforce-misc/cmdb-discovery-reference/actions/workflows/ci.yml/badge.svg)](https://github.com/salesforce-misc/cmdb-discovery-reference/actions/workflows/ci.yml)

A **simple, working sample** of a Salesforce second-generation managed package (2GP) that
shows **how to build a CMDB discovery integration** — the plumbing and the extension points,
with **no vendor-specific business logic**.

It is built for the _Agentforce for IT Service_ developer audience: **clone it, rename the
`Sample*` pieces, and fill in your own product's logic**. It is intentionally small — just
enough to convey the shape of an integration.

> Neutral vendor name: **Sample**. Namespace: **`sfcmdbSample`**. No credentials, secrets,
> or private endpoints are shipped anywhere — connections are _bring-your-own_ via an
> External Service Registration you create in your own org.

## The story this sample tells

**Sample is an endpoint vulnerability-management product.** It discovers managed **computers**
and the **security vulnerabilities** found on each one. Everything the package ships is used
to tell exactly that story, end to end — nothing is included "just to show the API":

- A discovered **computer** maps to the platform's **standard Compute CI type**, enriched
  with two Sample-specific attributes: **Sample Agent Status** and **Sample Compliance State**.
  → This shows _extending a standard CI type with your own attributes_.
- Each computer's **vulnerabilities** map to **Sample Vulnerability** — a **brand-new custom
  CI type** this package defines, attached as a child collection of the computer.
  → This shows _adding a new CI type of your own_.

The discovery flow's transform maps precisely these — the two Compute attributes and the
Vulnerability children — so the CI classes, the attributes, and the new type are all exercised
in one place.

## What's in the box

```
force-app/main/default/
├── classes/
│   ├── SampleComputeCI.cls              Parent CI DTO — standard Compute type + 2 attributes
│   ├── SampleVulnerabilityCI.cls        Child CI DTO — the NEW "Sample Vulnerability" type
│   ├── SamplePostInstall.cls            Creates the discovery probe at install time
│   ├── SampleRegistrationQueueable.cls  Creates the source + binds the 2 attributes to Compute
│   ├── SampleUninstall.cls              prepareForUninstall() pre-step + disables source on uninstall
│   └── *Test.cls                        Tests
├── lwc/sampleSyncSettings/              Custom Property Editor for the template's config page
├── appTemplates/SyncSampleToCMDB/       App Framework flow template (the discovery flow)
├── cnfgItemAttrDefs/                    5 attributes (2 for Compute, 3 for Vulnerability)
├── cnfgItemAttrSetDefs/                 Property groups the attributes belong to
├── cnfgItemAttrSetAttrs/                Binds each attribute to its property group
├── cnfgItemTypeDefs/                    The new "Sample Vulnerability" CI type
├── cnfgItemTypeAttrRelDefs/             Binds the 3 Vulnerability attributes to the type
├── cnfgItemTypeIdentRules/              Identity rule: how CMDB dedupes vulnerabilities
├── cnfgItemTypeIdentFieldMaps/          Which attribute forms that identity (VulnerabilityId)
├── contentassets/SampleVulnerabilityIcon.*  Icon for the new CI type (linked from its typeDef)
└── staticresources/SampleIcon.*         Probe icon

(Three things are created at runtime rather than shipped as metadata: the discovery source
 and the Compute → Vulnerability parent/child link in SampleRegistrationQueueable, and the
 discovery probe in SamplePostInstall — see the ship-vs-runtime table below for why.)
```

## The two ways to model data in CMDB (both shown here)

|                             | Extend a **standard** type                                                                                     | Add a **new** type                                                                                                                                                          |
| --------------------------- | -------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Example                     | Sample Agent Status / Compliance State on **Compute**                                                          | **Sample Vulnerability**                                                                                                                                                    |
| Define the attributes       | `cnfgItemAttrDefs/`                                                                                            | `cnfgItemAttrDefs/`                                                                                                                                                         |
| Define the type             | — (Compute already exists)                                                                                     | `cnfgItemTypeDefs/SampleVulnerability`                                                                                                                                      |
| Bind attributes to the type | at runtime in `SampleRegistrationQueueable` (you can't ship a binding to a standard type as packaged metadata) | `cnfgItemTypeAttrRelDefs/` (metadata — you own the type)                                                                                                                    |
| Make instances dedupe       | uses Compute's built-in identity                                                                               | `cnfgItemTypeIdentRules/` + `cnfgItemTypeIdentFieldMaps/`                                                                                                                   |
| Attach as a child           | n/a (Compute is the parent)                                                                                    | at runtime in `SampleRegistrationQueueable` (the link points at the standard Compute type + standard Parent/Child relationship type, so it can't ship as packaged metadata) |

The split is deliberate and matches how real integrations ship: attributes added to a
standard type are bound _at runtime_ (you don't own the standard type), while a brand-new CI
type you own is defined entirely in _metadata_. This sample does both.

> **Why the runtime binding?** Definitions you own ship as metadata; a binding to a _standard_
> type the package doesn't own is created at install time in Apex instead. See
> [What ships as metadata vs. runtime](docs/ARCHITECTURE.md#what-ships-as-metadata-vs-whats-created-at-runtime)
> for the full table.

## The discovery flow (trigger → transform → action)

`appTemplates/SyncSampleToCMDB/flows/SyncSampleToCMDB.xml`:

```
[1] TRIGGER  (EnterpriseScaleExternalSystemChange)
      -> [2] Generate_Scan_Id        platform action: open a discovery scan
      -> [3] Get_Device_Details      externalConnector: your bring-your-own connection
      -> [4] Map_Sample_Data_to_CI   TRANSFORM: event payload -> SampleComputeCI
      |                                 - Compute fields + Agent Status + Compliance State
      |                                 - Vulnerabilities[] children (cnfgItemTypeName = "Sample Vulnerability")
      -> [5] Create_Sample_CI_Records CMDB ACTION: createIntegrationRecordsInCmdb
```

The transform shows the mapping idioms you'll use: direct field copy, constant, formula, and
per-item child mapping with `[$EachItem]`.

## What is deliberately NOT here

- **No custom enrichment / mapper Apex actions.** Real integrations often add an
  `@InvocableMethod` to reshape or enrich their specific payload. That is _integration-specific_
  — add your own if your payload needs it; the sample doesn't presume it.
- **No vendor field catalogs, pagination, auth, or parsing logic.**
- **No credentials or endpoints** — connections are bring-your-own.

## Build & deploy

> **Set your own namespace first.** `sfcmdbSample` throughout this repo is a
> **placeholder** — it's the sample's namespace, not yours. Before you build a
> managed package, register your own namespace and replace `sfcmdbSample` in
> `sfdx-project.json` (the `namespace` field), in the flow's `apexClass` refs
> (`appTemplates/SyncSampleToCMDB/flows/SyncSampleToCMDB.xml`), and in the probe
> icon reference (`staticresources/SampleIcon.resource-meta.xml`). `SamplePostInstall`
> reads the namespace at runtime, so there is no Apex constant to change.

```bash
# 1. Create a namespace-registered scratch org from your Dev Hub
sf org create scratch -f config/project-scratch-def.json -a cmdb-ref --duration-days 7

# 2. Push the source and run the tests
sf project deploy start -o cmdb-ref
sf apex run test -o cmdb-ref -l RunLocalTests -w 10

# 3. (Optional) create a 2GP managed package version from this source
sf package create --name "CMDB Discovery Reference" --package-type Managed --path force-app
sf package version create --package "CMDB Discovery Reference" --installation-key-bypass --wait 20
```

The scratch-org definition enables the required features: **`CMDB`** and **`AssetDiscovery`**.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the pieces fit and exactly what to
change when you fork.

## Uninstalling

Uninstall is a **two-step** operation. The package creates a few CI-type bindings at runtime
that reference its own packaged components (the Compute→Vulnerability relation and the Compute
attribute bindings), and Salesforce **blocks** an uninstall while a non-packaged record
references a packaged component (`reasonCode 10`). The platform checks this _before_ any
uninstall handler runs, so the package can't clear it for you — an admin must remove those
bindings first:

```bash
# 1. Remove the runtime bindings that would otherwise block the uninstall
sf apex run --file scripts/apex/prepare-for-uninstall.apex --target-org <your-org>
#    (or, in Execute Anonymous:  <namespace>.SampleUninstall.prepareForUninstall();  — idempotent)

# 2. Now uninstall normally (onUninstall then disables the Sample source)
sf package uninstall --package "CMDB Discovery Reference" --target-org <your-org>
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#uninstall-package-removal) for why this is
required and why it can't be done from the uninstall handler.

## Developing locally

```bash
npm install          # ESLint, Prettier, and the LWC Jest test runner
npm run lint         # lint the LWC / Aura JavaScript
npm run prettier     # auto-format
npm run test:unit    # LWC unit tests
```

## Open-sourcing this

This repo is released under the **[Apache License 2.0](LICENSE.txt)** — a permissive
license (with an explicit patent grant) that lets partners clone and adapt the sample
into their own products. Retain the `LICENSE.txt` and its attribution notices in any
derivative work, per the license terms.

Community and governance files follow the [salesforce/oss-template](https://github.com/salesforce/oss-template):
`CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `SECURITY.md`, and `CODEOWNERS`. CI runs via
`.github/workflows/ci.yml` (lint, Prettier, and LWC Jest with coverage).

Before publishing externally, follow the OSPO **oss-request2** process (VP + manager +
Legal + Security approvals). Nothing here contains hard-coded credentials, private
endpoints, or non-public deployment details — keep it that way.
