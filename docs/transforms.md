# Transforms

Transforms post-process a mapped value before it reaches the output. There are two kinds:

1. **Built-in transforms** — 41 ready-made functions referenced by name in a mapping's
   `field-transforms` pipeline (`"in-octets": ["to_mbps"]`).
2. **User-defined transforms** — small **Starlark** expressions you create once (by name) and then
   reference the same way. The three in [`../shared/transforms/`](../shared/transforms) are examples.

A `field-transforms` entry is an **ordered pipeline**: each transform's output feeds the next.
Both built-in and user-defined names may be mixed in the same pipeline.

## Built-in transforms

| Category | Names |
|----------|-------|
| **BGP / ASN** | `as_plain`, `as_dot`, `bgp_community`, `bgp_ext_community` |
| **MIB enum decode** | `bgp_state`, `if_admin_status`, `if_oper_status`, `isis_adj_state`, `ospf_neighbor_state` |
| **Interface** | `speed_to_human` |
| **IP / MAC** | `ip_with_prefix`, `ip_with_netmask`, `ipv6_compress`, `ipv6_expand`, `mac_to_eui48`, `netmask_to_prefix` |
| **SNMP encoding** | `octetstring_to_hex`, `octetstring_to_mac`, `oid_last_segment`, `strip_null_bytes`, `timeticks_to_seconds`, `timeticks_to_uptime` |
| **Strings** | `base64_decode`, `hex_to_int`, `int_to_hex`, `lowercase`, `trim_whitespace`, `truncate_256`, `uppercase` |
| **Time** | `seconds_to_duration`, `unix_ms_to_iso`, `unix_to_iso` |
| **Unit scaling** | `bytes_to_gb`, `bytes_to_mb`, `celsius_to_fahrenheit`, `div_10`, `div_100`, `div_1000`, `mul_8`, `to_gbps`, `to_mbps` |

Example — decode SNMP IF-MIB integer enums to strings (see `vendors/ios-xr/models/snmp-if-mib-interfaces.json`):

```json
"field-transforms": {
  "admin-status": ["if_admin_status"],
  "oper-status":  ["if_oper_status"]
}
```

> **Built-in vs value-transforms.** Use a built-in (`if_oper_status`) when a decoder already exists.
> Use `value-transforms` (`{"UP":"up"}`) for ad-hoc string remapping that has no built-in.

## User-defined Starlark transforms

A user transform is a tiny Starlark function body. Rules:

- The input value is the variable **`value`**.
- You **must `return`** a value. A bare expression (no `return`) yields `nil` and the raw value
  passes through unchanged (with a WARN) — a common gotcha.
- The only Starlark-exclusive helper is **`round(number[, ndigits])`**.
- All 41 built-in transforms are **also callable** inside your expression (e.g. `to_mbps(...)`).
- Names are lowercase `snake_case`.

The example files use the `{ "name", "description", "code" }` shape, which maps 1:1 to the
`collector_transforms create` MCP arguments and the Web UI transforms form.

### Examples in this repo

`bytes_per_sec_to_mbps` — bytes/sec → Mbps (×8 to bits, then `to_mbps`, rounded):

```python
return round(to_mbps(value * 8), 1)
```

`bool_to_up_down` — boolean flag → `"up"`/`"down"` string:

```python
return "up" if value else "down"
```

`dbm_from_tenths` — optical power in tenths-of-dBm → dBm:

```python
return round(value / 10.0, 1)
```

> Note: `bytes_per_sec_to_mbps` rounds to **1** decimal even though its description says "2-decimal";
> the code is kept verbatim from the live collector. Adjust the `ndigits` arg to taste.

To use one in a model, reference it by name in a mapping pipeline, e.g.
`"in-octets": ["bytes_per_sec_to_mbps"]`.
