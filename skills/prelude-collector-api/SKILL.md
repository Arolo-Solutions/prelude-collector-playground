---
name: prelude-collector-api
description: Prelude Collector REST API — data models (family/version), fields, protocol mappings, live testing, snapshots, subscriptions, output backends (NATS, Prometheus, InfluxDB v1/v2, Kafka, Webhook, File, TimescaleDB), GoTTP/TTP templates, transforms, vendor profiles, Grafana pipelines, YANG tree browser, and SNMP MIB browser. Triggers on "collector API", "curl collector", "test mapping", "get snapshot", "API token", "export model", "import model", "TTP template", "GoTTP", "output backend", "enable output", "prometheus", "grafana", "influxdb", "kafka", "webhook", "nats output", "output metrics", "test output", "test cli", "data pipeline", "zero to dashboard", "yang tree", "yang catalog", "yang modules", "yang search", "yang deviations", "snmp browser", "mib browser", "snmp oid", "snmp search", "snmp walk api", "walk profiles", "vendor profile", "config export", "git sync".
---

# Prelude Collector API

REST API at `/api/v1/` for managing network telemetry data models, fields, protocol mappings,
live testing, subscriptions, and snapshots.

Written against collector **1.1.3**. The generated spec is the tie-breaker: run `make swagger`
in the collector checkout and read `api-docs/swagger.json`, or browse
`https://<host>:4030/swagger/index.html`.

## Quick Start

### Authentication

```bash
cd /path/to/prelude-collector && make token
# or: go run . user token -u admin -d 'api-work'
```

### Environment

```bash
export BASE_URL="https://127.0.0.1:4030"
export TOKEN="…"
```

### Base curl pattern

```bash
curl -sk -X METHOD "$BASE_URL/api/v1/ENDPOINT" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ ... }'
```

- `-k` is required — the collector serves a self-signed cert.
- Response JSON is kebab-case (`device-id`, `net-os`, `is-active`, `is-key`).
- Pagination query params use underscores: `?page_number=1&item_numbers=25`.

## Three things that break callers

### 1. JSON-string-encoded mapping fields

Protocol array/object fields are stored as JSON strings **inside** the JSON body, so they must
be double-encoded:

```json
{
  "gnmi-paths": "[\"openconfig-interfaces:interfaces/interface/state\"]",
  "field-mappings": "{\"name\": \"interface-name\", \"mtu\": \"mtu\"}",
  "field-transforms": "{\"admin-status\": [\"to-lower\"]}",
  "value-transforms": "{\"oper-status\": {\"1\": \"up\", \"2\": \"down\"}}",
  "ignore-values": "{\"interface-name\": [\"Null0\"]}"
}
```

Applies to: `gnmi-paths`, `snmp-walk-oids`, `snmp-scalar-oids`, `snmp-lookups`,
`netconf-filter-paths`, `cli-commands`, `cli-discovery-params`, `field-mappings`,
`field-transforms`, `value-transforms`, `ignore-values`, `version-constraints`.

### 2. A model is a family; fields and mappings hang off a version

Two tiers: a **definition** (family — the named model) owns one or more **versions**, and each
version owns its own fields and mappings.

- `GET /api/v1/models` lists **families**, each with a `version-id` — the version a caller
  should address (latest active by SemVer, falling back to newest overall; may be absent if
  every version is a draft).
- `GET/PUT/DELETE /api/v1/models/{id}`, `/export`, `/fields`, `/mappings`, `/test` all take a
  **version id**. Passing a family id addresses the wrong row or 404s.
- `POST /api/v1/models/{id}/new-version` forks a new version from an existing one.
- Subscriptions FK the family: `data-model-definition-id` is required,
  `data-model-version-id` is optional — omit it to track the latest active version.

### 3. The mapping key is derived, not declared

`ProtocolMapping` has **no `key-field`**. The record key is the source mapped onto the model
field flagged `is-key`:

```bash
# the field carrying the identity
curl … -X POST "$BASE_URL/api/v1/models/$VERSION_ID/fields" \
  -d '{"name":"interface-name","field-type":"string","is-key":true}'

# the mapping: "name" (from the device) feeds interface-name, so "name" is the key source
curl … -X POST "$BASE_URL/api/v1/models/$VERSION_ID/mappings" \
  -d '{"protocol":"gnmi","netos":"ios-xr",
       "gnmi-paths":"[\"openconfig-interfaces:interfaces/interface/state\"]",
       "field-mappings":"{\"name\":\"interface-name\",\"mtu\":\"mtu\"}"}'
```

