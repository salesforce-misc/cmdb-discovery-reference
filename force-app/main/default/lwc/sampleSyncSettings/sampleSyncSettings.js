import { LightningElement, api, track } from "lwc";

/**
 * Custom Property Editor (CPE) for the Sample discovery flow template.
 *
 * The App Framework renders this on the template's Configure page (see the
 * lightning__dynamicComponent capability in the -meta.xml). The framework contract is:
 *   - `targetParams` (setter) receives the current param values to hydrate the UI.
 *   - `getTargetParams()` returns the params to persist.
 *   - `validate()` returns { isValid, errors } and blocks Next when invalid.
 *   - dispatch a `targetparamchanged` CustomEvent whenever a value changes.
 *
 * This sample exposes a single on-story option: whether to also sync the
 * vulnerabilities discovered on each computer as child CIs. Labels and param names
 * are inlined below to keep the sample in one file.
 */
const LABELS = {
  SyncVulnerabilities: "Sync Vulnerabilities"
};

const PARAM_SYNC_VULNERABILITIES = "SyncVulnerabilities";

export default class SampleSyncSettings extends LightningElement {
  @api mode = "create";

  @track syncVulnerabilities = false;

  labels = LABELS;

  get isViewMode() {
    return this.mode === "view";
  }

  @api
  get targetParams() {
    return this._targetParams;
  }
  set targetParams(value) {
    this._targetParams = value;
    if (Array.isArray(value)) {
      value.forEach((p) => {
        if (p.name === PARAM_SYNC_VULNERABILITIES) {
          this.syncVulnerabilities = p.value === "true" || p.value === true;
        }
      });
    }
  }

  handleToggleChange(event) {
    this.syncVulnerabilities = event.target.checked;
    this.dispatchEvent(
      new CustomEvent("targetparamchanged", {
        detail: {
          name: PARAM_SYNC_VULNERABILITIES,
          newValue: String(this.syncVulnerabilities)
        }
      })
    );
  }

  @api
  validate() {
    // The only option is a boolean toggle, so there is nothing to validate.
    return { isValid: true, errors: [] };
  }

  @api
  getTargetParams() {
    return [
      {
        name: PARAM_SYNC_VULNERABILITIES,
        value: String(this.syncVulnerabilities)
      }
    ];
  }
}
