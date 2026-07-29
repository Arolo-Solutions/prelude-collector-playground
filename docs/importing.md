# Importing examples

Every `*.json` under [`../vendors/<netos>/models/`](../vendors) and
[`../shared/models/`](../shared/models) is an import-ready model export. Files under
[`../shared/transforms/`](../shared/transforms) are user-defined Starlark transforms in
`{ "name", "description", "code" }` form. Vendor profiles live at
`../vendors/<netos>/profile.json` — see [vendor-profiles.md](vendor-profiles.md).

Pick whichever loading path fits your workflow — MCP, Web UI, or REST. **Import a transform a model
depends on before the model**, so the transform name resolves.

## 1. Prelude MCP (recommended for agents/automation)

Import a model — pass the file contents as `import_data`:

```
collector_models    action=import   import_data=<contents of vendors/ios-xr/models/oc-interfaces.json>
```

Create a user-defined transform from a transform file's fields:

```
collector_transforms action=create  name=bytes_per_sec_to_mbps \
                      description="Convert byte/sec counter to Mbps" \
                      code="return round(to_mbps(value * 8), 1)"
```

Verify after import:

```
collector_test_model    / collector_snapshots get   # see normalized records
collector_validate_pipeline                          # device + model + mapping + output check
collector_snmp_browser / collector_test_path         # confirm SNMP OIDs / gNMI paths resolve
collector_test_cli                                   # confirm CLI command output (for TTP tuning)
```

## 2. Web UI

1. **Models → Import**, upload a `vendors/<netos>/models/*.json` or `shared/models/*.json` file. The model, its fields, and all mappings are created.
2. **Transforms → New**, paste the `name` / `description` / `code` from a `shared/transforms/*.json` file.
3. Open the imported model's mapping editor and use **Step 2 · Test & Generate** to run a live test
   against a device — this is the place to confirm the CLI/TTP example parses your device's output.

## 3. REST API

Auth uses a bearer token (`make token`, or `go run . user token -u admin -d 'import'`).

**Export** an existing model (this is exactly the JSON stored here):

```bash
curl -ks -H "Authorization: Bearer $TOKEN" \
  https://127.0.0.1:4030/api/v1/models/2/export
```

**Import** a model — POST the file as the body. The `{id}` in the path is ignored; a **new** model is
created (HTTP 201):

```bash
curl -ks -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  --data-binary @vendors/ios-xr/models/oc-interfaces.json \
  https://127.0.0.1:4030/api/v1/models/0/import
```

## Notes & caveats

- The model exports were taken from a live collector and **round-trip losslessly**.
- `vendors/ios-xr/models/snmp-if-mib-interfaces.json` and `vendors/ios-xr/models/cli-xr-interface-summary.json` were authored and
  verified against an ios-xr device via `collector_test_path` (SNMP OIDs) and `collector_test_cli`
  (CLI output). After importing the CLI example, confirm the **GoTTP** template against *your* device's
  output in the mapping editor — column layouts vary by platform/version.
- A mapping's `netos` must match the target device's NetOS, and the device must have that protocol
  enabled, before a subscription will collect data.
