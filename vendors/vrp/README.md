# Huawei VRP (`vrp`)

Vendor `huawei`. This profile is a **custom add-on** — it is not a collector builtin, so importing it is how you get support for this NetOS.

## Profile highlights

- **Custom profile** — unlike the others, this one does not ship as a collector builtin. Import it to add Huawei support.
- Prompts are `<hostname>` / `[hostname]` rather than `#` / `>`.
- Paging disabled with `screen-length 0 temporary`.
- Uses `blocked-prefixes` to refuse config-mode commands, and an `auto-response` to survive the first-login password-change prompt.

Import it:

```bash
# via the Prelude MCP
collector_vendor_profiles action=import import_data=<contents of vendors/vrp/profile.json>

# via REST
curl -ks -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  --data-binary @vendors/vrp/profile.json \
  https://127.0.0.1:4030/api/v1/vendor-profiles/import   # add ?overwrite=true to replace
```

## Data models

No `vrp`-specific models yet — contributions welcome. The profile alone is still useful: it gives the collector correct path formats, prompt handling and version detection for this NetOS.

Transforms are NetOS-independent: see [`shared/transforms/`](../../shared/transforms).

## Verified against

**Not exercised in the reference lab.** The profile is derived from vendor documentation and field experience, not from a live device in our lab, so treat the protocol defaults as a starting point and verify against your own hardware.

A mapping's `netos` must match the target device, and the device must have that protocol enabled, before a subscription will collect data.
