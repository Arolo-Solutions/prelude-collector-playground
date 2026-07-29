# Cisco NX-OS (`nxos`)

Vendor `cisco`. This profile ships as a collector **builtin** — it is here so you can read it, diff it, or import a modified copy.

## Profile highlights

- gNMI uses `bare-slash` paths with `json` encoding and origin `device`.
- Embedded YANG under `vendor/cisco/nx`.

Import it:

```bash
# via the Prelude MCP
collector_vendor_profiles action=import import_data=<contents of vendors/nxos/profile.json>

# via REST
curl -ks -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  --data-binary @vendors/nxos/profile.json \
  https://127.0.0.1:4030/api/v1/vendor-profiles/import   # add ?overwrite=true to replace
```

## Data models

No `nxos`-specific models yet — contributions welcome. The profile alone is still useful: it gives the collector correct path formats, prompt handling and version detection for this NetOS.

Transforms are NetOS-independent: see [`shared/transforms/`](../../shared/transforms).

## Verified against

**Not exercised in the reference lab.** The profile is derived from vendor documentation and field experience, not from a live device in our lab, so treat the protocol defaults as a starting point and verify against your own hardware.

A mapping's `netos` must match the target device, and the device must have that protocol enabled, before a subscription will collect data.
