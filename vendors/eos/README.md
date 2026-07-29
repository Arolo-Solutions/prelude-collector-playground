# Arista EOS (`eos`)

Vendor `arista`. This profile ships as a collector **builtin** — it is here so you can read it, diff it, or import a modified copy.

## Profile highlights

- gNMI uses `bare-slash` paths with `json` encoding.
- `split-prefix` notification style — the prefix and the leaf arrive in separate parts of the update, which the parser rejoins.
- Paging disabled with `terminal length 0`.

Import it:

```bash
# via the Prelude MCP
collector_vendor_profiles action=import import_data=<contents of vendors/eos/profile.json>

# via REST
curl -ks -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  --data-binary @vendors/eos/profile.json \
  https://127.0.0.1:4030/api/v1/vendor-profiles/import   # add ?overwrite=true to replace
```

## Data models

No `eos`-specific models yet — contributions welcome. The profile alone is still useful: it gives the collector correct path formats, prompt handling and version detection for this NetOS.

This NetOS is also covered by the multivendor model [`shared/models/interface-state.json`](../../shared/models/interface-state.json), which maps the same normalized interface state across `eos`, `srlinux` and `ios-xr` — one model, three mappings.

Transforms are NetOS-independent: see [`shared/transforms/`](../../shared/transforms).

## Verified against

A device running Arista EOS in the reference lab — gNMI :6030 (plaintext).

A mapping's `netos` must match the target device, and the device must have that protocol enabled, before a subscription will collect data.
