# Cisco IOS-XR (`ios-xr`)

Vendor `cisco`. This profile ships as a collector **builtin** — it is here so you can read it, diff it, or import a modified copy.

## Profile highlights

- gNMI paths use the `module-prefix` form with `json_ietf` encoding.
- Embedded YANG under `vendor/cisco/xr` — the YANG tree browser works offline for this NetOS.
- SNMP version detected from `Cisco IOS XR Software … Version <x>`.

Import it:

```bash
# via the Prelude MCP
collector_vendor_profiles action=import import_data=<contents of vendors/ios-xr/profile.json>

# via REST
curl -ks -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  --data-binary @vendors/ios-xr/profile.json \
  https://127.0.0.1:4030/api/v1/vendor-profiles/import   # add ?overwrite=true to replace
```

## Data models

Models under [`models/`](models) target `ios-xr` specifically.

| File | Protocol(s) | What it demonstrates |
|------|-------------|----------------------|
| [`oc-interfaces.json`](models/oc-interfaces.json) | gNMI + NETCONF | One model, two protocols. Nested `counters.*` source keys, `value-transforms`, and `ignore-values` to skip `Null0`. |
| [`oc-bgp-neighbor.json`](models/oc-bgp-neighbor.json) | gNMI | OpenConfig BGP session state. Enum normalization via `value-transforms`; `format: ip-address`. |
| [`xr-native-bgp-neighbor.json`](models/xr-native-bgp-neighbor.json) | gNMI | Cisco **native** model (`Cisco-IOS-XR-ipv4-bgp-oper`) instead of OpenConfig. Typed `int32`/`int64` fields. |
| [`oc-isis-adjacency.json`](models/oc-isis-adjacency.json) | gNMI | IS-IS adjacencies. State-prefixed key source (`state.system-id`); `format: mac-address`. |
| [`snmp-if-mib-interfaces.json`](models/snmp-if-mib-interfaces.json) | SNMP | `snmp-walk-oids` over the standard IF-MIB, decoding integer enums with the built-in `if_admin_status` / `if_oper_status` transforms. |
| [`cli-xr-interface-summary.json`](models/cli-xr-interface-summary.json) | CLI | A **GoTTP** `cli-template` parsing `show ipv4 interface brief`, dropping the header row with `ignore-values`. |

This NetOS is also covered by the multivendor model [`shared/models/interface-state.json`](../../shared/models/interface-state.json), which maps the same normalized interface state across `eos`, `srlinux` and `ios-xr` — one model, three mappings.

Transforms are NetOS-independent: see [`shared/transforms/`](../../shared/transforms).

## Verified against

A device running Cisco IOS-XR in the reference lab — gNMI :57400 · CLI :22 · SNMP :161.

A mapping's `netos` must match the target device, and the device must have that protocol enabled, before a subscription will collect data.
