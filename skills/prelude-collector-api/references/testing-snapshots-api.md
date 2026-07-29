# Testing & Snapshots API Reference

## Live Collection Test

### POST /api/v1/models/{id}/test

Runs a live collection test against a real device using a specific mapping. Connects to the device, collects data, and returns both the raw device output and the parsed/mapped results.

```bash
curl -sk -X POST "$BASE_URL/api/v1/models/$MODEL_ID/test" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "device-id": 42,
    "mapping-id": 10
  }'
```

**Request Body:**

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `device-id` | uint | yes | device must exist and have matching protocol configured |
| `mapping-id` | uint | yes | mapping must belong to the model |

**Response (200):**
```json
{
  "results": [
    {
      "device": "core-router-1",
      "device-id": 42,
      "model-name": "interfaces",
      "path": "/interfaces/interface/state",
      "key": "GigabitEthernet0/0/0",
      "timestamp": "2026-03-16T10:30:00Z",
      "data": {
        "interface-name": "GigabitEthernet0/0/0",
        "admin-status": "up",
        "mtu": 1500
      }
    }
  ],
  "raw-updates": [
    {
      "name": "GigabitEthernet0/0/0",
      "state": {
        "admin-status": "UP",
        "oper-status": "UP",
        "mtu": 1500,
        "counters": { "in-octets": 123456789 }
      }
    }
  ],
  "device": "core-router-1",
  "protocol": "netconf",
  "raw-data-received": true
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `results` | array | Parsed data after field-mappings, transforms, and type coercion |
| `raw-updates` | array | Raw `DataUpdate.Data` from the device before any parsing/mapping |
| `device` | string | Device hostname |
| `protocol` | string | Protocol used for collection |
| `raw-data-received` | bool | Whether any data arrived from the device |
| `error` | string | Error message if collection failed (omitted when empty) |

**Raw updates by protocol:**
- **gNMI**: nested map from gNMI notification (paths as nested keys, leaf values)
- **SNMP**: map of OID to value from SNMP walk/get responses
- **NETCONF**: parsed XML as nested map from NETCONF `<rpc-reply>`
- **CLI**: map of command string to raw text output (e.g. `{"show interfaces": "GigabitEthernet0/0/0 is up..."}`)

**Timeout Behavior:**
- CLI protocol: 35s context timeout, 30s collect timeout (SSH handshake is slow)
- Other protocols (gNMI, SNMP, NETCONF): 12s context timeout, 8s collect timeout
- Collects up to **20 parsed entries** or timeout, whichever comes first

**Error Handling:**
- Returns HTTP 200 even when collection fails — check the `error` field
- `raw-data-received: false` + non-empty `error` = connection or protocol failure
- `raw-data-received: true` + empty `results` = data received but parsing/mapping failed (check `raw-updates` to debug)
- Common errors: "context deadline exceeded" (timeout), "connection refused" (device unreachable)

**Prerequisites:**
- Device must exist with the mapping's protocol configured (e.g., NETCONF mapping needs a NETCONF protocol entry on the device)
- Protocol credentials (username/password) must be correct
- Device must be reachable on the protocol port

---

## Cross-Vendor Comparison Test

### POST /api/v1/models/{id}/test/compare

Run live collection tests across multiple mapping/device pairs and return results side-by-side. Used to validate cross-vendor data consistency — ensuring field names, value formats, and types are normalized across vendors.

```bash
curl -sk -X POST "$BASE_URL/api/v1/models/$MODEL_ID/test/compare" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "tests": [
      {"mapping-id": 1, "device-id": 5},
      {"mapping-id": 2, "device-id": 8}
    ]
  }'
