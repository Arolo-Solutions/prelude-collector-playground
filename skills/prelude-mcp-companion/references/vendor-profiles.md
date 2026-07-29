# Vendor Profiles Reference

Vendor profiles are per-NetOS definitions managed through the
`collector_vendor_profiles` MCP tool. One profile exists per network OS
(`ios-xr`, `junos`, `eos`, `nxos`, `ios-xe`, `sros`, `srlinux`, plus any custom
ones you create).

## What a Vendor Profile Controls

A profile is the collector's per-vendor knowledge. A single enabled profile drives:

- **Device NetOS dropdown** — only enabled profiles appear as NetOS options when
  adding a device.
- **Auto-detection** — patterns that identify a device's NetOS from a gNMI
  Capabilities response, an SNMP sysDescr, or CLI `show version` output.
- **Protocol defaults** the collection engine applies at runtime:
  - gNMI path syntax (`path-format`), encoding, origin, notification style
  - NETCONF default port
  - SNMP software-version regex
  - CLI prompt/error regexes, paging-disable, clean-shell setup, interactive
    auto-responses, and extra blocked command prefixes

Writes reload the in-memory `vendor.Default` registry **immediately** — no collector
restart is needed for a created/updated/toggled/reset profile to take effect.

## `collector_vendor_profiles` — Action Reference

`action` is always required. Other params are required only for the actions noted.

| action       | required params              | what it does |
|--------------|------------------------------|--------------|
| `list`       | —                            | All profiles (builtins first, then alphabetical by netos) |
| `get`        | `profile_id`                 | Full profile including its payload document |
| `create`     | `payload` (+ opt `change_note`) | Create a custom profile |
| `update`     | `profile_id`, `payload` (+ opt `change_note`) | Replace the payload; records a revision |
| `delete`     | `profile_id`                 | Delete a custom/imported profile (builtins refuse with 409) |
| `export`     | `profile_id`                 | One profile's raw JSON document (re-importable) |
| `export-all` | —                            | Array of every profile's document |
| `import`     | `import_data` (+ opt `overwrite`) | Import one document or an array; `overwrite=true` replaces same-netos profiles, else skips them |
| `toggle`     | `profile_id`                 | Flip enabled ↔ disabled |
| `reset`      | `profile_id`                 | Revert a **builtin** to its shipped seed (409 if the profile is not a builtin) |
| `revisions`  | `profile_id`                 | Revision history, newest first |
| `revision`   | `profile_id`, `revision_id`  | One revision including its payload |
| `diff`       | `profile_id`, `revision_id`  | Unified line diff (revision vs current) |
| `restore`    | `profile_id`, `revision_id`  | Re-apply a historical revision (records a new revision) |

## Parameter Encoding

- **`payload`** and **`import_data`** are passed as **JSON-encoded strings** (the same
  double-encoding convention as mapping fields in conventions.md).
- **`change_note`** is a plain string (optional audit note stored on the revision).
- **`overwrite`** is a boolean (import only, default `false`).

```
action:      "create"
payload:     "{\"schema-version\":1,\"netos\":\"acme-os\",\"display-name\":\"Acme OS\",\"vendor\":\"acme\"}"
change_note: "initial Acme profile"
```

## Profile Payload Schema (schema-version 1)

The `payload` is a JSON document validated against schema-version 1. All field names
are **kebab-case**. Only `schema-version`, `netos`, and `display-name` are required;
every nested object and field is optional — omit what a vendor doesn't need.

### Top level

| Field | Type | Meaning |
|-------|------|---------|
| `schema-version` | const `1` | Payload schema version. Must be `1`. |
| `netos` | string, `^[a-z0-9][a-z0-9-]{0,49}$` | The NetOS slug — the registry lookup key and the value stored on devices (e.g. `ios-xr`). Lowercase, ≤50 chars. |
| `display-name` | string (1–255) | Human-readable name shown in the UI dropdown (e.g. `Cisco IOS-XR`). |
| `vendor` | string (≤100) | Vendor/organization name (e.g. `cisco`). Documentation/grouping only; optional. |

