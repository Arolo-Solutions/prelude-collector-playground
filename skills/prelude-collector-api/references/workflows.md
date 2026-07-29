# End-to-End API Workflows

Complete curl-based workflows for common tasks. All examples assume `$BASE_URL` and `$TOKEN` are set.

---

## 1. gNMI Interface Model (IOS-XR)

Create a model to collect interface statistics via gNMI.

```bash
# Step 1: Create model
MODEL=$(curl -sk -X POST "$BASE_URL/api/v1/models" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "gnmi-interfaces",
    "description": "Interface stats via gNMI",
    "version": "1.0.0"
  }')
MODEL_ID=$(echo $MODEL | jq -r '.id')                       # version id -> fields/mappings/test
FAMILY_ID=$(echo $MODEL | jq -r '."data-model-definition-id"')  # family id -> subscriptions

# Step 2: Add fields
for field in \
  '{"name":"interface-name","field-type":"string","required":true,"is-key":true,"position":0}' \
  '{"name":"admin-status","field-type":"string","position":1}' \
  '{"name":"oper-status","field-type":"string","position":2}' \
  '{"name":"mtu","field-type":"uint32","position":3}' \
  '{"name":"in-octets","field-type":"uint64","position":4}' \
  '{"name":"out-octets","field-type":"uint64","position":5}'; do
  curl -sk -X POST "$BASE_URL/api/v1/models/$MODEL_ID/fields" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$field"
done

# Step 3: Add gNMI mapping
MAPPING=$(curl -sk -X POST "$BASE_URL/api/v1/models/$MODEL_ID/mappings" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "protocol": "gnmi",
    "netos": "ios-xr",
    "gnmi-paths": "[\"/interfaces/interface/state\"]",
    "field-mappings": "{\"name\": \"interface-name\", \"admin-status\": \"admin-status\", \"oper-status\": \"oper-status\", \"mtu\": \"mtu\", \"counters/in-octets\": \"in-octets\", \"counters/out-octets\": \"out-octets\"}"
  }')
MAPPING_ID=$(echo $MAPPING | jq -r '.id')

# Step 4: Test against a device
curl -sk -X POST "$BASE_URL/api/v1/models/$MODEL_ID/test" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"device-id\": $DEVICE_ID, \"mapping-id\": $MAPPING_ID}"

# Step 5: Get snapshot (requires active subscription)
curl -sk "$BASE_URL/api/v1/subscription/snapshots/$DEVICE_ID/gnmi-interfaces" \
  -H "Authorization: Bearer $TOKEN"
```

---

## 2. CLI Model with GoTTP Template

Create a model to parse CLI output using a TTP template.

```bash
# Step 1: Create model
MODEL=$(curl -sk -X POST "$BASE_URL/api/v1/models" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "cli-bgp-neighbors",
    "description": "BGP neighbor status via CLI",
    "version": "1.0.0"
  }')
MODEL_ID=$(echo $MODEL | jq -r '.id')                       # version id -> fields/mappings/test
FAMILY_ID=$(echo $MODEL | jq -r '."data-model-definition-id"')  # family id -> subscriptions

# Step 2: Add fields
for field in \
  '{"name":"neighbor-address","field-type":"string","format":"ip-address","required":true,"is-key":true,"position":0}' \
  '{"name":"remote-as","field-type":"uint32","format":"as-number","position":1}' \
  '{"name":"state","field-type":"string","position":2}' \
  '{"name":"prefixes-received","field-type":"uint32","position":3}'; do
  curl -sk -X POST "$BASE_URL/api/v1/models/$MODEL_ID/fields" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$field"
done

# Step 3: Add CLI mapping with TTP template
# Note: cli-template is a plain string (not JSON-encoded), cli-commands IS JSON-encoded
curl -sk -X POST "$BASE_URL/api/v1/models/$MODEL_ID/mappings" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "protocol": "cli",
    "netos": "ios-xr",
    "cli-commands": "[\"show bgp ipv4 unicast summary\"]",
    "cli-template": "{{ neighbor_address | IP }} {{ remote_as | to_int }} {{ state }} {{ prefixes | to_int }}",
    "field-mappings": "{\"neighbor_address\": \"neighbor-address\", \"remote_as\": \"remote-as\", \"state\": \"state\", \"prefixes\": \"prefixes-received\"}"
  }'
```

---

## 3. Export & Import Model

Export a model from one collector instance and import it to another.

```bash
# Export from source
curl -sk "$BASE_URL/api/v1/models/$MODEL_ID/export" \
  -H "Authorization: Bearer $TOKEN" > model-export.json

# Verify export
cat model-export.json | jq '.name, (.versions[0].fields | length), (.versions[0].mappings | length)'

# Import to destination (can be same or different instance)
curl -sk -X POST "$DEST_URL/api/v1/models/$DEST_VERSION_ID/import" \
  -H "Authorization: Bearer $DEST_TOKEN" \
  -H "Content-Type: application/json" \
  -d @model-export.json
```

---

## 4. Multi-Protocol Model

Same model with different mappings for different platforms/protocols.