Rules the API enforces (all **422**, same rules as the web form):

| Situation | Result |
|---|---|
| No source mapped onto the key field | `Map a source onto "X", the model's key field` |
| Two sources mapped onto it | `Several sources map onto "X"…` |
| Model has no `is-key` field at all | `The model has no key field: flag one field…` |
| A legacy `"key-field"` in the body | ignored — it is not a fallback |

Related invariants:

- **The first field added to a version is auto-promoted to key** if none is flagged.
- At most one key per version, enforced by a partial unique index — a second key is an error,
  even from direct SQL.
- `PUT` a field with `"is-key": false` **on the current key field** → **400**, "flag another
  field as the key instead of clearing this one". Flag the replacement instead; a partial PUT
  that omits `is-key` keeps it.
- `POST /fields/reorder` must list **every** field of the version exactly once — a partial
  list, a duplicate, or a foreign id is **400**.
- Import accepts a pre-1.1.3 export: a top-level `"key-field"` on a mapping is resolved
  through its field mappings and flags the target field. First flagged field wins.

## Endpoint quick reference

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/v1/ping` | Liveness |
| GET | `/api/v1/health` | System collection health |
| GET | `/api/v1/health/devices` · `/devices/{deviceId}` | Per-device health |
| GET | `/api/v1/health/subscriptions/{subscriptionId}` | Per-subscription health |
| GET | `/api/v1/health/history` | Health history |
| GET,POST | `/api/v1/devices` | List / create device |
| GET,PUT,DELETE | `/api/v1/devices/{id}` | Device detail (nested protocols) / update / delete |
| GET,POST | `/api/v1/protocols` | List / create protocol for a device |
| GET,PUT,DELETE | `/api/v1/protocols/{id}` | Protocol detail / update (incl. `enabled`) / delete |
| POST | `/api/v1/protocols/test-path` | Quick path test (gNMI/SNMP/NETCONF) |
| POST | `/api/v1/protocols/test-cli` | Quick CLI command test |
| GET,POST | `/api/v1/models` | List families (`version-id` each) / create |
| GET,PUT,DELETE | `/api/v1/models/{id}` | Version detail (fields + mappings) / update / delete |
| POST | `/api/v1/models/{id}/new-version` | Fork a new version |
| GET | `/api/v1/models/{id}/export` | Export family as JSON |
| POST | `/api/v1/models/{id}/import` | Import into a family |
| POST | `/api/v1/models/{id}/fields` | Add field (201) |
| PUT,DELETE | `/api/v1/models/{id}/fields/{fieldId}` | Update / delete field |
| POST | `/api/v1/models/{id}/fields/reorder` | Reorder — full permutation, body `[3,1,2]` |
| POST | `/api/v1/models/{id}/mappings` | Add mapping (201) |
| PUT,DELETE | `/api/v1/models/{id}/mappings/{mappingId}` | Update / delete mapping |
| POST | `/api/v1/models/{id}/test` | Live collection test |
| POST | `/api/v1/models/{id}/test/compare` | Cross-vendor comparison |
| GET,POST | `/api/v1/subscriptions` | List / create (starts collection) |
| GET,PUT,DELETE | `/api/v1/subscriptions/{id}` | Subscription detail / update / delete |
| GET | `/api/v1/subscription/snapshots/{deviceId}` | All snapshots for a device |
| GET | `/api/v1/subscription/snapshots/{deviceId}/{modelName}` | One model (`?refresh=true`) |
| GET | `/api/v1/subscription/snapshots/{deviceId}/definition/{definitionId}` | By family id |
| GET | `/api/v1/capture/{deviceId}/definition/{definitionId}` | Captured rows by family |
| GET | `/api/v1/capture/{deviceId}/{modelName}/{versionId}` | Captured rows by version |
| GET,POST | `/api/v1/transforms` | List / create Starlark transform |
| GET,PUT,DELETE | `/api/v1/transforms/{id}` | Transform detail / update / delete |
| POST | `/api/v1/transforms/ai-generate` | AI-generate a transform |
| GET | `/api/v1/outputs` | List backends |
| GET,PUT,DELETE | `/api/v1/outputs/{backend}` | Get / configure+enable / delete backend |
| GET | `/api/v1/outputs/metrics` | Per-backend metrics |
| POST | `/api/v1/outputs/test-output` | Inject test data |
| POST | `/api/v1/outputs/{backend}/detect` | Probe connectivity / config |
| POST | `/api/v1/pipelines/validate` | End-to-end pipeline validation |
| GET,POST | `/api/v1/vendor-profiles` | List / create NetOS profile |
| GET,PUT,DELETE | `/api/v1/vendor-profiles/{id}` | Profile detail / update / delete |
| GET | `/api/v1/vendor-profiles/export` · `/{id}/export` | Export all / one |
| POST | `/api/v1/vendor-profiles/import` | Import profiles |
| POST | `/api/v1/vendor-profiles/{id}/toggle` · `/reset` | Enable-disable / restore builtin |
| GET | `/api/v1/vendor-profiles/{id}/revisions` · `/{revId}` · `/{revId}/diff` | Audit trail |
| POST | `/api/v1/vendor-profiles/{id}/revisions/{revId}/restore` | Roll back |
| POST | `/api/v1/config/export` | Export collector config |
| POST | `/api/v1/config/import` · `/import/apply` | Preview / apply a config import |
| GET,PUT | `/api/v1/config/git-settings` | Git-sync settings |
| DELETE | `/api/v1/ai-settings` | Clear AI provider settings |
| GET | `/api/v1/yang/catalogs` | YANG catalogs (embedded + device) |
| GET | `/api/v1/yang/catalogs/{netos}/{ver}/modules` | Modules in a catalog |
| GET | `…/modules/{mod}/tree` · `/tree/children` · `/tree/search` · `/tree/leaves` | Tree navigation |
| GET | `…/modules/{mod}/deviations` | Module deviations |
| GET | `/api/v1/snmp/mibs/modules` · `/{module}/tree` · `/{module}/imports` | MIB modules |
| GET | `/api/v1/snmp/mibs/oids` · `/oids/children` · `/oids/columns` | OID detail / children / table columns |
| GET | `/api/v1/snmp/mibs/search` · `/profiles` | Search / walk profiles |
| POST | `/api/v1/snmp/mibs/walk` | On-demand device walk |

**Not in the REST API** (web UI only): vendor MIB repo import
(`POST /snmp/mibs/pull-repo`, `/snmp/mibs/import-repo`), the data explorer / row-matrix
viewer, the AI mapping wizard, and user/group management.

## End-to-end overview

**Create model → add fields (one `is-key`) → add mapping (key source in `field-mappings`) →
test → subscribe → snapshot.**

A version is collection-ready ("ready") when it has ≥1 field, ≥1 mapping, every mapping
sources the key field, and every mapping has ≥1 path/OID/command. Missing key source or
paths degrades it to "partial".

See `references/workflows.md` for full curl walkthroughs.

## HTTP status codes

| Code | Meaning |
|---|---|
| 200 | GET, PUT, test, export |
| 201 | create |
| 204 | delete |
| 400 | malformed JSON, bad path param, incomplete reorder, clearing the key field |
| 401 | missing or invalid token |
| 404 | not found — also returned when a child's parent id in the path doesn't match (IDOR guard) |
| 422 | validation failed — body carries `field-errors` / `non-field-errors` |

Validation failures are **422**, not 400. Read `field-errors` to know which field was rejected.

## Subagent Delegation

Delegate **data discovery** (YANG trees, SNMP MIBs, CLI probing) and **end-to-end model
creation** to subagents; keep decisions and user interaction in the main conversation.

### When to delegate

| Task | Delegate? | Reason |
|------|-----------|--------|
| Browse YANG tree / search paths | **Yes** | Many calls, large tree responses |
| Search SNMP MIBs / walk device | **Yes** | Large OID trees, column listings |
| Test CLI commands on a device | **Yes** | Raw CLI output is verbose |
| Build a complete model end-to-end | **Yes** | Discovery + multi-step creation |
| Single CRUD call | No | Quick, small response |
| Ask the user to choose | No | Must stay in the main conversation |

### Required in every subagent prompt

1. **Reference files** — paths relative to this skill directory, e.g.
   `references/browser-apis.md` (discovery), `references/models-api.md` (model/field/mapping),
   `references/testing-snapshots-api.md` (testing), `references/gottp-templates.md` (CLI).
2. **Environment**: `$BASE_URL` and `$TOKEN` are already exported; all curl uses `-sk`.
3. **JSON conventions**: mapping array/object fields must be JSON-string-encoded.
4. **The derived-key rule**: exactly one field flagged `is-key`, and `field-mappings` must map
   exactly one source onto it.
5. **Version id, not family id** for anything under `/models/{id}/…`.
6. **Device context** — id, netos, software version, configured protocols.
7. **Required output format** for the final summary.

### Pattern 1 — YANG path discovery

```
Read references/browser-apis.md
[environment + JSON conventions + derived-key rule]

