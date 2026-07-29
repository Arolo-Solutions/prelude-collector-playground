# Nokia SR Linux (`srlinux`)

Vendor `nokia`. This profile ships as a collector **builtin** — it is here so you can read it, diff it, or import a modified copy.

## Profile highlights

- gNMI `module-prefix` paths with `json_ietf` encoding.
- CLI engine forced to `basic` (`environment cli-engine type basic`) — the default interactive engine is unusable over a scripted session.
- List keys often live **only** in the gNMI path predicate (e.g. `[name=…]`), not as a data leaf; the parser backfills the key field from the path.

Import it:

```bash
# via the Prelude MCP
collector_vendor_profiles action=import import_data=<contents of vendors/srlinux/profile.json>

# via REST
curl -ks -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  --data-binary @vendors/srlinux/profile.json \
  https://127.0.0.1:4030/api/v1/vendor-profiles/import   # add ?overwrite=true to replace
```

## Data models

No `srlinux`-specific models yet — contributions welcome. The profile alone is still useful: it gives the collector correct path formats, prompt handling and version detection for this NetOS.

This NetOS is also covered by the multivendor model [`shared/models/interface-state.json`](../../shared/models/interface-state.json), which maps the same normalized interface state across `eos`, `srlinux` and `ios-xr` — one model, three mappings.

Transforms are NetOS-independent: see [`shared/transforms/`](../../shared/transforms).

## Verified against

A device running Nokia SR Linux in the reference lab — gNMI :57400 (self-signed TLS).

A mapping's `netos` must match the target device, and the device must have that protocol enabled, before a subscription will collect data.
