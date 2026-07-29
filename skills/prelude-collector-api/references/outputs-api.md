# Outputs API Reference

Configure, enable, and monitor output backends that receive collected data from the pipeline.

## Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/v1/outputs` | List all backends with status |
| GET | `/api/v1/outputs/{backend}` | Get single backend config |
| PUT | `/api/v1/outputs/{backend}` | Configure and/or enable backend |
| DELETE | `/api/v1/outputs/{backend}` | Delete backend config (stops output) |
| GET | `/api/v1/outputs/metrics` | Per-backend success/failure metrics |
| POST | `/api/v1/outputs/test-output` | Inject test data into all enabled backends |
| POST | `/api/v1/outputs/{backend}/detect` | Probe backend connectivity and config validity |

Valid `{backend}` values: `nats`, `influxdb`, `kafka`, `prometheus`, `webhook`, `file`,
`timescaledb`

### Cleartext HTTP is refused

For any backend with a URL (`influxdb`, `webhook`), an `http://` URL to a **non-loopback** host
requires `"insecure-http": true` in the config. Without it:

- `PUT /api/v1/outputs/{backend}` → **422**, `field-errors.url` =
  `Cleartext http:// to a non-loopback host requires "insecure-http": true — or use https://`
- `POST /api/v1/outputs/{backend}/detect` → a failed `transport` check (not a misleading pass)

Loopback (`127.0.0.1`, `localhost`) is exempt. The guard exists because the backend refuses to
start on a cleartext URL, so without it the API would persist a config that can never run.

---

## List All Backends

```bash
curl -sk "$BASE_URL/api/v1/outputs" \
  -H "Authorization: Bearer $TOKEN"
```

Response `200`:
```json
[
  {
    "backend": "nats",
    "label": "NATS",
    "description": "Publish collected data to NATS subjects",
    "enabled": true,
    "configured": true,
    "config": { "url": "nats://localhost:4222", "seed-path": "/path/to/seed.txt", "client-name": "prelude-collector" }
  },
  {
    "backend": "prometheus",
    "label": "Prometheus",
    "description": "Expose metrics on a /metrics endpoint for scraping",
    "enabled": false,
    "configured": false,
    "config": null
  }
]
```

## Get Single Backend

```bash
curl -sk "$BASE_URL/api/v1/outputs/prometheus" \
  -H "Authorization: Bearer $TOKEN"
```

## Configure / Enable Backend

```bash
curl -sk -X PUT "$BASE_URL/api/v1/outputs/{backend}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ "enabled": true, "config": { ... } }'
```

**Sensitive field handling**: Fields sent as empty string or `"********"` preserve the existing value from DB. This allows partial config updates without exposing secrets.

**Hot reload**: After a successful PUT, the output manager automatically reloads the backend — no restart required.

## Delete Backend Config

```bash
curl -sk -X DELETE "$BASE_URL/api/v1/outputs/{backend}" \
  -H "Authorization: Bearer $TOKEN"
```

Response: `204 No Content`. Hard delete — backend stops and config is removed.

## Get Output Metrics

```bash
curl -sk "$BASE_URL/api/v1/outputs/metrics" \
  -H "Authorization: Bearer $TOKEN"
```

Response `200`:
```json
{
  "nats": {
    "successes": 1250,
    "failures": 5,
    "last-output-at": "2026-03-18T15:32:45Z",
    "last-failure-at": "2026-03-18T14:20:12Z"
  },
  "prometheus": {
    "successes": 0,
    "failures": 0,
    "last-output-at": "",
    "last-failure-at": ""
  }
}
```

## Inject Test Data

Send an array of ParsedData objects directly into all enabled output backends. Useful for end-to-end testing without needing real devices.

```bash
curl -sk -X POST "$BASE_URL/api/v1/outputs/test-output" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '[
    {
      "timestamp": "2026-03-18T15:30:00Z",
      "device": "core-1",
      "device_id": 1,
      "model_name": "interfaces",
      "key": "GigabitEthernet0/0/0",
      "data": {
        "speed": 10000000000,
        "mtu": 1500,
        "admin-status": "up",
        "oper-status": "up"
      }
    }
  ]'
```

Response `200`:
```json
{ "injected": 1, "failures": 0 }
```

Constraints: max 1000 items per batch, missing timestamps auto-filled with current time.

---

## Backend Configuration Schemas

### NATS

```json
{
  "enabled": true,
  "config": {
    "url": "nats://localhost:4222",
    "seed-path": "/path/to/seed.txt",
    "client-name": "prelude-collector"
  }
}
```

- `url` (required): NATS server URL
- `seed-path`: NKey seed file path (optional, for NKey auth)
- `client-name`: NATS client identifier

**Output format**: Publishes JSON to topic `collector.data.{modelName}.{deviceId}`

Example: model "interfaces" on device ID 1 → topic `collector.data.interfaces.1`

### Prometheus