Goal: find YANG paths and leaves for "{concept}" on {netos} {version}. Device ID: {id}.

Steps:
1. List YANG catalogs; pick the one for {netos}/{version}
2. List modules; identify the relevant one(s)
3. Search the module tree for "{keywords}"
4. Get leaves under the most relevant container path(s)
5. If a device catalog exists, check module deviations

Return ONLY:
- Module / catalog
- Container path(s)
- Leaves: name | YANG path | type | description
- Recommended gnmi-paths
- Recommended field-mappings {source: field}
- Which source should be the key, and why
- Deviations (if any)
```

### Pattern 2 — SNMP OID discovery

```
Read references/browser-apis.md
[environment + JSON conventions + derived-key rule]

Goal: find SNMP OIDs for "{concept}" on {netos}. Device ID: {id}.

Steps:
1. Search the MIB tree for "{keywords}"
2. Get table columns for relevant tables
3. Check walk profiles for {netos}
4. Optionally walk the device to confirm the OIDs return data

Return ONLY:
- MIB module(s), table OID + name
- Columns: name | OID | syntax | description
- Walk profile match
- Recommended walk OIDs
- Recommended field-mappings {source: field} + which is the key source
- Recommended transforms {field: [names]}
```

### Pattern 3 — CLI command discovery

```
Read references/testing-snapshots-api.md
Read references/gottp-templates.md
[environment + JSON conventions + derived-key rule]

