import { createElement } from "lwc";
import SampleSyncSettings from "c/sampleSyncSettings";

describe("c-sample-sync-settings", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  function createComponent() {
    const element = createElement("c-sample-sync-settings", {
      is: SampleSyncSettings
    });
    document.body.appendChild(element);
    return element;
  }

  it("is always valid — the only option is a boolean toggle", () => {
    const element = createComponent();

    const result = element.validate();

    expect(result.isValid).toBe(true);
    expect(result.errors).toHaveLength(0);
  });

  it("hydrates state from targetParams and echoes it back via getTargetParams", () => {
    const element = createComponent();

    element.targetParams = [{ name: "SyncVulnerabilities", value: "true" }];

    const params = element.getTargetParams();
    const asMap = Object.fromEntries(params.map((p) => [p.name, p.value]));

    expect(asMap.SyncVulnerabilities).toBe("true");
  });

  it("defaults to sync vulnerabilities disabled", () => {
    const element = createComponent();

    const params = element.getTargetParams();
    const asMap = Object.fromEntries(params.map((p) => [p.name, p.value]));

    expect(asMap.SyncVulnerabilities).toBe("false");
  });
});
