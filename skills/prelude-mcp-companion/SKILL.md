---
name: prelude-mcp-companion
description: >
  Knowledge companion for the Prelude MCP server (prelude-mcp). Provides workflow patterns,
  JSON conventions, GoTTP template syntax, transform functions, Grafana pipeline setup, and
  subagent delegation guidance for working with Prelude network management tools.
  Covers all four components: Collector, OneBoard, Gateway, and Topology Engine (TE).
  Use when: working with prelude-mcp MCP tools (collector_*, oneboard_*, gateway_*, te_*),
  creating data models, building collection mappings, setting up output pipelines,
  managing vendor profiles, browsing YANG/SNMP trees, designing Grafana dashboards,
  or any Prelude network management task.
  Triggers on: "prelude", "collector", "oneboard", "gateway", "topology", "MCP server",
  "data model", "collection", "YANG", "SNMP MIB", "gNMI", "NETCONF", "GoTTP", "TTP template",
  "output backend", "Grafana dashboard", "pipeline", "network telemetry",
  "vendor profile", "NetOS profile".
---

# Prelude MCP Companion

## MCP Server Setup

The Prelude MCP server exposes network management tools via MCP protocol (Streamable HTTP or stdio).

**Check if running:** Call `collector_ping` (or `oneboard_ping`, `gateway_ping`, `te_ping`). If tools are unavailable, the server needs to be started.

**Start locally (Docker):**
```bash
docker run -d --name prelude-mcp -p 4040:4040 \
  -v /path/to/config.json:/etc/prelude-mcp/config.json \
  prelude-mcp --config /etc/prelude-mcp/config.json --port 4040
```

**Config format** (`config.json`):
```json
{
  "collector": {"url": "https://host.docker.internal:4030", "enabled": true},
  "oneboard": {"url": "https://host.docker.internal:4000", "enabled": false},
  "gateway": {"url": "https://host.docker.internal:4020", "enabled": false},
  "te": {"url": "https://host.docker.internal:4040", "enabled": false}
}
```

Env overrides: `PRELUDE_COLLECTOR_URL`, `PRELUDE_COLLECTOR_ENABLED`, etc.

**Registry (future):** `https://registry.arolo-solutions.com/` — when available for customer deployments.

**Verify:** `curl -s http://localhost:4040/status` — shows per-component status.

---

## Available MCP Tools (36 total)

### Collector (19 tools)
| Tool | Purpose |
|------|---------|
| `collector_ping` | Health check |
| `collector_devices` | CRUD devices (list, get, create, update, delete) |
| `collector_models` | CRUD data models (list, get, create, update, delete, export, import) |
| `collector_fields` | Manage model fields (add, update, delete, reorder) |
| `collector_mappings` | Protocol mappings (add, update, delete) — gNMI, SNMP, NETCONF, CLI |
| `collector_protocols` | Device protocols (list, get, create, update, delete) |
| `collector_subscriptions` | Collection subscriptions (list, get, create, update, delete) |
| `collector_transforms` | Starlark transforms (list, get, create, update, delete, ai-generate) |
| `collector_outputs` | Output backends (list, get, configure, delete, metrics, test, detect) |
| `collector_vendor_profiles` | Vendor profiles per NetOS (list, get, create, update, delete, export, export-all, import, toggle, reset, revisions, revision, diff, restore) |
| `collector_health` | Collection health (system, devices, device, subscription, history) |
| `collector_snapshots` | Collected data (list, get with optional refresh) |
| `collector_validate_pipeline` | End-to-end pipeline validation |
| `collector_test_model` | Live collection test against a device |
| `collector_test_path` | Quick path test (gNMI/SNMP/NETCONF) |
| `collector_test_cli` | Run show commands on a device |
| `collector_test_compare` | Compare collection across mappings/devices for cross-vendor consistency |
| `collector_yang_browser` | YANG tree (catalogs, modules, tree, search, leaves, deviations) |
| `collector_snmp_browser` | SNMP MIB tree (modules, tree, OIDs, columns, search, profiles, walk) |

### OneBoard (10 tools)
| Tool | Purpose |
|------|---------|
| `oneboard_ping` | Health check |
| `oneboard_devices` | Inventory devices CRUD |
| `oneboard_credentials` | Credential management CRUD |
| `oneboard_customers` | Customer management (list, create) |
| `oneboard_connectors_gateway` | Gateway connector CRUD |
| `oneboard_connectors_nso` | NSO connector CRUD |
| `oneboard_connectors_te` | TE connector CRUD |
| `oneboard_id_pools` | ID pool allocation (allocate, request, release) |
| `oneboard_subnet_pools` | Subnet pool allocation |
| `oneboard_services_log` | Services log |

### Gateway (3 tools)
| Tool | Purpose |
|------|---------|
| `gateway_ping` | Health check |
| `gateway_device_ping` | ICMP ping a device through Gateway |
| `gateway_ssh` | SSH commands (command, session_start, session_command, session_end) |

### Topology Engine (4 tools)
| Tool | Purpose |
|------|---------|
| `te_ping` | Health check |
| `te_topology` | Live topology (list_domains, get_domain, stats) |
| `te_bgp_peers` | BGP peer CRUD |
| `te_databuses` | Data bus CRUD |