```json
{
  "enabled": true,
  "config": {
    "metrics-path": "/metrics/collector",
    "port": 9090
  }
}
```

- `metrics-path`: HTTP path for scraping (default: `/metrics/collector`)
- `port`: Listen port (default: `9090`)

**Output format**: Prometheus gauges

- Metric name: `collector_{modelName}_{fieldName}` (non-alphanumeric → underscore)
- Labels: `device`, `device_id`, `key`
- Only numeric fields exported (strings/maps silently skipped)
- Pull-based: Prometheus scrapes the endpoint; no batching

**Scrape URL**: `https://{collector-host}:{port}{metrics-path}`

Example metric:
```
collector_interfaces_mtu{device="core-1",device_id="1",key="GigabitEthernet0/0/0"} 1500
collector_interfaces_speed{device="core-1",device_id="1",key="GigabitEthernet0/0/0"} 1e+10
```

### InfluxDB

One backend, two config shapes chosen by `version`. Blank defaults to v2.

**v2** (`"version": "v2"` or omitted):

```json
{
  "enabled": true,
  "config": {
    "version": "v2",
    "url": "https://localhost:8086",
    "token": "your-api-token",
    "org": "my-org",
    "bucket": "collector",
    "batch-size": 100,
    "flush-interval": 5000
  }
}
```

- `url` (required), `token` (required, masked `********` in responses), `org` (required),
  `bucket` (required)

**v1.x** (`"version": "v1"`, covers InfluxDB 1.0–1.8):

```json
{
  "enabled": true,
  "config": {
    "version": "v1",
    "url": "http://127.0.0.1:8086",
    "database": "prelude",
    "retention-policy": "autogen",
    "username": "admin",
    "password": "secret",
    "batch-size": 100,
    "flush-interval": 5000
  }
}
```

- `database` (**required for v1**), `retention-policy`, `username`/`password` optional
- Sending v2 fields with `"version": "v1"` is ignored, and omitting `database` is **422**

Common to both: `batch-size` points before flush, `flush-interval` ms between auto-flushes,
`insecure-http` to allow a cleartext non-loopback URL.

Unsigned integer fields are written as plain integers — InfluxDB 1.x rejects the `u` suffix
that would otherwise silently drop those lines.

**Output format**: InfluxDB line protocol

- Measurement: model name (e.g., `interfaces`)
- Tags: `device`, `device-id`, `key`
- Fields: all scalar values from parsed data (flattened, nested maps/arrays skipped)

### Kafka

```json
{
  "enabled": true,
  "config": {
    "brokers": "broker1:9092,broker2:9092",
    "topic": "collector-data",
    "sasl-mechanism": "PLAIN",
    "sasl-username": "user",
    "sasl-password": "password",
    "tls-enabled": true
  }
}
```

- `brokers` (required): Comma-separated broker addresses
- `topic`: Kafka topic (empty = per-model topics)
- `sasl-mechanism`: `PLAIN`, `SCRAM-SHA-256`, `SCRAM-SHA-512`, or empty
- `sasl-username`/`sasl-password`: SASL credentials (password masked in responses)
- `tls-enabled`: Enable TLS

**Output format**: JSON message, key = `{modelName}-{deviceId}` for partition locality

### Webhook

```json
{
  "enabled": true,
  "config": {
    "url": "https://webhook.example.com/data",
    "method": "POST",
    "headers": { "X-Custom-Header": "value" },
    "auth-header": "Bearer token123",
    "batch-mode": true,
    "timeout-ms": 10000
  }
}
```

- `url` (required): HTTP(S) endpoint
- `method`: `POST` or `PUT` (default: `POST`)
- `headers`: Custom HTTP headers
- `auth-header`: Authorization header value (masked in responses)
- `batch-mode`: `true` = single request with array, `false` = one request per item
- `timeout-ms`: Request timeout (default: `10000`)

### File

```json
{
  "enabled": true,
  "config": {
    "output-dir": "/var/collector/data",
    "format": "jsonl",
    "rotate-after-mb": 100
  }
}
```

- `output-dir` (required): Directory to write files
- `format`: `jsonl` or `csv` (default: `jsonl`)
- `rotate-after-mb`: Size-based rotation in MB (0 = no rotation)

**Output format**:
- JSONL: one JSON object per line, one file per model
- CSV: columns = `timestamp`, `device`, `device-id`, `model`, `key`, + all scalar fields; headers written on first line

### TimescaleDB

Long-term metric storage: one row per (metric, sample) in a self-provisioned hypertable.

```json
{
  "enabled": true,
  "config": {
    "host": "timescale.lan",
    "port": 5432,
    "database": "metrics",
    "username": "collector",
    "password": "secret",
    "ssl-mode": "require",
    "table": "collector_metrics",
    "batch-size": 1000,
    "flush-interval": 5000
  }
}
```