```bash
# Create model
MODEL=$(curl -sk -X POST "$BASE_URL/api/v1/models" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "interface-counters", "description": "Multi-protocol interface counters"}')
MODEL_ID=$(echo $MODEL | jq -r '.id')                       # version id -> fields/mappings/test
FAMILY_ID=$(echo $MODEL | jq -r '."data-model-definition-id"')  # family id -> subscriptions

# Add fields (shared across all mappings)
for field in \
  '{"name":"interface-name","field-type":"string","required":true,"is-key":true,"position":0}' \
  '{"name":"in-octets","field-type":"uint64","position":1}' \
  '{"name":"out-octets","field-type":"uint64","position":2}'; do
  curl -sk -X POST "$BASE_URL/api/v1/models/$MODEL_ID/fields" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$field"
done

# Mapping 1: gNMI for IOS-XR
curl -sk -X POST "$BASE_URL/api/v1/models/$MODEL_ID/mappings" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "protocol": "gnmi",
    "netos": "ios-xr",
    "gnmi-paths": "[\"/interfaces/interface/state/counters\"]",
    "field-mappings": "{\"name\": \"interface-name\", \"in-octets\": \"in-octets\", \"out-octets\": \"out-octets\"}"
  }'

# Mapping 2: SNMP for IOS
curl -sk -X POST "$BASE_URL/api/v1/models/$MODEL_ID/mappings" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "protocol": "snmp",
    "netos": "ios",
    "snmp-walk-oids": "[\"1.3.6.1.2.1.2.2.1.2\", \"1.3.6.1.2.1.2.2.1.10\", \"1.3.6.1.2.1.2.2.1.16\"]",
    "field-mappings": "{\"1.3.6.1.2.1.2.2.1.2\": \"interface-name\", \"1.3.6.1.2.1.2.2.1.10\": \"in-octets\", \"1.3.6.1.2.1.2.2.1.16\": \"out-octets\"}"
  }'

# Mapping 3: NETCONF for IOS-XR
curl -sk -X POST "$BASE_URL/api/v1/models/$MODEL_ID/mappings" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "protocol": "netconf",
    "netos": "ios-xr",
    "netconf-filter-paths": "[\"<interfaces xmlns=\\\"http://openconfig.net/yang/interfaces\\\"/>\"]",
    "field-mappings": "{\"name\": \"interface-name\", \"state/counters/in-octets\": \"in-octets\", \"state/counters/out-octets\": \"out-octets\"}"
  }'
```

---

## 5. Full Stack Setup

Complete setup from device creation to live data collection.

```bash
# === Device Setup ===

# Create device
DEVICE=$(curl -sk -X POST "$BASE_URL/api/v1/devices" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "hostname": "core-1",
    "management-ip": "192.0.2.1",
    "net-os": "ios-xr",
    "active": true
  }')
DEVICE_ID=$(echo $DEVICE | jq -r '.id')

# Add gNMI protocol
PROTOCOL=$(curl -sk -X POST "$BASE_URL/api/v1/protocols" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"device-id\": $DEVICE_ID,
    \"type\": \"gnmi\",
    \"port\": 57400,
    \"username\": \"admin\",
    \"password\": \"admin123\",
    \"tls\": false,
    \"timeout\": 30
  }")
PROTOCOL_ID=$(echo $PROTOCOL | jq -r '.id')

# Enable protocol
curl -sk -X POST "$BASE_URL/api/v1/protocols/$PROTOCOL_ID/enable" \
  -H "Authorization: Bearer $TOKEN"

# === Model Setup ===

# Create model
MODEL=$(curl -sk -X POST "$BASE_URL/api/v1/models" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "system-info", "description": "System information"}')
MODEL_ID=$(echo $MODEL | jq -r '.id')                       # version id -> fields/mappings/test
FAMILY_ID=$(echo $MODEL | jq -r '."data-model-definition-id"')  # family id -> subscriptions

# Add fields
curl -sk -X POST "$BASE_URL/api/v1/models/$MODEL_ID/fields" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"hostname","field-type":"string","format":"hostname","required":true,"is-key":true,"position":0}'

curl -sk -X POST "$BASE_URL/api/v1/models/$MODEL_ID/fields" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"uptime","field-type":"string","format":"duration","position":1}'

# Add mapping
MAPPING=$(curl -sk -X POST "$BASE_URL/api/v1/models/$MODEL_ID/mappings" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "protocol": "gnmi",
    "netos": "ios-xr",
    "gnmi-paths": "[\"/system/state\"]",
    "field-mappings": "{\"hostname\": \"hostname\", \"boot-time\": \"uptime\"}"
  }')
MAPPING_ID=$(echo $MAPPING | jq -r '.id')

# === Test ===

curl -sk -X POST "$BASE_URL/api/v1/models/$MODEL_ID/test" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"device-id\": $DEVICE_ID, \"mapping-id\": $MAPPING_ID}"

# === Subscribe ===

curl -sk -X POST "$BASE_URL/api/v1/subscriptions" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"device-id\": $DEVICE_ID,
    \"data-model-definition-id\": $FAMILY_ID,
    \"protocol\": \"gnmi\",
    \"interval\": 60,
    \"enabled\": true
  }"

# === Snapshot (after subscription has collected data) ===

curl -sk "$BASE_URL/api/v1/subscription/snapshots/$DEVICE_ID/system-info" \
  -H "Authorization: Bearer $TOKEN"
```