---

## Core Workflow: Device → Model → Test → Collect

Standard sequence for setting up network telemetry collection:

1. **List/create device** — `collector_devices` (action: list/create)
2. **Add protocol** — `collector_protocols` (action: create) with type, port, credentials
3. **Discover paths** — `collector_yang_browser` or `collector_snmp_browser` or `collector_test_cli`
4. **Create model** — `collector_models` (action: create) with name, description
5. **Add fields** — `collector_fields` (action: add) — needs at least 1 field, at least one flagged `is_key` (a second or third adds a composite-key part instead of replacing it)
6. **Add mapping** — `collector_mappings` (action: add) — needs paths/OIDs + a `field_mappings` entry targeting each key field
7. **Test** — `collector_test_model` with device_id and mapping_id
8. **Subscribe** — `collector_subscriptions` (action: create) — starts live collection
9. **Verify** — `collector_snapshots` (action: get), `collector_outputs` (action: metrics), or `collector_health` (action: subscription) to check collection health

A model is "collection-ready" when it has: at least 1 field with `is_key` set + at least 1 mapping whose `field_mappings` maps exactly one source onto each key field, plus protocol paths.

**The key is derived, not declared** (collector 1.1.3+). `collector_mappings` has no `key_field`
parameter: the collector reads the record key from the source(s) mapped onto the model's `is_key`
field(s). One key field is the common case; two or more form a composite key (soft cap 4), joined
into one string sorted by field name. A mapping that leaves any key field unmapped — or maps two
sources onto the same key field — is rejected. Empty `records` from `collector_test_model` usually
means a key source name doesn't match what the device returns.

### Model IDs: family vs version

Models are a two-tier structure: a **family** (the named model) owns one or more **versions**,
and fields and mappings belong to a version. The two tools disagree on which id they take:

- `collector_models action=list` is keyed by family, and prints both — follow the
  **`Version ID`** line, not the family id.
- `get`, `update`, `delete`, `export`, `collector_fields`, and `collector_mappings` all take
  that version id as `model_id`.

`Version ID` resolves to the latest active version by SemVer, falling back to the newest
overall. A family whose versions are all still drafts may print no `Version ID` at all.
Passing a family id where a version id is expected addresses the wrong row or 404s.

### Choosing the key source

The key identifies each row in collected data (one row per interface, per BGP peer, …).
Discover it from real device data before building the model:

1. **Run `collector_test_path`** (or `collector_test_cli`) — see the raw field names the device
   actually returns.
2. **Flag the model field(s)** that hold that identity with `is_key` via `collector_fields`. Most
   models need only one; flag a second when no single value is unique on its own (e.g. a BGP
   neighbor identified by address *and* VRF).
3. **Map the raw source onto each one** in the mapping's `field_mappings` — those entries are the
   key sources. Exactly one per key field, or the save is rejected.

| Model | Key field(s) | Typical source |
|-------|--------------|----------------|
| Interfaces | `name` | `/interfaces/interface/state` → `name` |
| BGP neighbors | `neighbor-address` | `/bgp/neighbors/neighbor/state` → `neighbor-address` |
| BGP neighbors (multi-VRF) | `neighbor-address`, `vrf-name` | address from `/state`; VRF from the `network-instance[name=…]` path predicate — path-qualified source `/network-instance.name` |
| ISIS adjacencies | `system-id` | `/isis/…/adjacencies/adjacency/state` → `system-id` |
| Subinterfaces | `name`, `index` | both often exist only as path predicates: `interface[name=…]/subinterfaces/subinterface[index=…]` |
| Routes | `prefix` | varies by protocol |
| System info | `hostname` | `/system/state` → `hostname` |

!!! tip "Nested lists that reuse a predicate name"
    A path like `network-instance[name=VRF]/protocols/protocol[name=core]` has **two** `name`
    predicates at different levels. The collector resolves each qualified as
    `<listElement>.<predicateName>` (`network-instance.name` vs `protocol.name`), so the outer
    list's predicate can be a key part even though a deeper list reuses the same leaf name.

The value normally comes from the **data payload**, and the parser matches the source name
directly. When a gNMI list key appears only in the path predicate (`[name=eth0]`) and never as
a leaf — SR Linux does this — the parser backfills it from the path, so map the bare leaf name
and it resolves.

### Multivendor consistency (core mission)

**The collector's value is homogeneous parsed data across vendors.** Downstream consumers
(Grafana, NATS, APIs) must see identical field names, value sets, and types no matter which
vendor produced the row.

After adding mappings for several vendors, validate before subscribing:

1. **Compare** — `collector_test_compare` with `model_id` plus `tests`, a JSON array of
   `{"mapping-id": N, "device-id": N}` pairs (minimum 2). Returns per-vendor parsed rows and
   field lists for side-by-side reading.
2. **Resolve divergence** — case mismatch → `lowercase`/`uppercase` transform; vendor enum
   (`im-state-up` vs `up`) → value transforms; missing field → check the source path and the
   field mapping.
