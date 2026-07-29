# Grafana Integration

Two deployment modes: **Docker Compose** for dev/test (fully autonomous) and **API-only** for production (existing Grafana).

---

## Docker Compose (Dev/Test)

### Prometheus + Grafana Stack

Create this alongside your collector for a zero-config monitoring stack.

**docker-compose-monitoring.yml**:

```yaml
services:
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9091:9090"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
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
      - ./monitoring/grafana/provisioning:/etc/grafana/provisioning
    depends_on:
      - prometheus
```

**monitoring/prometheus.yml**:

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

**monitoring/grafana/provisioning/datasources/prelude.yml**:

```yaml
apiVersion: 1
datasources:
  - name: Prelude Collector
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
```

Start: `docker compose -f docker-compose-monitoring.yml up -d`

Grafana available at `http://localhost:3000` (admin/admin, anonymous read enabled).

### InfluxDB + Grafana Stack

**docker-compose-influxdb.yml**:

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
      - DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=prelude-influxdb-token

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_AUTH_ANONYMOUS_ENABLED=true
      - GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer
    volumes:
      - ./monitoring/grafana/provisioning:/etc/grafana/provisioning
    depends_on:
      - influxdb
```

**monitoring/grafana/provisioning/datasources/influxdb.yml**:

```yaml
apiVersion: 1
datasources:
  - name: Prelude InfluxDB
    type: influxdb
    access: proxy
    url: http://influxdb:8086
    isDefault: true
    jsonData:
      version: Flux
      organization: prelude
      defaultBucket: collector
    secureJsonData:
      token: prelude-influxdb-token
```

---

## API-Only (Production)

For existing Grafana instances. Uses Grafana HTTP API.

### Authentication

Generate a Grafana service account token:

```bash
# Via UI: Grafana → Administration → Service Accounts → Add token
# Via API (if admin creds available):
GRAFANA_URL="http://grafana.example.com:3000"
GRAFANA_TOKEN="your-service-account-token"

# Or use basic auth for initial setup:
curl -s -u admin:admin "$GRAFANA_URL/api/org"
```

All Grafana API calls:
```bash
curl -s -X METHOD "$GRAFANA_URL/api/ENDPOINT" \
  -H "Authorization: Bearer $GRAFANA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ ... }'
```

### Create Prometheus Data Source

```bash
curl -s -X POST "$GRAFANA_URL/api/datasources" \
  -H "Authorization: Bearer $GRAFANA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Prelude Collector",
    "type": "prometheus",
    "access": "proxy",
    "url": "http://prometheus:9090",
    "isDefault": false
  }'
```

### Create InfluxDB Data Source

```bash
curl -s -X POST "$GRAFANA_URL/api/datasources" \
  -H "Authorization: Bearer $GRAFANA_TOKEN" \
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
      "token": "your-influxdb-token"
    }
  }'
```

### Get Data Source UID (needed for dashboards)

```bash
# List all data sources
curl -s "$GRAFANA_URL/api/datasources" \
  -H "Authorization: Bearer $GRAFANA_TOKEN" | jq '.[].uid'
```

### Create Dashboard

**Critical**: Always fetch the datasource UID via `GET /api/datasources` before creating dashboards. Grafana auto-generates UIDs for provisioned datasources — never hardcode them.

```bash
curl -s -X POST "$GRAFANA_URL/api/dashboards/db" \
  -H "Authorization: Bearer $GRAFANA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "dashboard": {
      "title": "Dashboard Title",
      "panels": [ ... ],
      "refresh": "30s",
      "time": { "from": "now-1h", "to": "now" }
    },
    "overwrite": true
  }'
```

Response includes `url` field — the dashboard permalink.

### Delete Dashboard

```bash
curl -s -X DELETE "$GRAFANA_URL/api/dashboards/uid/{dashboard-uid}" \
  -H "Authorization: Bearer $GRAFANA_TOKEN"
