# Autonomous Pipelines

## Table of Contents
- [Workflow A: Zero to Prometheus + Grafana](#workflow-a-zero-to-prometheus--grafana) — Docker Compose, enable output, model+subscription, dashboard
- [Workflow B: Zero to InfluxDB + Grafana](#workflow-b-zero-to-influxdb--grafana) — Docker Compose, InfluxDB output, Flux queries
- [Workflow C: Quick Output Verification](#workflow-c-quick-output-verification) — enable backend, inject test data, verify
- [Dashboard Auto-Generation Logic](#dashboard-auto-generation-logic) — field-to-panel mapping rules

Complete end-to-end workflows for Claude Code to execute autonomously. Each workflow goes from zero to data flowing, using only collector API calls and standard tools.

**Prerequisites for all workflows**:
```bash
export BASE_URL="https://127.0.0.1:4030"
export TOKEN="$(cd /path/to/prelude-collector && go run . user token 2>/dev/null | tail -1)"
```

---

## Workflow A: Zero to Prometheus + Grafana

The most common autonomous pipeline. Collector exposes Prometheus metrics, Grafana scrapes and visualizes.

### Step 1: Docker Compose for Prometheus + Grafana

Create `docker-compose-monitoring.yml`:

```yaml
services:
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9091:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    extra_hosts:
      - "host.docker.internal:host-gateway"

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_AUTH_ANONYMOUS_ENABLED=true
      - GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer
    volumes:
      - ./grafana-provisioning:/etc/grafana/provisioning
```

Create `prometheus.yml`:

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prelude-collector'
    scheme: https
    tls_config:
      insecure_skip_verify: true
    static_configs:
      - targets: ['host.docker.internal:9090']
    metrics_path: '/metrics/collector'
```

Create `grafana-provisioning/datasources/prometheus.yml`:

```yaml
apiVersion: 1
datasources:
  - name: Prelude Collector
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
```

Start: `docker compose -f docker-compose-monitoring.yml up -d`

### Step 2: Enable Prometheus Output on Collector

```bash
curl -sk -X PUT "$BASE_URL/api/v1/outputs/prometheus" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ "enabled": true, "config": { "port": 9090, "metrics-path": "/metrics/collector" } }'
```

### Step 3: Create Device + Protocol (if not existing)

```bash
# Check existing devices
curl -sk "$BASE_URL/api/v1/devices" -H "Authorization: Bearer $TOKEN"

# Create device (skip if exists)
curl -sk -X POST "$BASE_URL/api/v1/devices" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "hostname": "core-1",
    "management-ip": "192.0.2.1",
    "net-os": "ios-xr",
    "is-active": true
  }'

# Create gNMI protocol for device (use device ID from response)
curl -sk -X POST "$BASE_URL/api/v1/protocols" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "device-id": 1,
    "type": "gnmi",
    "port": 57400,
    "username": "admin",
    "password": "<device-password>",
    "tls": true,
    "timeout": 10
  }'
```

### Step 4: Create Model + Fields + Mapping

```bash
# Create model
MODEL_RESPONSE=$(curl -sk -X POST "$BASE_URL/api/v1/models" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ "name": "interface-stats", "description": "Interface statistics", "version": "1.0.0", "is-active": true }')
MODEL_ID=$(echo "$MODEL_RESPONSE" | jq -r '.id')                        # version id -> fields/mappings
FAMILY_ID=$(echo "$MODEL_RESPONSE" | jq -r '."data-model-definition-id"')  # family id -> subscription

# Add fields
for field in \
  '{"name":"interface-name","field-type":"string","required":true,"is-key":true,"description":"Interface name","position":1}' \
  '{"name":"admin-status","field-type":"string","description":"Admin status","position":2}' \
  '{"name":"oper-status","field-type":"string","description":"Operational status","position":3}' \
  '{"name":"mtu","field-type":"uint32","description":"MTU size","position":4}' \
  '{"name":"in-octets","field-type":"uint64","description":"Input bytes","position":5}' \
  '{"name":"out-octets","field-type":"uint64","description":"Output bytes","position":6}'; do
  curl -sk -X POST "$BASE_URL/api/v1/models/$MODEL_ID/fields" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$field"
done

# Add gNMI mapping
curl -sk -X POST "$BASE_URL/api/v1/models/$MODEL_ID/mappings" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "protocol": "gnmi",
    "net-os": "ios-xr",
    "gnmi-paths": "[\"/interfaces/interface/state\"]",
    "field-mappings": "{\"name\":\"interface-name\",\"admin-status\":\"admin-status\",\"oper-status\":\"oper-status\",\"mtu\":\"mtu\",\"counters/in-octets\":\"in-octets\",\"counters/out-octets\":\"out-octets\"}",
    "field-transforms": "{\"admin-status\":[\"to_lower\"],\"oper-status\":[\"to_lower\"]}",
    "ignore-values": "{\"interface-name\":[\"Null0\",\"Loopback99\"]}"
  }'
