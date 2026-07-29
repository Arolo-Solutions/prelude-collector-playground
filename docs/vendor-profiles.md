# Vendor profiles

A **vendor profile** is a per-NetOS definition that tells the collector how to talk to a
family of devices. Each [`../vendors/<netos>/profile.json`](../vendors) is an
import-ready profile document (`schema-version` 1). One profile controls:

- **the NetOS dropdown** shown when adding a device (enabled profiles only),
- **auto-detection** — patterns matched against a gNMI Capabilities response, an SNMP
  sysDescr, or CLI `show version` output to identify the NetOS,
- **per-protocol defaults** the collection engine applies at runtime: gNMI path-format &
  encoding, NETCONF port, SNMP version regex, and CLI prompt/error patterns, paging-disable,
  clean-shell setup, blocked command prefixes, and interactive auto-responses.

The collector already ships these seven as **builtins** (`ios-xr`, `ios-xe`, `nxos`, `junos`,
`eos`, `srlinux`, `sros`); they're included here as editable references. `vrp` (Huawei) is a
**custom** profile you can import to add a new NetOS the collector doesn't ship.

## Files

| File | NetOS | Vendor | Notes |
|------|-------|--------|-------|
| [`ios-xr.json`](../vendors/ios-xr/profile.json) | ios-xr | cisco | gNMI `module-prefix` / `json_ietf`; embedded YANG `vendor/cisco/xr` |
| [`ios-xe.json`](../vendors/ios-xe/profile.json) | ios-xe | cisco | gNMI `module-prefix` / `json_ietf`, origin `rfc7951` |
| [`nxos.json`](../vendors/nxos/profile.json) | nxos | cisco | gNMI `bare-slash` / `json`, origin `device` |
| [`junos.json`](../vendors/junos/profile.json) | junos | juniper | paging `set cli screen-length 0`; `{master}`-style prompts |
| [`eos.json`](../vendors/eos/profile.json) | eos | arista | gNMI `bare-slash` / `json`, `split-prefix` notifications |
| [`srlinux.json`](../vendors/srlinux/profile.json) | srlinux | nokia | gNMI `module-prefix` / `json_ietf`; CLI engine set to `basic` |
| [`sros.json`](../vendors/sros/profile.json) | sros | nokia | `TiMOS` detection; `A:`/`B:` prompts; severity `MINOR:`/`MAJOR:` errors |
| [`vrp.json`](../vendors/vrp/profile.json) | vrp | huawei | **custom** — Huawei `<…>`/`[…]` prompts, `screen-length 0 temporary`, `blocked-prefixes`, password-change `auto-response` |

## Importing

**Prelude MCP** — pass the file contents as `import_data` (one document, or a JSON array of
many). `overwrite=true` replaces an existing profile with the same `netos`; otherwise it's skipped.

```
collector_vendor_profiles  action=import  import_data=<contents of vendors/vrp/profile.json>
collector_vendor_profiles  action=import  overwrite=true  import_data=<contents of a file>
```

**REST** — POST the file as the body (token from `make token`):

```bash
curl -ks -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  --data-binary @vendors/vrp/profile.json \
  https://127.0.0.1:4030/api/v1/vendor-profiles/import          # add ?overwrite=true to replace
```

**Web UI** — **Settings → Vendor Profiles → Import**.

Import returns `{created, updated, skipped}`. Creating, updating, toggling, or resetting a
profile reloads the in-memory registry immediately — no collector restart.

## Profile fields (schema-version 1)

Required: `schema-version` (1), `netos` (slug `^[a-z0-9][a-z0-9-]{0,49}$`), `display-name`.
Optional: `vendor`, and the nested blocks below.

| Block | Key fields | Purpose |
|-------|-----------|---------|
| `detection` | `gnmi-capability-modules`, `snmp-sysdescr-patterns`, `cli-show-version-patterns` | substrings used to auto-detect the NetOS |
| `gnmi` | `path-format` (`module-prefix`\|`bare-slash`\|`bare`), `default-encoding` (`json`\|`json_ietf`\|`proto`\|`ascii`), `default-origin`, `notification-style` (`standard`\|`split-prefix`) | gNMI subscribe/get defaults |
| `netconf` | `default-port` (1–65535) | NETCONF SSH port |
| `snmp` | `profile-tags`, `version-regex` (1st capture = version) | SNMP classification + version parse from sysDescr |
| `cli` | `prompt-hints`, `paging-disable`, `prompt-patterns`, `error-patterns`, `clean-shell`, `blocked-prefixes`, `auto-responses[{pattern,response}]` | SSH/CLI session driver (Go regexes) |
| `yang` | `embedded-subpath`, `repo-slugs` | where to resolve YANG models |
| `playground` | `url` (http/https), `examples` | optional link back to examples like these |

> CLI `prompt-patterns`, `error-patterns`, `auto-responses[].pattern`, and `snmp.version-regex`
> are compiled as **Go regexes** at import time — an invalid pattern is rejected with a 400.