```

---

## Panel Templates

### Prometheus Time Series (for counters)

```json
{
  "id": 1,
  "title": "Traffic Rate",
  "type": "timeseries",
  "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
  "fieldConfig": {
    "defaults": {
      "unit": "Bps"
    }
  },
  "targets": [{
    "expr": "rate(collector_{model}_{field}[5m])",
    "legendFormat": "{{device}} - {{key}}"
  }],
  "datasource": { "type": "prometheus", "uid": "DATASOURCE_UID" }
}
```

### Prometheus Bar Gauge (for gauges)

```json
{
  "id": 2,
  "title": "MTU by Interface",
  "type": "bargauge",
  "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
  "targets": [{
    "expr": "collector_{model}_{field}",
    "legendFormat": "{{device}} - {{key}}"
  }],
  "options": {
    "orientation": "horizontal",
    "displayMode": "gradient"
  },
  "datasource": { "type": "prometheus", "uid": "DATASOURCE_UID" }
}
```

### Prometheus Stat (for status)

```json
{
  "id": 3,
  "title": "Interfaces Up",
  "type": "stat",
  "gridPos": { "h": 4, "w": 6, "x": 0, "y": 0 },
  "targets": [{
    "expr": "count(collector_{model}_{field} == 1)",
    "legendFormat": "Up"
  }],
  "options": {
    "colorMode": "background"
  },
  "datasource": { "type": "prometheus", "uid": "DATASOURCE_UID" }
}
```

### Prometheus Table (for string/mixed data)

```json
{
  "id": 4,
  "title": "Interface Status",
  "type": "table",
  "gridPos": { "h": 10, "w": 24, "x": 0, "y": 0 },
  "targets": [{
    "expr": "collector_{model}_{field}",
    "format": "table",
    "instant": true
  }],
  "datasource": { "type": "prometheus", "uid": "DATASOURCE_UID" }
}
```

### InfluxDB Time Series

```json
{
  "id": 1,
  "title": "Traffic Rate",
  "type": "timeseries",
  "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
  "targets": [{
    "query": "from(bucket: \"collector\")\n  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)\n  |> filter(fn: (r) => r._measurement == \"{model}\")\n  |> filter(fn: (r) => r._field == \"{field}\")\n  |> derivative(unit: 1s, nonNegative: true)",
    "refId": "A"
  }],
  "datasource": { "type": "influxdb", "uid": "DATASOURCE_UID" }
}
```

### InfluxDB Table

```json
{
  "id": 2,
  "title": "Current Values",
  "type": "table",
  "gridPos": { "h": 10, "w": 24, "x": 0, "y": 0 },
  "targets": [{
    "query": "from(bucket: \"collector\")\n  |> range(start: -5m)\n  |> filter(fn: (r) => r._measurement == \"{model}\")\n  |> last()\n  |> pivot(rowKey: [\"_time\"], columnKey: [\"_field\"], valueColumn: \"_value\")",
    "refId": "A"
  }],
  "datasource": { "type": "influxdb", "uid": "DATASOURCE_UID" }
}
```

---

## Field-to-Panel Mapping

When auto-generating dashboards from a collector model, use this logic:

| Field Type | Best Panel | PromQL Pattern | Flux Pattern |
|------------|-----------|----------------|--------------|
| `uint64` (counter) | timeseries | `rate(metric[5m])` | `derivative(unit:1s)` |
| `uint32` (gauge) | bargauge / stat | `metric` | `last()` |
| `float32/64` | timeseries | `metric` | direct |
| `string` (status) | table | N/A (not in Prometheus) | `pivot()` + `last()` |
| `boolean` | stat | `metric == 1` | value mapping |

**Prometheus metric naming**: `collector_{model_name}_{field_name}` — hyphens become underscores.

Example: model `interface-stats`, field `in-octets` → `collector_interface_stats_in_octets`

**Common units** (`fieldConfig.defaults.unit`):
- Bytes/sec: `Bps` | Bits/sec: `bps` | Bytes: `bytes` | Seconds: `s` | Percent: `percent`

---

## Grafana Dashboard Grid Layout

Standard layout for network models:

```
Row 0 (y=0):  [ Stat panels — key counts/statuses ] (h=4)
Row 1 (y=4):  [ Time series — traffic/counters    ] (h=8, w=12 each)
Row 2 (y=12): [ Table — full inventory view        ] (h=10, w=24)
```

Grid is 24 columns wide. Panel positions: `gridPos: { h, w, x, y }`.