```

### Step 5: Create Subscription (Starts Collection)

```bash
curl -sk -X POST "$BASE_URL/api/v1/subscriptions" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "device-id": 1,
    "data-model-definition-id": $FAMILY_ID,
    "protocol": "gnmi",
    "interval": 30,
    "enabled": true
  }'
```

### Step 6: Verify Data Flow

```bash
# Check output metrics (wait ~30s for first collection)
curl -sk "$BASE_URL/api/v1/outputs/metrics" -H "Authorization: Bearer $TOKEN"

# Check snapshot
curl -sk "$BASE_URL/api/v1/subscription/snapshots/1/interface-stats" -H "Authorization: Bearer $TOKEN"

# Check Prometheus endpoint directly
curl -sk "https://127.0.0.1:9090/metrics/collector" | grep collector_interface
```

### Step 7: Create Grafana Dashboard

```bash
GRAFANA_URL="http://localhost:3000"

# CRITICAL: Fetch the actual datasource UID first — it's auto-generated by Grafana
DS_UID=$(curl -s "$GRAFANA_URL/api/datasources" -u admin:admin | python3 -c "import sys,json; ds=json.load(sys.stdin); print(ds[0]['uid'])")

# Create dashboard via Grafana API
curl -s -X POST "$GRAFANA_URL/api/dashboards/db" \
  -H "Content-Type: application/json" \
  -d '{
    "dashboard": {
      "title": "Interface Statistics",
      "panels": [
        {
          "id": 1,
          "title": "MTU by Interface",
          "type": "bargauge",
          "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
          "targets": [{
            "expr": "collector_interface_stats_mtu",
            "legendFormat": "{{device}} - {{key}}"
          }],
          "datasource": { "type": "prometheus", "uid": "'"$DS_UID"'" }
        },
        {
          "id": 2,
          "title": "Input Octets",
          "type": "timeseries",
          "gridPos": { "h": 8, "w": 12, "x": 12, "y": 0 },
          "targets": [{
            "expr": "rate(collector_interface_stats_in_octets[5m])",
            "legendFormat": "{{device}} - {{key}}"
          }],
          "datasource": { "type": "prometheus", "uid": "'"$DS_UID"'" }
        },
        {
          "id": 3,
          "title": "Output Octets",
          "type": "timeseries",
          "gridPos": { "h": 8, "w": 12, "x": 0, "y": 8 },
          "targets": [{
            "expr": "rate(collector_interface_stats_out_octets[5m])",
            "legendFormat": "{{device}} - {{key}}"
          }],
          "datasource": { "type": "prometheus", "uid": "'"$DS_UID"'" }
        }
      ],
      "refresh": "30s",
      "time": { "from": "now-1h", "to": "now" }
    },
    "overwrite": true
  }'
```

---

## Workflow B: Zero to InfluxDB + Grafana

### Step 1: Docker Compose for InfluxDB + Grafana

```yaml
services:
  influxdb:
    image: influxdb:2
    ports:
      - "8086:8086"
    environment:
      - DOCKER_INFLUXDB_INIT_MODE=setup
      - DOCKER_INFLUXDB_INIT_USERNAME=admin
      - DOCKER_INFLUXDB_INIT_PASSWORD=adminpassword
      - DOCKER_INFLUXDB_INIT_ORG=prelude
      - DOCKER_INFLUXDB_INIT_BUCKET=collector
      - DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=my-super-secret-token

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_AUTH_ANONYMOUS_ENABLED=true
      - GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer
```

Start: `docker compose -f docker-compose-influxdb.yml up -d`

### Step 2: Enable InfluxDB Output

```bash
curl -sk -X PUT "$BASE_URL/api/v1/outputs/influxdb" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "enabled": true,
    "config": {
      "url": "http://localhost:8086",
      "token": "my-super-secret-token",
      "org": "prelude",
      "bucket": "collector",
      "batch-size": 100,
      "flush-interval": 5000
    }
  }'
```

### Step 3: Device + Model + Subscription

Same as Workflow A Steps 3-5. Create device, model, fields, mapping, and subscription.

### Step 4: Create Grafana InfluxDB Data Source

```bash
curl -s -X POST "http://localhost:3000/api/datasources" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Prelude InfluxDB",
    "type": "influxdb",
    "access": "proxy",
    "url": "http://influxdb:8086",
    "jsonData": {
      "version": "Flux",
      "organization": "prelude",
      "defaultBucket": "collector"
    },
    "secureJsonData": {
      "token": "my-super-secret-token"
    }
  }'