```

**Request Body:**

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `tests` | array | yes | At least 2 entries. Each: `{"mapping-id": uint, "device-id": uint}` |

**Response (200):** each result carries `device`, `mapping-id`, `protocol`, `netos`,
`key-field`, `records`, `error`. `key-field` is the **derived key source** — the source mapped
onto the model's `is-key` field, not a declared setting.

```json
{
  "results": [
    {
      "device": "xr-core-1",
      "netos": "ios-xr",
      "mapping-id": 1,
      "protocol": "gnmi",
      "key-field": "name",
      "records": [
        {"interface-name": "GigabitEthernet0/0/0", "admin-status": "up", "mtu": 1500}
      ],
      "error": ""
    },
    {
      "device": "srlinux-leaf-1",
      "netos": "srlinux",
      "mapping-id": 2,
      "protocol": "gnmi",
      "key-field": "name",
      "records": [
        {"interface-name": "ethernet-1/1", "admin-status": "up", "mtu": 1500}
      ],
      "error": ""
    }
  ],
  "fields": ["interface-name", "admin-status", "mtu"]
}
```

**Use case:** After creating mappings for multiple vendors/protocols on the same model, compare results to detect normalization gaps (case mismatches, vendor-specific enums, missing fields). Fix with transforms, then re-compare.

---

## Quick Path Test (gnmic-like)

### POST /api/v1/protocols/test-path

Run a one-shot test against a device with arbitrary paths — no model or mapping required. Like running `gnmic get` but through the Collector.

```bash
# gNMI path test
curl -sk -X POST "$BASE_URL/api/v1/protocols/test-path" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "device-id": 1,
    "protocol": "gnmi",
    "paths": ["openconfig-interfaces:interfaces/interface/state"]
  }'

# SNMP walk test
curl -sk -X POST "$BASE_URL/api/v1/protocols/test-path" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "device-id": 1,
    "protocol": "snmp",
    "paths": ["1.3.6.1.2.1.2.2.1"]
  }'

# NETCONF filter test
curl -sk -X POST "$BASE_URL/api/v1/protocols/test-path" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "device-id": 1,
    "protocol": "netconf",
    "paths": ["<interfaces xmlns=\"http://openconfig.net/yang/interfaces\"/>"]
  }'
```

**Request Body:**

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `device-id` | uint | yes | device must have matching protocol configured |
| `protocol` | string | yes | `gnmi`, `snmp`, or `netconf` |
| `paths` | string[] | yes | YANG paths, OIDs, or NETCONF XML filters |

**Response (200):**
```json
{
  "device": "dev-core-1",
  "protocol": "gnmi",
  "paths": ["openconfig-interfaces:interfaces/interface/state"],
  "duration": "8.12s",
  "raw-updates": [ ... ],
  "raw-count": 15,
  "error": ""
}
```

**Timeout**: 12s context, 8s collection, max 50 raw updates.

---

## Quick CLI Test

### POST /api/v1/protocols/test-cli

Run CLI show commands on a device and get raw output — no model or mapping required. The CLI equivalent of `test-path`.

```bash
curl -sk -X POST "$BASE_URL/api/v1/protocols/test-cli" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "device-id": 1,
    "commands": ["show ip interface brief", "show ip route summary"]
  }'
