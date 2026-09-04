# prelude-collector-playground

Import-ready **data models**, **transforms** and **vendor profiles** for
[Prelude Collector](https://portal.arolo-solutions.com/docs/collector/latest/) — a multi-protocol
network telemetry collector (gNMI, SNMP, CLI/SSH, NETCONF).

Use these as copy-paste starting points. Each model is an **import-ready** export covering a real
collection use case; import one, point it at a device, and you have normalized telemetry flowing in
minutes.

Verified against **Prelude Collector v1.1.2**.

## Repo layout

```
vendors/<netos>/     Everything specific to one NetOS: profile.json, models/, and a README
shared/models/       Models that span several vendors
shared/transforms/   User-defined Starlark transforms ({name, description, code})
skills/              Claude agent skills — teach an agent the collector's API and conventions
docs/                Reference: model schema, transform catalog, vendor profiles, import paths
scripts/             Maintenance helpers (skill vendoring)
```

Content is organized **by NetOS** because that is the question you actually have — "what do I need
for my Cisco/Arista/Nokia box". Start at your vendor's directory; drop into `shared/` for the parts
that are vendor-independent.

## Quick start

```bash
# via the Prelude MCP
collector_models action=import import_data=<contents of vendors/ios-xr/models/oc-interfaces.json>

# via REST (token from `make token`)
curl -ks -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  --data-binary @vendors/ios-xr/models/oc-interfaces.json \
  https://127.0.0.1:4030/api/v1/models/0/import
```

Or in the Web UI: **Models → Import**. Full details (incl. transforms and vendor profiles) in
[docs/importing.md](docs/importing.md).

## Vendors

| NetOS | Vendor | Profile | Models | Verified on a device |
|-------|--------|---------|--------|----------------------|
| [`ios-xr`](vendors/ios-xr) | Cisco | builtin | 6 + shared | ✅ gNMI, CLI, SNMP |
| [`eos`](vendors/eos) | Arista | builtin | shared | ✅ gNMI |
| [`srlinux`](vendors/srlinux) | Nokia | builtin | shared | ✅ gNMI |
| [`ios-xe`](vendors/ios-xe) | Cisco | builtin | — | — |
| [`nxos`](vendors/nxos) | Cisco | builtin | — | — |
| [`junos`](vendors/junos) | Juniper | builtin | — | — |
| [`sros`](vendors/sros) | Nokia | builtin | — | — |
| [`vrp`](vendors/vrp) | Huawei | **custom** | — | — |

"builtin" means the collector already ships that profile — the copy here is for reading, diffing, or
importing a modified version. `vrp` is a **custom** add-on: importing it is how you get Huawei
support. Models are thin for most vendors today; the profile alone still gives the collector correct
path formats, prompt handling and version detection.

## Shared models

| File | Protocol | NetOS | What it demonstrates |
|------|----------|-------|----------------------|
| [`interface-state.json`](shared/models/interface-state.json) | gNMI | eos, srlinux, ios-xr | **Multivendor** — three mappings onto one model, showing how source keys and paths differ per vendor while the normalized output stays identical. Uses `field-transforms` (`lowercase`). |

## Shared transforms

| File | Does |
|------|------|
| [`bytes_per_sec_to_mbps.json`](shared/transforms/bytes_per_sec_to_mbps.json) | `return round(to_mbps(value * 8), 1)` — byte/sec → Mbps. |
| [`bool_to_up_down.json`](shared/transforms/bool_to_up_down.json) | `return "up" if value else "down"`. |
| [`dbm_from_tenths.json`](shared/transforms/dbm_from_tenths.json) | `return round(value / 10.0, 1)` — tenths-of-dBm → dBm. |

There are also **41 built-in transforms** that need no definition — reference them by name. Full
catalog and the Starlark rules (including the mandatory `return`) in
[docs/transforms.md](docs/transforms.md).

## Agent skills

Two [Claude agent skills](https://docs.claude.com/en/docs/claude-code/skills) that teach an agent how
to drive the collector. Copy either directory into `~/.claude/skills/`.

| Skill | Teaches |
|-------|---------|
| [`prelude-collector-api`](skills/prelude-collector-api) | The **REST API**: models, fields, mappings, live testing, snapshots, subscriptions, output backends, GoTTP templates, transforms, vendor profiles, Grafana pipelines, YANG/SNMP browsers. |
| [`prelude-mcp-companion`](skills/prelude-mcp-companion) | The **Prelude MCP** server: the workflow (device → model → mapping → test → subscribe), JSON conventions, built-in transforms, GoTTP syntax, and the multivendor-consistency rule — compare across vendors before you subscribe. |

These directories are **vendored copies**; their source of truth lives elsewhere and they are
refreshed with [`scripts/sync-skills.sh`](scripts/sync-skills.sh). Send skill fixes upstream rather
than editing the copy here.

## Docs

- [docs/data-models.md](docs/data-models.md) — the model / field / mapping JSON schema, field types & formats.
- [docs/transforms.md](docs/transforms.md) — built-in transform catalog + user-defined Starlark guide.
- [docs/vendor-profiles.md](docs/vendor-profiles.md) — per-NetOS vendor profiles: fields, detection, import paths.
- [docs/importing.md](docs/importing.md) — import via MCP, Web UI, or REST; verification commands.

## Reference lab

The verified examples were exported from and tested against a small reference lab:

| Device | NetOS | Protocols |
|--------|-------|-----------|
| `pe1` | ios-xr 24.2.2 | gNMI :57400, CLI :22, SNMP :161 |
| `r1`  | srlinux | gNMI :57400 (self-signed TLS) |
| `r2`  | eos | gNMI :6030 (plaintext) |

A mapping's `netos` must match the target device, and the device must have that protocol enabled,
before a subscription will collect data.