```

### Step 5: Create Grafana Dashboard with Flux Queries

```bash
# CRITICAL: Fetch the actual datasource UID first — it's auto-generated by Grafana
DS_UID=$(curl -s "http://localhost:3000/api/datasources" -u admin:admin | python3 -c "import sys,json; ds=json.load(sys.stdin); print(ds[0]['uid'])")

curl -s -X POST "http://localhost:3000/api/dashboards/db" \
  -H "Content-Type: application/json" \
  -d '{
    "dashboard": {
      "title": "Interface Statistics (InfluxDB)",
      "panels": [
        {
          "id": 1,
          "title": "Input Traffic",
          "type": "timeseries",
          "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
          "targets": [{
            "query": "from(bucket: \"collector\")\n  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)\n  |> filter(fn: (r) => r._measurement == \"interface-stats\")\n  |> filter(fn: (r) => r._field == \"in-octets\")\n  |> derivative(unit: 1s, nonNegative: true)"
          }]
        },
        {
          "id": 2,
          "title": "Output Traffic",
          "type": "timeseries",
          "gridPos": { "h": 8, "w": 12, "x": 12, "y": 0 },
          "targets": [{
            "query": "from(bucket: \"collector\")\n  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)\n  |> filter(fn: (r) => r._measurement == \"interface-stats\")\n  |> filter(fn: (r) => r._field == \"out-octets\")\n  |> derivative(unit: 1s, nonNegative: true)"
          }]
        }
      ],
      "refresh": "30s"
    },
    "overwrite": true
  }'
```

---

## Workflow C: Quick Output Verification

Lightweight workflow to verify any backend works without real devices.

### Step 1: Enable Backend

```bash
# Example: enable file output
curl -sk -X PUT "$BASE_URL/api/v1/outputs/file" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ "enabled": true, "config": { "output-dir": "/tmp/collector-data", "format": "jsonl" } }'
```

### Step 2: Inject Test Data

```bash
curl -sk -X POST "$BASE_URL/api/v1/outputs/test-output" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '[
    {
      "device": "test-router",
      "device_id": 999,
      "model_name": "test-model",
      "key": "test-key-1",
      "data": { "value": 42, "status": "up" }
    },
    {
      "device": "test-router",
      "device_id": 999,
      "model_name": "test-model",
      "key": "test-key-2",
      "data": { "value": 99, "status": "down" }
    }
  ]'
```

### Step 3: Verify

```bash
# Check metrics
curl -sk "$BASE_URL/api/v1/outputs/metrics" -H "Authorization: Bearer $TOKEN"

# Backend-specific verification:
# File:       cat /tmp/collector-data/test-model.jsonl
# NATS:       nats sub "collector.data.test-model.999"
# Prometheus: curl -sk https://127.0.0.1:9090/metrics/collector | grep test_model
# Webhook:    check your receiver logs
```

---

## Dashboard Auto-Generation Logic

When Claude creates Grafana dashboards autonomously, use this mapping from model fields to panel types:

| Field Type | Prometheus Panel | InfluxDB Panel |
|------------|-----------------|----------------|
| `uint64` (counters like in-octets) | `timeseries` with `rate()` | `timeseries` with `toFloat() \|> derivative()` |
| `uint32`/`int32` (gauges like mtu) | `bargauge` or `stat` | `bargauge` or `stat` |
| `float32`/`float64` | `timeseries` or `gauge` | `timeseries` or `gauge` |
| `string` (status like admin-status) | `table` panel | `table` panel |
| `boolean` | `stat` with value mapping | `stat` with value mapping |

**Prometheus metric naming**: `collector_{model}_{field}` where non-alphanumeric chars become `_`

Example: model `interface-stats`, field `in-octets` → `collector_interface_stats_in_octets`

**PromQL patterns**:
- Gauge: `collector_{model}_{field}{device="X"}`
- Counter rate: `rate(collector_{model}_{field}[5m])`
- Top N: `topk(10, collector_{model}_{field})`
- Per device: `collector_{model}_{field}{device=~"$device"}`

**Flux query patterns**:
- Basic: `from(bucket:"collector") |> filter(fn: (r) => r._measurement == "model") |> filter(fn: (r) => r._field == "field")`
- Rate: append `|> toFloat() |> derivative(unit: 1s, nonNegative: true)` — **`toFloat()` is required** because the collector writes integer counters and `derivative()` only works on floats
- Device filter: append `|> filter(fn: (r) => r.device == "hostname")`
- Current values table: append `|> last() |> pivot(rowKey: ["_time"], columnKey: ["_field"], valueColumn: "_value")`
