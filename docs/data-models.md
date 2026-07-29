# Data model JSON reference

A **data model** defines *what* normalized data the collector produces, independent of how it
is collected. Each model has a flat list of typed **fields** and one or more protocol **mappings**
that say how to populate those fields from a given protocol on a given NetOS.

The JSON below is exactly the format produced by **Export** and accepted by **Import** — it
round-trips losslessly. All keys are **kebab-case**.

## Top level

```json
{
  "name": "oc-interfaces",
  "description": "OpenConfig interface state",
  "version": "1.0.0",
  "fields":   [ /* FieldExport */ ],
  "mappings": [ /* MappingExport */ ]
}
```

| Key | Type | Notes |
|-----|------|-------|
| `name` | string | Unique model identifier (kebab-case). Also the NATS topic segment: `collector.data.{name}.{deviceId}`. |
| `description` | string | Human description. |
| `version` | string | Free-form model version (e.g. `1.0.0`). |
| `fields` | array | Field definitions (the output schema). |
| `mappings` | array | One entry per `(protocol, netos)` pair. |

## Fields (`FieldExport`)

```json
{
  "name": "in-octets",
  "field-type": "uint64",
  "format": "",
  "required": false,
  "description": "Ingress byte counter",
  "position": 4
}
```

| Key | Notes |
|-----|-------|
| `name` | Output field name (kebab-case). |
| `field-type` | One of `string`, `int32`, `int64`, `uint32`, `uint64`, `float32`, `float64`, `boolean`. (The UI/older exports also accept the alias `integer`.) |
| `format` | Optional semantic format (validated against type). See list below. Omit if empty. |
| `required` | If `true`, a record missing this field is rejected. The **key** field is normally required. |
| `description` | Human description. |
| `position` | Display/order index. |
| `enum-values`, `prometheus-role`, `prometheus-unit` | Optional; only emitted when set (used by the Prometheus output backend). |

**Valid `format` values:** `ipv4`, `ipv6`, `ip-address`, `ip-prefix`, `mac-address`, `as-number`,
`bgp-community`, `oid`, `duration`, `vlan-id`, `hostname`, `route-distinguisher`, `date-and-time`,
`port-number`, `phys-address`, `domain-name`, `uri`. Not all formats are valid for every type
(e.g. `as-number` requires a uint type; `ip-address`/`mac-address` require `string`).

## Mappings (`MappingExport`)

A mapping binds one protocol + NetOS to the model. Only the keys relevant to the chosen
`protocol` are populated; the rest are omitted.

```json
{
  "protocol": "gnmi",
  "netos": "ios-xr",
  "version-constraints": [],
  "key-field": "name",
  "gnmi-paths": ["openconfig-interfaces:interfaces/interface/state"],
  "gnmi-path-filter": "/state",
  "snmp-walk-oids": [],
  "snmp-scalar-oids": [],
  "netconf-filter-paths": [],
  "cli-commands": [],
  "cli-template": "",
  "field-mappings":   { "source-key": "model-field" },
  "field-transforms": { "model-field": ["transform_name", ...] },
  "value-transforms": { "model-field": { "RAW": "normalized" } },
  "ignore-values":    { "model-field": ["value-to-drop"] }
}
```

| Key | Applies to | Notes |
|-----|-----------|-------|
| `protocol` | all | `gnmi`, `snmp`, `cli`, or `netconf`. |
| `netos` | all | e.g. `ios-xr`, `eos`, `srlinux`, `junos`. A model can have one mapping per NetOS per protocol (see `interface-state` for a multivendor example). |
| `version-constraints` | all | Optional semver-style constraints to scope the mapping to certain software versions. |
| `key-field` | all | **Uses the SOURCE field name** (the parsed key before mapping), not the model field name. Setting it to the model field name yields empty results. |
| `gnmi-paths` | gnmi | List of gNMI subscription paths. |
| `gnmi-path-filter` | gnmi | Suffix filter (e.g. `/state`) applied to returned leaves. |
| `snmp-walk-oids` | snmp | Numeric table OIDs to walk; rows are keyed by table index and columns merged. |
| `snmp-scalar-oids` | snmp | Numeric scalar OIDs. |
| `netconf-filter-paths` | netconf | XML subtree filters, e.g. `<interfaces xmlns='http://openconfig.net/yang/interfaces'/>`. |
| `cli-commands` | cli | Show commands to run. |
| `cli-template` | cli | **GoTTP** template parsing the command output (mandatory for CLI). |
| `field-mappings` | all | `{ "<source key>": "<model field>" }`. Source keys are protocol-specific (resolved MIB names for SNMP, leaf names for gNMI, TTP variable names for CLI). Dotted keys (e.g. `counters.in-octets`) reach into nested gNMI/NETCONF subtrees. |
| `field-transforms` | all | `{ "<model field>": ["t1", "t2"] }` — ordered pipeline of built-in or user-defined transform names applied after mapping. |
| `value-transforms` | all | `{ "<model field>": { "RAW": "out" } }` — static value replacement (enum normalization). |
| `ignore-values` | all | `{ "<model field>": ["drop1"] }` — records whose field equals a listed value are dropped (handy to skip header rows or `Null0`). |

> **Source-key tips**
> - **gNMI / NETCONF (OpenConfig):** the full `/state` subtree is returned, so counters live under
>   `counters.*` (e.g. `counters.in-octets`). srlinux/eos flatten differently — compare the three
>   mappings in `interface-state.json`.
> - **IS-IS / nested keys:** the adjacency key is `state.system-id` (state-prefixed) — see `oc-isis-adjacency.json`.
> - **SNMP:** with MIBs loaded, source keys are the resolved names (`ifName`, `ifHCInOctets`, …), not OIDs.
> - **CLI:** source keys are the `{{ variable }}` names from the GoTTP template.

See [transforms.md](transforms.md) for the transform catalog and [importing.md](importing.md) for loading these files.