```

**Request Body:**

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `device-id` | uint | yes | device must have an enabled CLI protocol configured |
| `commands` | string[] | yes | show commands to execute (max 20) |

**Response (200):**
```json
{
  "device": "core-1",
  "duration": "1.23s",
  "command-outputs": [
    {
      "command": "show ip interface brief",
      "output": "Interface              IP-Address      Status      Protocol\nGi0/0/0                192.0.2.1      up          up\n",
      "has-data": true
    },
    {
      "command": "show ip route summary",
      "output": "Route Source    Networks    ...\nconnected       4           ...\n",
      "has-data": true
    }
  ],
  "command-count": 2,
  "has-warnings": false
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `device` | string | Device hostname |
| `duration` | string | Total execution time |
| `command-outputs` | array | Per-command results |
| `command-outputs[].command` | string | The command that was executed |
| `command-outputs[].output` | string | Raw CLI output text |
| `command-outputs[].has-data` | bool | Whether meaningful output was returned |
| `command-outputs[].device-error` | string | Device error message if detected (omitted when empty) |
| `command-count` | int | Number of commands executed |
| `has-warnings` | bool | True if any command returned no data or a device error |
| `error` | string | Error message if SSH connection or execution failed (omitted when empty) |

**Blocked Commands:**

Dangerous commands are rejected with HTTP 400 before any SSH connection is made. Blocked prefixes include: `configure`, `config`, `delete`, `set`, `no`, `reload`, `reboot`, `shutdown`, `write mem`, `erase`, and others.

**Timeout**: Uses CLI config timeouts from `config.json` — `cli.timeout` for SSH connection, `cli.command-timeout` per command.

---

## Snapshots

Snapshots return the latest cached collection data for a device. Data comes from active subscriptions — if no subscription is running for a model, the snapshot will be empty.

Routes live under `/api/v1/subscription/snapshots/…` (not a bare `/api/v1/snapshots/…`). A third
form addresses the model by its immutable family id instead of its name:
`GET /api/v1/subscription/snapshots/{deviceId}/definition/{definitionId}` — 404 when the
definition or a subscription for it is unknown, 204 when it has produced no data yet.

Captured history is separate: `GET /api/v1/capture/{deviceId}/definition/{definitionId}` and
`GET /api/v1/capture/{deviceId}/{modelName}/{versionId}`.

### GET /api/v1/subscription/snapshots/{deviceId}

All model snapshots for a device:

```bash
curl -sk "$BASE_URL/api/v1/subscription/snapshots/$DEVICE_ID" \
  -H "Authorization: Bearer $TOKEN"
```

**Response (200):**
```json
{
  "device-id": 42,
  "device": "core-router-1",
  "models": [
    {
      "model-name": "interfaces",
      "timestamp": "2026-03-16T10:30:00Z",
      "entries": [
        {
          "timestamp": "2026-03-16T10:30:00Z",
          "data": {
            "interface-name": "GigabitEthernet0/0/0",
            "admin-status": "up",
            "mtu": 1500
          }
        }
      ]
    }
  ]
}
```

### GET /api/v1/subscription/snapshots/{deviceId}/{modelName}

Single model snapshot:

```bash
curl -sk "$BASE_URL/api/v1/subscription/snapshots/$DEVICE_ID/interfaces" \
  -H "Authorization: Bearer $TOKEN"
```

**Query Parameters:**
- `refresh=true` — force a fresh poll before returning (useful for polling protocols: SNMP, CLI, NETCONF)

```bash
curl -sk "$BASE_URL/api/v1/subscription/snapshots/$DEVICE_ID/interfaces?refresh=true" \
  -H "Authorization: Bearer $TOKEN"
```

---

## Supporting Endpoints

### Devices

```bash
# List devices
curl -sk "$BASE_URL/api/v1/devices" -H "Authorization: Bearer $TOKEN"

# Create device
curl -sk -X POST "$BASE_URL/api/v1/devices" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "hostname": "core-router-1",
    "management-ip": "192.0.2.1",
    "net-os": "ios-xr",
    "active": true
  }'
```

### Protocols

```bash
# Create protocol for device
curl -sk -X POST "$BASE_URL/api/v1/protocols" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "device-id": 42,
    "type": "gnmi",
    "port": 57400,
    "username": "admin",
    "password": "secret",
    "tls": false,
    "timeout": 30
  }'

# Enable protocol
curl -sk -X POST "$BASE_URL/api/v1/protocols/$PROTOCOL_ID/enable" \
  -H "Authorization: Bearer $TOKEN"
```

Valid protocol types: `gnmi`, `snmp`, `cli`, `netconf`, `icmp`

### Subscriptions

```bash
# Create subscription (starts collection)
curl -sk -X POST "$BASE_URL/api/v1/subscriptions" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "device-id": 42,
    "data-model-definition-id": $FAMILY_ID,
    "protocol": "gnmi",
    "interval": 30,
    "enabled": true
  }'
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `device-id` | uint | yes | device must exist |
| `data-model-definition-id` | uint | yes | the model **family** id — not the version id, and `model-name` is no longer accepted |
| `data-model-version-id` | uint | no | pin a version; **omit to track the latest active version** |
| `protocol` | string | yes | `gnmi`, `snmp`, `cli`, `netconf` |
| `interval` | int | no | polling interval in seconds, must be > 0 |
| `enabled` | boolean | no | default false |
| `output-ids` | [uint] | no | output backends this subscription feeds |

Collection runs only when the subscription is enabled **and** the device is active **and** the
model version is active.

### Transforms

```bash
# List transforms
curl -sk "$BASE_URL/api/v1/transforms" -H "Authorization: Bearer $TOKEN"

# Create transform
curl -sk -X POST "$BASE_URL/api/v1/transforms" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ ... }'
```