- `host`, `database`, `username`, `password` required; `port` defaults 5432
- `ssl-mode`: `disable` | `require` (default) | `verify-ca` | `verify-full`
- `table`: hypertable name, defaults `collector_metrics`
- `batch-size`: rows buffered before a COPY flush (default 1000); `flush-interval` ms (default 5000)
- Blank `password` preserves the stored one, same as the InfluxDB token
- Retention/compression policies take `"<N> <unit>"` literals (`"7 days"`); blank applies the
  recommended default, `"off"`/`"none"`/`"never"`/`"0"` disables. They need the `timescaledb`
  extension — on plain PostgreSQL they are skipped with a warning.

---

## ParsedData Format

All backends receive the same ParsedData structure:

```json
{
  "timestamp": "2026-03-18T15:30:00Z",
  "device": "core-1",
  "device_id": 1,
  "model_name": "interfaces",
  "key": "GigabitEthernet0/0/0",
  "data": {
    "admin-status": "up",
    "oper-status": "up",
    "mtu": 1500,
    "speed": 10000000000
  }
}
```

**Field flattening** (`ParsedDataToFields()`): Time-series backends (Prometheus, InfluxDB, File/CSV) flatten the `data` map to scalar values only — nested maps and arrays are skipped.

---

## Probe Backend Connectivity (Detect)

Probe an output backend to verify connectivity, authentication, and configuration validity before saving.

```bash
# Probe with config from request body (pre-save validation)
curl -sk -X POST "$BASE_URL/api/v1/outputs/influxdb/detect" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "enabled": true,
    "config": {
      "url": "http://localhost:8086",
      "token": "my-token",
      "org": "prelude",
      "bucket": "collector"
    }
  }'

# Probe saved config from DB (no body needed)
curl -sk -X POST "$BASE_URL/api/v1/outputs/nats/detect" \
  -H "Authorization: Bearer $TOKEN"
```

Response `200`:
```json
{
  "backend": "influxdb",
  "all-passed": false,
  "duration-ms": 342,
  "checks": [
    { "name": "reachable", "passed": true, "message": "InfluxDB health endpoint responded" },
    { "name": "authenticated", "passed": true, "message": "Token is valid" },
    { "name": "org-valid", "passed": false, "message": "Organization 'wrong-org' not found" },
    { "name": "bucket-valid", "passed": false, "message": "Skipped (previous check failed)" }
  ]
}
```

**Per-backend checks:**
- **InfluxDB**: reachable (health), authenticated (token), org-valid, bucket-valid
- **NATS**: reachable (connect), authenticated (NKey if configured)
- **Kafka**: reachable (broker dial), topic-exists (if topic configured)
- **Webhook**: reachable (HTTP HEAD), tls-valid (if HTTPS)
- **Prometheus**: port-available
- **File**: dir-exists, writable

**Sensitive fields**: Masked tokens (`********`) in the request body are automatically recovered from the saved DB config.

---

## End-to-End Pipeline Validation

Validate the full data collection pipeline in one call: device → protocol → reachability → connection → collection → mapping → output.

```bash
curl -sk -X POST "$BASE_URL/api/v1/pipelines/validate" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "device-id": 1,
    "model-name": "interface-stats",
    "protocol": "gnmi",
    "run-all": false
  }'
```

Request fields:
- `device-id` (required): Device to validate
- `model-name` (required): Data model to validate
- `protocol` (optional): Filter to specific protocol
- `mapping-id` (optional): Use specific mapping ID
- `run-all` (optional, default false): If false, stops at first failure; if true, runs all stages

Response `200`:
```json
{
  "device-id": 1,
  "device": "core-1",
  "model-name": "interface-stats",
  "protocol": "gnmi",
  "all-passed": true,
  "total-duration-ms": 4230,
  "stages": [
    { "stage": "device-check", "status": "pass", "message": "Device 'core-1' is active", "duration-ms": 2 },
    { "stage": "protocol-check", "status": "pass", "message": "GNMI protocol enabled on device", "duration-ms": 3 },
    { "stage": "reachability-check", "status": "pass", "message": "3/3 pings received from 192.0.2.1", "duration-ms": 1050 },
    { "stage": "connection-check", "status": "pass", "message": "GNMI connected to 192.0.2.1:57400", "duration-ms": 320 },
    { "stage": "collection-check", "status": "pass", "message": "Received 12 raw updates, parsed 8 records", "duration-ms": 2100 },
    { "stage": "mapping-check", "status": "pass", "message": "Parsed 8 records, fields populated: admin-status, in-octets, ...", "duration-ms": 5 },
    { "stage": "output-check", "status": "pass", "message": "1 backend(s) reachable: nats", "duration-ms": 750 }
  ]
}
```

**Seven stages**: device-check, protocol-check, reachability-check, connection-check, collection-check, mapping-check, output-check. Each returns `"pass"`, `"fail"`, or `"skip"` (when a prior stage failed and `run-all` is false).
