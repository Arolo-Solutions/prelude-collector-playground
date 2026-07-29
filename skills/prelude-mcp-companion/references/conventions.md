# Prelude MCP Conventions & Data Reference

## JSON Double-Encoding Convention

**Critical gotcha**: Protocol-specific array and object fields in mappings are stored as JSON strings within the JSON body. When calling MCP tools, you must pass them as JSON-encoded strings:

Affected fields: `gnmi_paths`, `snmp_walk_oids`, `snmp_scalar_oids`, `netconf_filter_paths`, `cli_commands`, `field_mappings`, `field_transforms`, `value_transforms`, `ignore_values`, `version_constraints`

Example for `collector_mappings` tool:
```
gnmi_paths:       "[\"openconfig-interfaces:interfaces/interface/state\"]"
field_mappings:   "{\"name\": \"interface-name\", \"mtu\": \"mtu\"}"
field_transforms: "{\"admin-status\": [\"if_admin_status\"]}"
```

**Exception**: `cli_template` is a plain string, NOT JSON-encoded.

## All JSON Field Names Use kebab-case

The collector API uses kebab-case for all JSON field names: `device-id`, `net-os`, `is-active`, `field-type`, etc.

## Valid Field Types

| Type | Description |
|------|-------------|
| `string` | Text value (default) |
| `int32` | 32-bit signed integer |
| `int64` | 64-bit signed integer |
| `uint32` | 32-bit unsigned integer |
| `uint64` | 64-bit unsigned integer |
| `float32` | 32-bit float |
| `float64` | 64-bit float |
| `boolean` | True/false |

### Valid Formats (by base type)

| Base Type | Valid Formats |
|-----------|---------------|
| `string` | `ipv4`, `ipv6`, `ip-address`, `ip-prefix`, `mac-address`, `bgp-community`, `oid`, `duration`, `hostname`, `route-distinguisher`, `date-and-time`, `phys-address`, `domain-name`, `uri` |
| `uint32` | `as-number`, `vlan-id`, `port-number` |
| `uint64` | `as-number` |

## Mapping Unique Constraint

Each mapping must be unique by `(protocol, netos, version-constraints)` within a model. Duplicate combinations return 400.

## Built-in Transform Functions

Transforms applied in pipeline order via `field_transforms`. Output of one feeds into the next.

### BGP
| Name | Description |
|------|-------------|
| `as_plain` | ASN asdot+ to plain decimal |
| `as_dot` | ASN integer to asdot+ (65536 → "1.0") |
| `bgp_community` | uint32 to "HI:LO" |
| `bgp_ext_community` | uint64 to "TYPE:HI:LO" |
| `bgp_state` | FSM integer 1-6 to state name |

### Interface
| Name | Description |
|------|-------------|
| `if_admin_status` | Integer 1-3 to "up"/"down"/"testing" |
| `if_oper_status` | Integer 1-7 to state name |
| `speed_to_human` | Bits/sec to "1G", "100M" etc. |

### IP / MAC
| Name | Description |
|------|-------------|
| `ip_with_prefix` | 32-bit int to dotted-quad |
| `ip_with_netmask` | Subnet mask to "/24" |
| `ipv6_compress` | IPv6 to compressed form |
| `ipv6_expand` | IPv6 to full 8-group |
| `mac_to_eui48` | Any MAC to "aa:bb:cc:dd:ee:ff" |
| `netmask_to_prefix` | Netmask to prefix-length int |

### Routing
| Name | Description |
|------|-------------|
| `isis_adj_state` | Integer 1-3 to "down"/"initializing"/"up" |
| `ospf_neighbor_state` | Integer 1-8 to state name |

### SNMP
| Name | Description |
|------|-------------|
| `octetstring_to_hex` | Bytes to "aa:bb:cc" |
| `octetstring_to_mac` | 6-byte to MAC string |
| `oid_last_segment` | OID to last segment |
| `strip_null_bytes` | Remove \x00 |
| `timeticks_to_seconds` | TimeTicks to seconds float |
| `timeticks_to_uptime` | TimeTicks to "Xd Xh Xm Xs" |

### Strings
| Name | Description |
|------|-------------|
| `base64_decode` | Base64 to decoded string |
| `hex_to_int` | Hex to integer |
| `int_to_hex` | Integer to "0x" hex |
| `lowercase` | To lowercase |
| `trim_whitespace` | Trim whitespace |
| `truncate_256` | Truncate to 256 chars |
| `uppercase` | To uppercase |

### Time
| Name | Description |
|------|-------------|
| `seconds_to_duration` | Seconds to "Xd Xh Xm Xs" |
| `unix_ms_to_iso` | Unix ms to ISO 8601 |
| `unix_to_iso` | Unix seconds to ISO 8601 |

### Units
| Name | Description |
|------|-------------|
| `bytes_to_gb` / `bytes_to_mb` | Byte conversion |
| `celsius_to_fahrenheit` | Temperature conversion |
| `div_10` / `div_100` / `div_1000` | Division |
| `mul_8` | Bytes to bits |
| `to_gbps` / `to_mbps` | Bits/sec conversion |

### User-Defined Transforms (Starlark)

Custom transforms via `collector_transforms` tool. Expression is wrapped in `def transform(value):` automatically — write only the body.

```
expression: "return str(value).upper()"
expression: "if value > 1000:\n  return str(value / 1000) + \"K\"\nreturn str(value)"
expression: "return lowercase(strip_null_bytes(value))"  # can call built-ins
```

## Output Backend Config Schemas

### NATS
`url` (required), `seed-path` (NKey auth), `client-name`
Topic: `collector.data.{model}.{deviceId}`

### Prometheus
`metrics-path` (default `/metrics/collector`), `port` (default 9090)
Metric: `collector_{model}_{field}` with labels `device`, `device_id`, `key`

### InfluxDB v2
`url`, `token`, `org`, `bucket` (all required), `batch-size`, `flush-interval`
Measurement: model name. Tags: `device`, `device-id`, `key`

### Kafka
`brokers` (required), `topic`, `sasl-mechanism`, `sasl-username`, `sasl-password`, `tls-enabled`
Key: `{model}-{deviceId}`

### Webhook
`url` (required), `method`, `headers`, `auth-header`, `batch-mode`, `timeout-ms`

### File
`output-dir` (required), `format` (jsonl/csv), `rotate-after-mb`

### TimescaleDB
`host`, `database`, `username`, `password` (required), `port` (default 5432), `ssl-mode` (default require), `table` (hypertable, default `collector_metrics`), `batch-size`, `flush-interval`
Analytics (auto-provisioned on connect, needs the `timescaledb` extension — falls back to a plain table without it): `chunk-interval`, `compress-after`, `retention-period`, `continuous-aggregate`, `aggregate-retention`. Interval fields take a `<N> <unit>` literal (e.g. `7 days`); blank = recommended default, `off` = disable.
Schema: one narrow row per numeric field — `(time, device, device_id, model, key, metric, value)`; an hourly `<table>_hourly` continuous aggregate is created by default.

## Pipeline Validation Stages

7 stages run by `collector_validate_pipeline`: device-check → protocol-check → reachability-check → connection-check → collection-check → mapping-check → output-check

## Testing Timeouts

- CLI: 35s context / 30s collect
- gNMI/SNMP/NETCONF: 12s context / 8s collect
- Quick path test: 12s context / 8s collect, max 50 raw updates
- Model test: max 20 parsed entries
