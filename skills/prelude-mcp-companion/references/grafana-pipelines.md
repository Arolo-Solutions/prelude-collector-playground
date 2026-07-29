# Grafana & Autonomous Pipelines

## Docker Compose Stacks

### Prometheus + Grafana

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

### InfluxDB + Grafana

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

## Grafana API (Production)

```bash
GRAFANA_URL="http://grafana.example.com:3000"
GRAFANA_TOKEN="your-service-account-token"
```

### Create Data Sources

**Prometheus:**
```bash
curl -s -X POST "$GRAFANA_URL/api/datasources" \
  -H "Authorization: Bearer $GRAFANA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Prelude Collector","type":"prometheus","access":"proxy","url":"http://prometheus:9090","isDefault":false}'
```

**InfluxDB:**
```bash
curl -s -X POST "$GRAFANA_URL/api/datasources" \
  -H "Authorization: Bearer $GRAFANA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Prelude InfluxDB","type":"influxdb","access":"proxy","url":"http://influxdb:8086","jsonData":{"version":"Flux","organization":"prelude","defaultBucket":"collector"},"secureJsonData":{"token":"your-token"}}'
```

### Create Dashboard

**Critical**: Always fetch the datasource UID first — Grafana auto-generates UIDs.

```bash
DS_UID=$(curl -s "$GRAFANA_URL/api/datasources" -H "Authorization: Bearer $GRAFANA_TOKEN" | jq -r '.[0].uid')

curl -s -X POST "$GRAFANA_URL/api/dashboards/db" \
  -H "Authorization: Bearer $GRAFANA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"dashboard":{"title":"Dashboard Title","panels":[...],"refresh":"30s","time":{"from":"now-1h","to":"now"}},"overwrite":true}'
```

---

## Dashboard Auto-Generation

### Field-to-Panel Mapping

| Field Type | Prometheus Panel | InfluxDB Panel |
|------------|-----------------|----------------|
| `uint64` (counters) | `timeseries` + `rate()` | `timeseries` + `derivative()` |
| `uint32`/`int32` (gauges) | `bargauge` or `stat` | `bargauge` or `stat` |
| `float32`/`float64` | `timeseries` or `gauge` | `timeseries` or `gauge` |
| `string` (status) | `table` | `table` |
| `boolean` | `stat` + value mapping | `stat` + value mapping |

### Prometheus Metric Naming

`collector_{model}_{field}` — hyphens become underscores.
Example: model `interface-stats`, field `in-octets` → `collector_interface_stats_in_octets`

Labels: `device`, `device_id`, `key`

### PromQL Patterns

- Gauge: `collector_{model}_{field}{device="X"}`
- Counter rate: `rate(collector_{model}_{field}[5m])`
- Top N: `topk(10, collector_{model}_{field})`
- Per device: `collector_{model}_{field}{device=~"$device"}`

### Flux Patterns

- Basic: `from(bucket:"collector") |> filter(fn: (r) => r._measurement == "model") |> filter(fn: (r) => r._field == "field")`
- Rate: append `|> toFloat() |> derivative(unit: 1s, nonNegative: true)` — **`toFloat()` required** for integer counters
- Current values: append `|> last() |> pivot(rowKey: ["_time"], columnKey: ["_field"], valueColumn: "_value")`

### Panel Templates

**Prometheus timeseries:**
```json
{"title":"Traffic Rate","type":"timeseries","gridPos":{"h":8,"w":12,"x":0,"y":0},"fieldConfig":{"defaults":{"unit":"Bps"}},"targets":[{"expr":"rate(collector_{model}_{field}[5m])","legendFormat":"{{device}} - {{key}}"}],"datasource":{"type":"prometheus","uid":"UID"}}
```

**Prometheus bargauge:**
```json
{"title":"MTU","type":"bargauge","gridPos":{"h":8,"w":12,"x":0,"y":0},"targets":[{"expr":"collector_{model}_{field}","legendFormat":"{{device}} - {{key}}"}],"options":{"orientation":"horizontal","displayMode":"gradient"},"datasource":{"type":"prometheus","uid":"UID"}}
```

**Prometheus stat:**
```json
{"title":"Up Count","type":"stat","gridPos":{"h":4,"w":6,"x":0,"y":0},"targets":[{"expr":"count(collector_{model}_{field} == 1)"}],"options":{"colorMode":"background"},"datasource":{"type":"prometheus","uid":"UID"}}
```

**InfluxDB timeseries:**
```json
{"title":"Traffic","type":"timeseries","gridPos":{"h":8,"w":12,"x":0,"y":0},"targets":[{"query":"from(bucket:\"collector\") |> range(start:v.timeRangeStart,stop:v.timeRangeStop) |> filter(fn:(r)=>r._measurement==\"{model}\") |> filter(fn:(r)=>r._field==\"{field}\") |> derivative(unit:1s,nonNegative:true)"}],"datasource":{"type":"influxdb","uid":"UID"}}
```

### Grid Layout

```
Row 0 (y=0):  [ Stat panels — key counts/statuses ] (h=4)
Row 1 (y=4):  [ Time series — traffic/counters    ] (h=8, w=12 each)
Row 2 (y=12): [ Table — full inventory view        ] (h=10, w=24)
```

Common units: Bytes/sec `Bps`, Bits/sec `bps`, Bytes `bytes`, Seconds `s`, Percent `percent`