3. **Re-compare** until the fields agree.
4. **Subscribe** — only once they do.

| Field | IOS-XR native | OpenConfig | SR Linux | Normalized |
|-------|---------------|------------|----------|------------|
| admin-status | `im-state-up` | `UP` | `enable` | `up` |
| oper-status | `im-state-up` | `UP` | `up` | `up` |
| speed | kbps | `SPEED_10GB` | bps | use transforms |

---

## Critical Conventions

Read `references/conventions.md` for:
- **JSON double-encoding** for mapping fields (gnmi_paths, field_mappings, etc.) — the #1 gotcha
- Valid field types and formats
- All 40+ built-in transform functions
- User-defined Starlark transforms
- Output backend config schemas (NATS, Prometheus, InfluxDB, Kafka, Webhook, File, TimescaleDB)
- Pipeline validation stages
- Testing timeouts per protocol

Two output gotchas worth knowing up front:

- **Cleartext HTTP is refused.** An `http://` URL to a non-loopback host needs
  `"insecure-http": true` in the config, or the save is rejected and the test-connection
  reports a failed `transport` check. Loopback (`127.0.0.1`, `localhost`) is exempt. Prefer
  `https://`.
- **InfluxDB 1.x and 2.x take different configs.** `"version": "v1"` needs `database`
  (plus `username`/`password`); v2 — the default when `version` is blank — needs `token`,
  `org`, and `bucket`.

---

## Vendor Profiles

`collector_vendor_profiles` manages per-NetOS definitions (`ios-xr`, `junos`, `eos`, …)
that populate the device NetOS dropdown, drive auto-detection, and supply protocol
defaults (gNMI path-format/encoding, NETCONF port, SNMP version regex, CLI
prompt/error patterns). Builtins ship with the collector and can't be deleted (toggle
off or reset instead); custom/imported profiles are fully editable. Every write is
audited via revisions, and the registry reloads immediately (no restart).

Read `references/vendor-profiles.md` for the full field reference (what each payload
parameter represents) and the CRUD / revision recipes.

---

## Reference Files

| File | When to read |
|------|-------------|
| [conventions.md](references/conventions.md) | Always — JSON encoding, transforms, field types, output schemas |
| [gottp-templates.md](references/gottp-templates.md) | Building CLI mappings — TTP template syntax, patterns, examples |
| [grafana-pipelines.md](references/grafana-pipelines.md) | Setting up monitoring — Docker Compose, Grafana API, dashboard auto-generation |
| [vendor-profiles.md](references/vendor-profiles.md) | Managing per-NetOS vendor profiles — fields, CRUD actions, revisions |

---

## Subagent Delegation

Delegate heavy work to subagents to keep the main conversation clean.

### When to Delegate

| Task | Delegate? | Why |
|------|-----------|-----|
| Browse YANG tree / search paths | **Yes** | Multiple API calls, large responses |
| Search SNMP MIBs / walk device | **Yes** | Large OID trees, verbose output |
| Test CLI commands on a device | **Yes** | Raw CLI output is verbose |
| Build a complete model end-to-end | **Yes** | Discovery + multi-step creation |
| Single CRUD call | No | Quick, small response |
| Confirm design with user | No | Must stay in main conversation |

### Subagent Prompt Template

Every subagent prompt MUST include:

1. **Which reference to read** — tell it to `Read /path/to/references/conventions.md` etc.
2. **Device context** — device ID, netos, software version, configured protocols
3. **Required output format** — what the subagent must return as summary

**Example — YANG path discovery:**
```
Read references/conventions.md from the prelude-mcp-companion skill.

Goal: Find YANG paths for "{concept}" on {netos} {version}. Device ID: {device-id}.

Steps:
1. Call collector_yang_browser (action: catalogs) to find the right catalog
2. Call collector_yang_browser (action: modules) to list modules
3. Call collector_yang_browser (action: search) for "{keywords}"
4. Call collector_yang_browser (action: leaves) under the best container path

Return: module name, container paths, available leaves (name | path | type), recommended gnmi_paths and field_mappings.
```

**Example — end-to-end model creation:**
```
Read references/conventions.md from the prelude-mcp-companion skill.

Goal: Create a {protocol} model for "{concept}" on {netos}. Device ID: {device-id}.

Steps:
1. DISCOVER: [use YANG/SNMP/CLI discovery]
2. CREATE: collector_models (action: create)
3. ADD FIELDS: collector_fields (action: add) for each discovered field
4. ADD MAPPING: collector_mappings (action: add) with paths and field_mappings
5. TEST: collector_test_model with device_id and mapping_id

Return: model name+ID, fields created, mapping ID, test result (pass/fail + row count).
```

### Parallel vs. Sequential

**Parallel:** YANG + SNMP discovery for same concept, multiple mappings for existing model, unrelated concepts.

**Sequential:** Discovery determines fields (discover first, then create). User wants to choose between options.

### Rules

1. **Never let a subagent make design decisions** the user should make — if discovery reveals multiple options (openconfig vs native YANG), report both and ask.
2. **Subagents use MCP tools** — not curl.
3. **After completion**, summarize results concisely for the user.