Goal: test CLI commands for "{concept}" on device {id} ({netos}) and design a TTP template.

Steps:
1. Run test-cli with candidate show commands
2. Identify the output structure (key-value | table | hierarchical)
3. Write a TTP template extracting the fields
4. Identify the per-row identity variable — it MUST be captured, or every row is dropped

Return ONLY:
- Working command(s)
- Output structure
- TTP template
- Variables: name | suggested field-type | description
- Which variable is the key source
- Recommended field-mappings {ttp-var: field}
```

### Pattern 4 — end-to-end model creation

```
Read references/browser-apis.md
Read references/models-api.md
Read references/workflows.md
[environment + JSON conventions + derived-key rule]

Goal: create a complete {protocol} model for "{concept}" targeting {netos}.
Test device ID: {id}.

Steps:
1. DISCOVER (pattern above)
2. CREATE MODEL: POST /api/v1/models — note the returned family id AND version id
3. ADD FIELDS: POST /models/{versionId}/fields — flag the identity field is-key:true
4. ADD MAPPING: POST /models/{versionId}/mappings — field-mappings must hit the key field
5. TEST: POST /models/{versionId}/test with device-id + mapping-id

Return ONLY:
- Model: {name} (family {id}, version {versionId})
- Fields: {count} — list with types, and which is the key
- Mapping: {protocol}/{netos} (id {mid})
- Test result: rows parsed, keys non-empty?, issues
- Suggestions / warnings
```

**Multiple protocols:** the main agent creates the model and fields first (shared by every
mapping), then launches one subagent per mapping with the version id and the field list —
including which field is the key.

### Parallel vs sequential

Parallel: independent discovery (YANG *and* SNMP for one concept), several mappings on an
existing model, unrelated concepts. Sequential: when discovery determines the field list, or
the user wants to iterate on the design first.

### Rules

1. **Confirm before launching** when the protocol or field set is ambiguous.
2. Subagents use **curl against the REST API**, not Go code.
3. Never let a subagent make a design decision the user should make — report the options.
4. Summarize for the user; never paste raw subagent output.

## Reference files

| File | When to read |
|------|--------------|
| `references/models-api.md` | Model/field/mapping CRUD, per-protocol payloads, field types + formats, built-in transforms, Starlark transforms |
| `references/testing-snapshots-api.md` | Live test, compare, path/CLI tests, snapshots, devices, protocols, subscriptions |
| `references/workflows.md` | End-to-end curl workflows per protocol, export/import, multi-protocol, full stack |
| `references/gottp-templates.md` | GoTTP/TTP syntax for CLI mappings — decision tree, groups, examples, how the key source is resolved |
| `references/outputs-api.md` | Output backends: config schema per backend, cleartext-HTTP guard, metrics, test injection, detect |
| `references/autonomous-pipelines.md` | Zero-to-dashboard: Prometheus+Grafana, InfluxDB+Grafana, quick verification |
| `references/grafana-integration.md` | Grafana Docker stacks, API, data sources, panel templates, field-to-panel mapping |
| `references/browser-apis.md` | YANG tree browser and SNMP MIB browser APIs |