### `detection` — NetOS auto-detection

Patterns the engine matches to identify a device's NetOS automatically.

| Field | Type | Meaning |
|-------|------|---------|
| `gnmi-capability-modules` | string[] | Substrings matched against module names in a gNMI Capabilities response (e.g. `Cisco-IOS-XR`). |
| `snmp-sysdescr-patterns` | string[] | Case-sensitive substrings matched against SNMP sysDescr (e.g. `IOS XR`). |
| `cli-show-version-patterns` | string[] | Substrings matched against `show version` output. |

### `gnmi` — gNMI defaults

| Field | Type | Meaning |
|-------|------|---------|
| `path-format` | enum `module-prefix` \| `bare-slash` \| `bare` | How YANG paths are written. `module-prefix` = `/module:path`; `bare-slash` = `/path`; `bare` = vendor/alias form. |
| `default-encoding` | enum `json` \| `json_ietf` \| `proto` \| `ascii` | Subscribe/Get encoding preference. |
| `default-origin` | string | Optional gNMI `Path.Origin` (e.g. `openconfig`). Empty = unset. |
| `notification-style` | enum `standard` \| `split-prefix` | `standard` = full paths in each update; `split-prefix` = prefix update + leaf updates. |

### `netconf`

| Field | Type | Meaning |
|-------|------|---------|
| `default-port` | int 1–65535 | SSH port used for NETCONF sessions (typically `830`). |

### `snmp`

| Field | Type | Meaning |
|-------|------|---------|
| `profile-tags` | string[] | Free-form classification tags (e.g. `cisco-iosxr`). |
| `version-regex` | string (Go regex) | Extracts the software version from sysDescr; first capture group is the version. |

### `cli` — SSH/CLI session behavior

When `prompt-patterns` is set, the profile drives the SSH/CLI session instead of the
hardcoded ssh-client driver. All regexes use **Go regex syntax**.

| Field | Type | Meaning |
|-------|------|---------|
| `prompt-hints` | string[] | UI hints for the prompt characters (e.g. `["#", ">"]`). |
| `paging-disable` | string | Single command to disable output paging (e.g. `terminal length 0`). Fallback when `clean-shell` is unset. |
| `prompt-patterns` | string[] (Go regex) | Match the device command prompt in output. |
| `error-patterns` | string[] (Go regex) | Mark command output as a device error (e.g. `% ?Invalid input`). |
| `clean-shell` | string[] | Commands sent right after login (disable paging, widen terminal, etc.). |
| `auto-responses` | object[] `{pattern, response}` | Interactive prompt → automatic reply pairs (e.g. confirmation/license dialogs). Both fields required per item. |
| `blocked-prefixes` | string[] (`^[a-z][a-z0-9_-]{0,31}$`, ≤32) | Extra first-token commands blocked for this vendor (e.g. `install-active`). **Additive** — the global blocklist (`configure`, `commit`, `reload`, …) is always enforced. |

### `yang`

| Field | Type | Meaning |
|-------|------|---------|
| `embedded-subpath` | string (`^([a-z0-9_][a-z0-9._-]*(/…)*)?$`, ≤200) | Subdirectory joined under `storage/yang/openconfig` for embedded vendor models (e.g. `vendor/cisco/xr`). Traversal-guarded: no absolute paths, no `..`, no leading slash. |
| `repo-slugs` | string[] | External YANG repo identifiers for resolution (e.g. `openconfig`, `juniper`). |

### `playground`

| Field | Type | Meaning |
|-------|------|---------|
| `url` | string, `http(s)://` only (≤500) | Link to an external examples playground. Non-http(s) schemes (e.g. `javascript:`) are rejected. |
| `examples` | string[] | Example files/dirs to reference. |

## Server-Managed Fields (read-only)

`get`/`list` return these alongside the payload; they are **not** part of the payload
document and cannot be set via `create`/`update`:

| Field | Meaning |
|-------|---------|
| `id` | Numeric profile ID — use as `profile_id`. |
| `source` | `builtin` (ships with the collector) \| `imported` \| `custom`. |
| `builtin-hash` | SHA-256 of the shipped payload (builtins only); drift detection for `reset`. |
| `enabled` | Whether the profile is active in the registry (toggle with `toggle`). |
| `updated-by` | Who last modified it (audit). |
| `created-at` / `updated-at` | Timestamps. |

## Builtins, Custom Profiles & Revisions

- **Builtins cannot be deleted.** To stop using one, `toggle` it off. To undo edits,
  `reset` reverts it to the shipped seed.
- **Custom / imported** profiles can be deleted freely.
- Every `create`/`update`/`restore` writes an **audited revision** (`updated-by`,
  `change-note`, `saved-at`). Use `revisions` to list history, `revision` to read one,
  `diff` to compare a revision against the current payload, and `restore` to roll back
  (which itself records a new revision).

## Worked Examples

### Full create (real IOS-XR profile)

```
action: "create"
change_note: "add Cisco IOS-XR"
payload: (JSON-encode the document below)
```
```json
{
  "schema-version": 1,
  "netos": "ios-xr",
  "display-name": "Cisco IOS-XR",
  "vendor": "cisco",
  "detection": {
    "gnmi-capability-modules": ["Cisco-IOS-XR"],
    "snmp-sysdescr-patterns": ["IOS XR", "Cisco IOS XR Software"],
    "cli-show-version-patterns": ["IOS XR"]
  },
  "gnmi": {
    "path-format": "module-prefix",
    "default-encoding": "json_ietf",
    "default-origin": "",
    "notification-style": "standard"
  },
  "netconf": { "default-port": 830 },
  "snmp": {
    "profile-tags": ["cisco-iosxr"],
    "version-regex": "Cisco IOS XR Software.*Version\\s+(\\S+?)[\\[,\\s]"
  },
  "cli": {
    "prompt-hints": ["#", ">"],
    "paging-disable": "terminal length 0",
    "prompt-patterns": ["[\\r\\n]*[\\w+\\-\\.:\\/\\[\\]\\~]+(?:\\([^\\)]+\\)){0,1}(?:>|#|\\$) ?$"],
    "error-patterns": ["% ?Error", "Invalid input", "(?:incomplete|ambiguous) command"],
    "clean-shell": ["terminal length 0", "terminal width 512", "terminal exec prompt no-timestamp"]
  },
  "yang": { "embedded-subpath": "vendor/cisco/xr", "repo-slugs": ["openconfig"] },
  "playground": {
    "url": "https://github.com/Arolo-Solutions/prelude-collector-playground/tree/main/vendors/ios-xr",
    "examples": ["profile.json", "models/"]
  }
}
```

### Minimal create

```
action:  "create"
payload: "{\"schema-version\":1,\"netos\":\"acme-os\",\"display-name\":\"Acme OS\",\"vendor\":\"acme\"}"
```

### Update with audit note

```
action:      "update"
profile_id:  "12"
change_note: "tighten IOS-XR error patterns"
payload:     (full edited document — update replaces the whole payload)
```

### Import an array of profiles

```
action:      "import"
overwrite:   false
import_data: "[{\"schema-version\":1,\"netos\":\"acme-os\",\"display-name\":\"Acme OS\"}, {\"schema-version\":1,\"netos\":\"foo-os\",\"display-name\":\"Foo OS\"}]"
```
Returns counts: `{created, updated, skipped}` (`updated` only with `overwrite=true`).

### Roll back a profile

```
1. collector_vendor_profiles(action: "revisions", profile_id: "12")          # find the revision_id
2. collector_vendor_profiles(action: "diff", profile_id: "12", revision_id: "47")   # confirm the change
3. collector_vendor_profiles(action: "restore", profile_id: "12", revision_id: "47")
```
