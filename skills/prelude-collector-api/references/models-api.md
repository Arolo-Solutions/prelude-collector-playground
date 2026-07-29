# Models, Fields & Mappings API Reference

**A model is two tiers.** A *definition* (family) owns one or more *versions*; fields and
mappings belong to a version.

- `GET /api/v1/models` lists **families**, each carrying a `version-id` — the version to
  address (latest active by SemVer, else newest overall).
- Everything under `/api/v1/models/{id}/…` takes a **version id**.
- `POST /api/v1/models` returns the **version** row: its `id` is the version id, and
  `data-model-definition-id` is the family id. Use `id` for fields/mappings, and
  `data-model-definition-id` for subscriptions.

**The mapping key is derived, not declared.** There is no `key-field`. The record key is the
source mapped onto the field flagged `is-key` — see [Protocol Mappings CRUD](#protocol-mappings-crud).

## Table of Contents
- [Data Models CRUD](#data-models-crud) — list, get, create, update, delete, export, import
- [Model Fields CRUD](#model-fields-crud) — add, update, delete, reorder, valid types/formats
- [Protocol Mappings CRUD](#protocol-mappings-crud) — mapping fields, gNMI/SNMP/NETCONF/CLI examples
- [Built-in Transform Functions](#built-in-transform-functions) — BGP, interface, IP/MAC, routing, SNMP, strings, time, units
- [User-Defined Transforms (Starlark) API](#user-defined-transforms-starlark-api) — create, list, update, delete

## Data Models CRUD

### List Models

```bash
curl -sk "$BASE_URL/api/v1/models?page_number=1&item_numbers=25" \
  -H "Authorization: Bearer $TOKEN"
```

Response includes `items` array and pagination metadata. Each item is a **family**:

```json
{
  "id": 9,
  "name": "interface-counters",
  "description": "…",
  "version-id": 4,
  "versions": [...]
}
```

`id` is the family; **`version-id` is what the item endpoints take**. They differ whenever a
family has more than one version.

### Get Model (by version id)

```bash
curl -sk "$BASE_URL/api/v1/models/$VERSION_ID" \
  -H "Authorization: Bearer $TOKEN"
```

Returns the version with nested `fields` and `mappings` arrays:
```json
{
  "id": 4,
  "data-model-definition-id": 9,
  "version": "1.0.0",
  "is-active": true,
  "fields": [...],
  "mappings": [...]
}
```

### Create Model

```bash
curl -sk -X POST "$BASE_URL/api/v1/models" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "interfaces",
    "description": "Network interface statistics",
    "version": "1.0.0"
  }'
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| name | string | yes | unique, max 100 chars |
| description | string | no | max 500 chars |
| version | string | no | **SemVer**, default `1.0.0` — `1.0` is rejected where a bump is computed |
| is-active | boolean | no | default true |

Response 201 is the created **version**:

```json
{"id": 111, "data-model-definition-id": 112, "version": "1.0.0", "is-active": true}
```

`id` (111) → fields, mappings, test, export. `data-model-definition-id` (112) → subscriptions.

### Update Model

```bash
curl -sk -X PUT "$BASE_URL/api/v1/models/$VERSION_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"description": "Updated description", "version": "1.1.0"}'
```

### Delete Model

```bash
curl -sk -X DELETE "$BASE_URL/api/v1/models/$VERSION_ID" \
  -H "Authorization: Bearer $TOKEN"
```

Response: 204. Fails if model has active subscriptions.

### Export Model

```bash
curl -sk "$BASE_URL/api/v1/models/$VERSION_ID/export" \
  -H "Authorization: Bearer $TOKEN"
```

Returns the family as `{name, description, versions: [{version, is-active, fields, mappings}]}`.
Fields carry `is-key`; mappings carry **no** `key-field`.

### New Version

```bash
curl -sk -X POST "$BASE_URL/api/v1/models/$VERSION_ID/new-version" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"version": "1.1.0"}'
```

Forks a new version from an existing one. Omit `version` to auto-bump the minor
(`1.0.0` → `1.1.0`), created as an inactive draft.

### Import Model

```bash
curl -sk -X POST "$BASE_URL/api/v1/models/$VERSION_ID/import" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @exported-model.json
```

Note the path takes an id — import lands in a family, it is not a bare `/models/import`.

Import rules that matter:

- Field `position` comes from **array order**.
- If several fields set `"is-key": true`, the **first wins**; the rest are cleared.
- If no field sets `is-key`, the first field is auto-promoted.
- A pre-1.1.3 export whose mapping carries `"key-field": "ifName"` still imports: the source
  is resolved through that mapping's `field-mappings` and the target field is flagged.
  Read on import only — never written back.

---

## Model Fields CRUD

Every version has **exactly one** key field — the one flagged `is-key`. It is the model's
protocol-independent identity, and the mapping's key source is whatever source is mapped onto
it.

### Add Field

```bash
curl -sk -X POST "$BASE_URL/api/v1/models/$VERSION_ID/fields" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "interface-name",
    "field-type": "string",
    "format": "",
    "required": true,
    "is-key": true,
    "description": "Interface identifier",
    "position": 0
  }'
```

Response: 201

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| name | string | yes | max 100 chars |
| field-type | string | yes | see valid types below |
| format | string | no | type-dependent, max 30 chars |
| required | boolean | no | default false |
| `is-key` | boolean | no | identity key. At most one per version — flagging a field clears the previous one |
| description | string | no | max 500 chars |
| position | int | no | display order, default 0 |
| prometheus-role / prometheus-unit | string | no | output hints; written by the full PUT, not by the hints endpoint |

**The first field added to a version is auto-promoted to key** when none is flagged. So a model
built by adding fields in order gets its key on field #1 whether you asked for it or not — check
it, and move it if that is wrong.

### Update Field

```bash
curl -sk -X PUT "$BASE_URL/api/v1/models/$VERSION_ID/fields/$FIELD_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "interface-name", "field-type": "string", "is-key": true}'
```

The body is merged onto the stored row, so omitting `is-key` **keeps** it.

- To move the key: PUT the *new* field with `"is-key": true`. The old one is cleared for you.
- Clearing it on the current key field is refused:

```json
{"code":"bad_request",
 "message":"a model needs one key field: flag another field as the key instead of clearing this one: bad request"}
```

→ **400**. There is no way to leave a version keyless.

### Delete Field

```bash
curl -sk -X DELETE "$BASE_URL/api/v1/models/$VERSION_ID/fields/$FIELD_ID" \
  -H "Authorization: Bearer $TOKEN"
```

Deleting the key field re-promotes the first remaining field (by position, then id).

### Reorder Fields

```bash
curl -sk -X POST "$BASE_URL/api/v1/models/$VERSION_ID/fields/reorder" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '[3, 1, 2]'
```

Body is a JSON array of field IDs in the new order. It must be a **full permutation** — every
field of the version exactly once. Otherwise **400**:

```json
{"code":"bad_request",
 "message":"reorder must list every field of the model exactly once: got 1 field(s), the model has 2: bad request"}
```

Also 400 on a duplicated id or an id from another model. Reordering never moves the key flag —
it stays on the same field wherever it lands.

### Valid Field Types

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

---

## Protocol Mappings CRUD

### The key is derived from `field-mappings`

There is **no `key-field`**. The record key is the source whose target is the field flagged
`is-key`. In this mapping, `interface-name` is the key field, so `name` is the key source:

```json
{"field-mappings": "{\"name\": \"interface-name\", \"mtu\": \"mtu\"}"}
```

Rejections, all **422** with the detail under `field-errors["field-mappings"]`:

| Payload | Message |
|---|---|
| nothing targets the key field | `Map a source onto "interface-name", the model's key field: it identifies each record` |
| two sources target it | `Several sources map onto "interface-name", the model's key field: keep exactly one so the record identity is unambiguous` |
| the model has no `is-key` field | `The model has no key field: flag one field as the identity key first` |

Sending a literal `"key-field"` key is **400**, not a silent ignore — the decoder rejects
unknown keys: `body contains unknown key "key-field"`.

Same rules on POST and PUT, and identical to the web edit form.

### Mapping Fields Reference

| JSON Field | Type | Required | Notes |
|------------|------|----------|-------|
| `protocol` | string | yes | `gnmi`, `snmp`, `cli`, `netconf` |
| `netos` | string | yes | `ios-xr`, `ios-xe`, `junos`, `eos`, etc. |
| `version-constraints` | string | no | JSON array: `[">=7.0", "<8.0"]` |
| `gnmi-paths` | string | gNMI | JSON array of gNMI paths |
| `gnmi-path-filter` | string | no | regex filter for gNMI path |
| `snmp-walk-oids` | string | SNMP | JSON array of walk OIDs |
| `snmp-scalar-oids` | string | SNMP | JSON array of scalar OIDs |
| `netconf-filter-paths` | string | NETCONF | JSON array of XML subtree filters |
| `cli-commands` | string | CLI | JSON array of CLI commands |
| `cli-template` | string | CLI | TTP template for parsing output (mandatory for CLI) |
| `cli-discovery-params` | string | no | JSON array of CLI discovery params |
| `snmp-lookups` | string | no | JSON array of SNMP lookup definitions |
| `field-mappings` | string | yes | JSON object: `{"source": "target-field"}` — must include exactly one entry whose target is the key field |
| `field-transforms` | string | no | JSON object: `{"field": ["transform1"]}` |
| `value-transforms` | string | no | JSON object: `{"field": {"src": "display"}}` |
| `ignore-values` | string | no | JSON object: `{"field": ["val1", "val2"]}` |

**Important:** All JSON array/object fields above are **JSON-encoded strings** in the request body. You must double-encode them.

### Unique constraint

Each mapping must be unique by `(protocol, netos, version-constraints)` within a model. Duplicate combinations return **422** (`field-errors.protocol`).

### Add gNMI Mapping

```bash
curl -sk -X POST "$BASE_URL/api/v1/models/$VERSION_ID/mappings" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "protocol": "gnmi",
    "netos": "ios-xr",
    "gnmi-paths": "[\"/interfaces/interface/state\"]",
    "field-mappings": "{\"name\": \"interface-name\", \"counters/in-octets\": \"in-octets\", \"counters/out-octets\": \"out-octets\", \"mtu\": \"mtu\"}"
  }'
```

gNMI-specific fields:
- `gnmi-paths` — required, JSON array of OpenConfig or native YANG paths
- `gnmi-path-filter` — optional regex to filter updates (e.g., `"Gig.*"`)

### Add SNMP Mapping

```bash
curl -sk -X POST "$BASE_URL/api/v1/models/$VERSION_ID/mappings" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "protocol": "snmp",
    "netos": "ios-xr",
    "snmp-walk-oids": "[\"1.3.6.1.2.1.2.2.1.2\", \"1.3.6.1.2.1.2.2.1.5\", \"1.3.6.1.2.1.2.2.1.10\"]",
    "snmp-scalar-oids": "[]",
    "field-mappings": "{\"1.3.6.1.2.1.2.2.1.2\": \"interface-name\", \"1.3.6.1.2.1.2.2.1.5\": \"mtu\", \"1.3.6.1.2.1.2.2.1.10\": \"in-octets\"}"
  }'
```

SNMP-specific fields:
- `snmp-walk-oids` — JSON array, tabular OIDs (SNMP WALK)
- `snmp-scalar-oids` — JSON array, single-instance OIDs (SNMP GET)
- For SNMP, `field-mappings` keys are OID strings

### Add NETCONF Mapping

```bash
curl -sk -X POST "$BASE_URL/api/v1/models/$VERSION_ID/mappings" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "protocol": "netconf",
    "netos": "ios-xr",
    "netconf-filter-paths": "[\"<interfaces xmlns=\\\"http://openconfig.net/yang/interfaces\\\"/>\"]",
    "field-mappings": "{\"name\": \"interface-name\", \"state/admin-status\": \"admin-status\", \"state/mtu\": \"mtu\"}"
  }'
```

NETCONF-specific fields:
- `netconf-filter-paths` — required, JSON array of XML subtree filter strings
- Filters must be valid XML elements with xmlns namespaces
- Must not be empty array (returns 400)

### Add CLI Mapping

```bash
curl -sk -X POST "$BASE_URL/api/v1/models/$VERSION_ID/mappings" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "protocol": "cli",
    "netos": "ios-xr",
    "cli-commands": "[\"show interfaces\"]",
    "cli-template": "interface {{ interface_name }}\n  MTU {{ mtu }}",
    "field-mappings": "{\"interface_name\": \"interface-name\", \"mtu\": \"mtu\"}"
  }'
```

CLI-specific fields:
- `cli-commands` — required, JSON array of CLI commands to execute
- `cli-template` — required, TTP (Template Text Parser) template for parsing CLI output
- For CLI, `field-mappings` keys are TTP variable names from the template

### Update Mapping

```bash
curl -sk -X PUT "$BASE_URL/api/v1/models/$VERSION_ID/mappings/$MAPPING_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "field-mappings": "{\"name\": \"updated-field\"}"
  }'
```

### Delete Mapping

```bash
curl -sk -X DELETE "$BASE_URL/api/v1/models/$VERSION_ID/mappings/$MAPPING_ID" \
  -H "Authorization: Bearer $TOKEN"
```

Response: 204

### Transform Fields in Mappings

Mappings support three transform mechanisms applied during collection. All are JSON-encoded strings in the request body.

**Field Transforms** (`field-transforms`) — pipeline of named transform functions applied in order to raw values. Each field can have multiple transforms chained:
```json
"field-transforms": "{\"admin-status\": [\"if_admin_status\"], \"speed\": [\"speed_to_human\"], \"mac\": [\"octetstring_to_mac\", \"mac_to_eui48\"]}"
```

**Value Transforms** (`value-transforms`) — static source value to display value replacement map:
```json
"value-transforms": "{\"oper-status\": {\"1\": \"up\", \"2\": \"down\", \"3\": \"testing\"}}"
```

**Ignore Values** (`ignore-values`) — entries with these values for given fields are filtered out:
```json
"ignore-values": "{\"interface-name\": [\"Null0\", \"Loopback99\", \"nVFabric\"]}"
```

---

## Built-in Transform Functions

These are the built-in transforms available for use in `field-transforms`. Transforms are applied in pipeline order — the output of one feeds into the next.

### BGP

| Name | Description |
|------|-------------|
| `as_plain` | ASN asdot+ notation to plain decimal integer |
| `as_dot` | ASN integer to asdot+ notation (e.g. 65536 to "1.0") |
| `bgp_community` | uint32 to BGP standard community "HI:LO" |
| `bgp_ext_community` | uint64 to BGP extended community "TYPE:HI:LO" |
| `bgp_state` | BGP FSM integer 1-6 to state name (Idle ... Established) |

### Interface

| Name | Description |
|------|-------------|
| `if_admin_status` | IF-MIB ifAdminStatus integer 1-3 to "up" / "down" / "testing" |
| `if_oper_status` | IF-MIB ifOperStatus integer 1-7 to state name (up, down, dormant ...) |
| `speed_to_human` | Bits/sec integer to human-readable speed (e.g. "1G", "100M") |

### IP / MAC

| Name | Description |
|------|-------------|
| `ip_with_prefix` | Packed 32-bit IPv4 integer to dotted-quad string |
| `ip_with_netmask` | Packed 32-bit subnet mask to prefix-length string ("/24") |
| `ipv6_compress` | IPv6 string to compressed form (e.g. "2001:db8::1") |
| `ipv6_expand` | IPv6 string to fully expanded 8-group form |
| `mac_to_eui48` | Any MAC format (:, -, Cisco .) to lowercase "aa:bb:cc:dd:ee:ff" |
| `netmask_to_prefix` | Dotted-quad netmask string to prefix-length integer |

### Routing

| Name | Description |
|------|-------------|
| `isis_adj_state` | ISIS-MIB isisISAdjState integer 1-3 to "down" / "initializing" / "up" |
| `ospf_neighbor_state` | OSPF-MIB ospfNbrState integer 1-8 to state name (Down ... Full) |

### SNMP

| Name | Description |
|------|-------------|
| `octetstring_to_hex` | SNMP OctetString bytes to colon-separated hex (e.g. "aa:bb:cc") |
| `octetstring_to_mac` | 6-byte SNMP OctetString to MAC address string |
| `oid_last_segment` | OID string to last segment after the final dot |
| `strip_null_bytes` | Remove \x00 null bytes from a string value |
| `timeticks_to_seconds` | SNMP TimeTicks (1/100 s) to seconds as float |
| `timeticks_to_uptime` | SNMP TimeTicks to "Xd Xh Xm Xs" human-readable uptime |

### Strings

| Name | Description |
|------|-------------|
| `base64_decode` | Base64-encoded string to decoded string |
| `hex_to_int` | Hex string ("0x1f" or "1f") to integer |
| `int_to_hex` | Integer to hex string with "0x" prefix |
| `lowercase` | String to lowercase |
| `trim_whitespace` | Trim leading/trailing whitespace |
| `truncate_256` | Truncate string to 256 characters |
| `uppercase` | String to uppercase |

### Time

| Name | Description |
|------|-------------|
| `seconds_to_duration` | Seconds integer to "Xd Xh Xm Xs" duration string |
| `unix_ms_to_iso` | Unix timestamp in milliseconds to ISO 8601 UTC string |
| `unix_to_iso` | Unix timestamp in seconds to ISO 8601 UTC string |

### Units

| Name | Description |
|------|-------------|
| `bytes_to_gb` | Bytes to gigabytes (/ 1,073,741,824) |
| `bytes_to_mb` | Bytes to megabytes (/ 1,048,576) |
| `celsius_to_fahrenheit` | Celsius to Fahrenheit (x 9/5 + 32) |
| `div_10` | Numeric value / 10 |
| `div_100` | Numeric value / 100 |
| `div_1000` | Numeric value / 1000 (milli-unit to unit) |
| `mul_8` | Numeric value x 8 (bytes to bits) |
| `to_gbps` | Bits/sec to Gbps (/ 1,000,000,000) |
| `to_mbps` | Bits/sec to Mbps (/ 1,000,000) |

### Transform Pipeline Example

```json
{
  "field-transforms": "{\"speed\": [\"mul_8\", \"to_gbps\"], \"uptime\": [\"timeticks_to_uptime\"], \"mac-address\": [\"octetstring_to_mac\", \"mac_to_eui48\"], \"admin-status\": [\"if_admin_status\"]}"
}
```

This applies: speed raw bytes x8 then to Gbps, SNMP timeticks to human uptime, raw OctetString to normalized MAC, and integer admin-status to "up"/"down".

---

## User-Defined Transforms (Starlark) API

Beyond the built-in transforms above, users can create custom transforms using Starlark expressions via the API. Custom transforms are registered at runtime and can be used in `field-transforms` just like built-ins.

### UserTransform Model

| JSON Field | Type | Required | Notes |
|------------|------|----------|-------|
| `name` | string | yes | unique, max 100 chars, lowercase snake_case (`^[a-z][a-z0-9_]*$`) |
| `description` | string | no | max 500 chars |
| `expression` | string | yes | Starlark expression body (see below) |

Names must not collide with built-in transform names.

### Create User Transform

```bash
curl -sk -X POST "$BASE_URL/api/v1/transforms" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "prefix_ge",
    "description": "Prepend GigabitEthernet prefix",
    "expression": "return \"GigabitEthernet\" + str(value)"
  }'
```

Response: 201

The `expression` is wrapped in `def transform(value):` automatically. Write only the function body. The `value` parameter receives the raw field value. Available features: `set()`, while loops, recursion, plus all built-in transforms as callable functions.

### Starlark Expression Examples

Simple return:
```json
{"expression": "return str(value).upper()"}
```

Multi-line with logic:
```json
{"expression": "if value > 1000:\n  return str(value / 1000) + \"K\"\nreturn str(value)"}
```

Using built-in transforms inside Starlark:
```json
{"expression": "return lowercase(strip_null_bytes(value))"}
```

Extra builtins available in Starlark: `round(number [, ndigits])`.

### List User Transforms

```bash
curl -sk "$BASE_URL/api/v1/transforms?page_number=1&item_numbers=25" \
  -H "Authorization: Bearer $TOKEN"
```

### Get User Transform

```bash
curl -sk "$BASE_URL/api/v1/transforms/$TRANSFORM_ID" \
  -H "Authorization: Bearer $TOKEN"
```

### Update User Transform

```bash
curl -sk -X PUT "$BASE_URL/api/v1/transforms/$TRANSFORM_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "description": "Updated description",
    "expression": "return str(value).strip()"
  }'
```

### Delete User Transform

```bash
curl -sk -X DELETE "$BASE_URL/api/v1/transforms/$TRANSFORM_ID" \
  -H "Authorization: Bearer $TOKEN"
```

Response: 204. Cannot delete built-in transforms.
