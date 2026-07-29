# YANG Tree Browser & SNMP MIB Browser API

Read-only REST APIs for browsing YANG schema trees and SNMP MIB trees.

## YANG Tree Browser

Permission group: `collector.api.yang`

### List Catalogs

```bash
curl -sk -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/yang/catalogs"
```

Response: array of catalogs (always includes "embedded/openconfig" + any device-collected catalogs).

```json
[
  {"netos":"embedded","software-version":"openconfig","module-count":5,"status":"collected"},
  {"id":1,"netos":"ios-xr","software-version":"24.2.2","module-count":2025,"status":"collected","collected-at":"2026-03-16T16:56:13Z","source-device-hostname":"dev-core-1"}
]
```

### List Modules

```bash
curl -sk -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/yang/catalogs/embedded/openconfig/modules"
# or for device catalog:
curl -sk -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/yang/catalogs/ios-xr/24.2.2/modules"
```

Response:
```json
{"netos":"embedded","software-version":"openconfig","modules":["openconfig-interfaces","openconfig-bgp",...]}
```

### Get Tree Root (2 levels pre-expanded)

```bash
curl -sk -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/api/v1/yang/catalogs/embedded/openconfig/modules/openconfig-interfaces/tree"
```

Response:
```json
{
  "module": "openconfig-interfaces",
  "namespace": "http://openconfig.net/yang/interfaces",
  "nodes": [
    {
      "name": "interfaces",
      "path": "/openconfig-interfaces/interfaces",
      "kind": "container",
      "config": true,
      "has-children": true,
      "children": [...]
    }
  ]
}
```

### Expand Node Children

```bash
curl -sk -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/api/v1/yang/catalogs/embedded/openconfig/modules/openconfig-interfaces/tree/children?path=/openconfig-interfaces/interfaces/interface/config"
```

### Search Tree

```bash
curl -sk -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/api/v1/yang/catalogs/embedded/openconfig/modules/openconfig-interfaces/tree/search?query=mtu"
```

Returns filtered tree with `is-match: true` on matching nodes (max 200 results).

### Get Leaves Under Path

```bash
curl -sk -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/api/v1/yang/catalogs/embedded/openconfig/modules/openconfig-interfaces/tree/leaves?path=/openconfig-interfaces/interfaces/interface/config"
```

Returns flat list of leaf/leaf-list nodes only.

### Get Module Deviations

```bash
curl -sk -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/api/v1/yang/catalogs/ios-xr/24.2.2/modules/openconfig-interfaces/deviations"
```

Response:
```json
{"module":"openconfig-interfaces","deviations":[{"path":"/interfaces/interface/config/mtu","type":"replace"}]}
```

### YangTreeNode Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Node name |
| `path` | string | Absolute YANG path |
| `kind` | string | container, list, leaf, leaf-list, choice, case |
| `type` | string | YANG type (leaf/leaf-list only) |
| `description` | string | Cleaned description (max 200 chars) |
| `key` | string | List key definition |
| `config` | bool | true=read-write, false=read-only |
| `has-children` | bool | Whether node has children |
| `children` | array | Child nodes (depth-dependent) |
| `is-match` | bool | true when matching search query |
| `augmented` | bool | true if augmented from another module |
| `augment-source` | string | Namespace of augmenting module |
| `deviated` | bool | true if affected by deviation |
| `deviation-type` | string | add, replace, delete, not-supported |

---

## SNMP MIB Browser

Permission group: `collector.api.snmp-browser`

### List MIB Modules

```bash
curl -sk -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/snmp/mibs/modules"
```

Response:
```json
{"modules":["AGENTX-MIB","BGP4-MIB","BRIDGE-MIB","IF-MIB",...]}
```

### Get Module Tree (2 levels)

```bash
curl -sk -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/snmp/mibs/modules/IF-MIB/tree"
# Optional: filter walk profile annotations by NetOS
curl -sk -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/snmp/mibs/modules/IF-MIB/tree?netos=ios-xr"
```

### Get Module Imports (Dependencies)

```bash
curl -sk -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/snmp/mibs/modules/IF-MIB/imports"
```

Response:
```json
{"module":"IF-MIB","imports":["SNMPv2-SMI","SNMPv2-TC","SNMPv2-CONF","SNMPv2-MIB","IANAifType-MIB"]}
```

### Get OID Detail

```bash
curl -sk -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/snmp/mibs/oids?oid=1.3.6.1.2.1.2.2.1.2"
```

Response:
```json
{
  "name": "ifDescr",
  "oid": "1.3.6.1.2.1.2.2.1.2",
  "module": "RFC1213-MIB",
  "syntax": "DisplayString (SIZE (0..255))",
  "max-access": "read-only",
  "status": "mandatory",
  "description": "...",
  "is-table": false,
  "is-row": false
}
```

### Get OID Children

```bash
curl -sk -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/snmp/mibs/oids/children?oid=1.3.6.1.2.1.2.2.1"
```

### Get Table Columns

```bash
curl -sk -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/snmp/mibs/oids/columns?oid=1.3.6.1.2.1.2.2"
```

### Search MIB Tree

```bash
# Basic search
curl -sk -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/snmp/mibs/search?query=ifDescr"
# Scoped to module
curl -sk -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/snmp/mibs/search?query=ifDescr&module=IF-MIB"
# Scoped to OID subtree
curl -sk -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/snmp/mibs/search?query=ifDescr&root-oid=1.3.6.1.2.1.2"
# Custom limit (default 200, max 1000)
curl -sk -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/snmp/mibs/search?query=if&limit=50"
```

### List Walk Profiles

```bash
curl -sk -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/snmp/mibs/profiles"
# Filter by NetOS
curl -sk -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/snmp/mibs/profiles?netos=ios-xr"
```

Response:
```json
{
  "profiles": [
    {"name":"Interfaces Table","oid":"1.3.6.1.2.1.2.2","mib_module":"IF-MIB","description":"...","netos":[],"builtin":true,"metrics":["ifInOctets"],"labels":["ifDescr"]}
  ]
}
```

### Walk Device (On-Demand)

```bash
curl -sk -X POST "$BASE_URL/api/v1/snmp/mibs/walk" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "device-id": 1,
    "oid": ".1.3.6.1.2.1.2.2",
    "mode": "walk",
    "max-results": 500
  }'
```

`mode`: "walk" (default) or "get". `max-results`: default 1000, hard max 10000.

Response:
```json
{
  "results": [
    {"oid":"1.3.6.1.2.1.2.2.1.1.1","name":"ifIndex","module":"RFC1213-MIB","index":"1","type":"INTEGER","value":"1"},
    {"oid":"1.3.6.1.2.1.2.2.1.2.1","name":"ifDescr","module":"RFC1213-MIB","index":"1","type":"STRING","value":"GigabitEthernet0/0/0/0"}
  ],
  "result-count": 150,
  "truncated": false,
  "duration": "1.234s"
}
```

### MibTreeNode Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Object name |
| `oid` | string | Dotted numeric OID |
| `sub-id` | string | Last component of OID |
| `module` | string | Defining MIB module |
| `kind` | string | table, row, column, scalar, branch |
| `syntax` | string | SMI syntax definition |
| `max-access` | string | read-only, read-write, etc. |
| `status` | string | current, deprecated, mandatory |
| `description` | string | Object description |
| `index-names` | array | Table index column names |
| `has-children` | bool | Whether node has children |
| `has-profile` | bool | Matched by a walk profile |
| `profile-name` | string | Name of matching walk profile |
| `is-match` | bool | true when matching search query |
| `children` | array | Child nodes (depth-dependent) |
