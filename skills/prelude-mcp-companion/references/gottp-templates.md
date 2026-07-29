# GoTTP Template Reference for CLI Mappings

CLI protocol mappings require a TTP (Template Text Parser) template to parse raw CLI output into structured records. The collector uses GoTTP (`git.arolo.net/arolo/gottp`) — a Go implementation of TTP.

## When You Need a TTP Template

- Every CLI mapping **requires** a `cli-template` field
- If `cli-template` is empty, the parser falls back to raw mode (no structured parsing)
- Templates are compiled once at config time and reused for every collection

## Decision Tree — Choose the Right Structure

| CLI Output Pattern | Template Structure |
|---|---|
| Key-value lines (one value per line) | Flat template, no `<group>` needed |
| Repeating rows with same columns | `<group method="table">` |
| Column-aligned table with a header row | `<group method="table">` + `{{ _headers_ }}` |
| Hierarchical blocks with indentation/sections | Nested `<group>` with `{{ _start_ }}` / `{{ _end_ }}` |

## Syntax Reference

### Variables

| Syntax | Description |
|--------|-------------|
| `{{ variable }}` | Match any non-whitespace token |
| `{{ variable \| PATTERN }}` | Named pattern match |
| `{{ variable \| re('regex') }}` | Custom regex match |
| `{{ variable \| func1 \| func2(arg) }}` | Chained functions |
| `{{ ignore }}` | Consume without saving |
| `{{ _start_ }}` | New record boundary |
| `{{ _end_ }}` | End record boundary |
| `{{ _line_ }}` | Capture entire line |
| `{{ _headers_ }}` | Column-based table parsing |

### Named Patterns

| Pattern | Matches |
|---------|---------|
| `DIGIT` | Counters, IDs, port numbers, AS numbers |
| `IP` | IPv4 addresses |
| `IPV6` | IPv6 addresses |
| `PREFIX` | CIDR notation (10.0.0.0/24) |
| `PREFIXV6` | IPv6 CIDR notation |
| `MAC` | MAC addresses |
| `PHRASE` | Multi-word values (always 2+ words) |
| `ORPHRASE` | Descriptions that may be 1 word or many |
| `ROW` | Capture all remaining whitespace-separated words |

### Match Functions

| Category | Functions |
|----------|-----------|
| **Type** | `to_int`, `to_float`, `to_list` |
| **String** | `upper`, `lower`, `strip`, `split(',')`, `replaceall` |
| **Conditions** | `contains('x')`, `exclude('x')`, `greaterthan(n)`, `lessthan(n)` |
| **Special** | `default('val')`, `set('val')`, `set(true)`, `joinmatches`, `joinmatches(', ')` |

### Groups

| Syntax | Description |
|--------|-------------|
| `<group name="items*">` | List of records |
| `<group name="items*" method="table">` | Every line starts a new record |
| `<group name="items*" contains="up">` | Keep only records containing "up" |
| `<group name="items*" exclude="down">` | Discard records containing "down" |
| `<group name="items*" default="N/A">` | Default for unmatched variables |

## Rules

1. **Indentation matters** — match the CLI output's leading whitespace exactly
2. **Variable names** — `lower_snake_case`, descriptive (e.g. `admin_state` not `a`)
3. **Capture everything** — every dynamic value (counters, states, addresses, names) should be a named variable. Only use `{{ ignore }}` for decorative lines (`===`, `---`)
4. **Type variables** using Named Patterns when the semantic type is known — e.g. `{{ ip_address | IP }}`, `{{ count | DIGIT }}`, `{{ mac | MAC }}`, `{{ description | ORPHRASE }}`
5. **Literal text stays literal** — only replace dynamic values with `{{ variable }}`
6. **Group names** use `*` suffix for lists: `<group name="interfaces*">`
7. **Nested groups** use dot-path naming (`<group name="bgp.neighbors*">`) or nest `<group>` tags
8. **No `<macro>`** — not supported in GoTTP

## Anti-Patterns

- Do NOT skip dynamic values — capture every counter, state, address, name, and flag
- Do NOT capture fixed keywords as variables — leave them as literal text
- Do NOT use `method="table"` for hierarchical block output — use nested groups
- Do NOT omit the header line in `method="table"` groups — always include the literal header row from the CLI output inside the group, before the variable line
- Do NOT forget `{{ ignore }}` for separator/decoration lines

## Examples

### Example A — Key-Value (flat, like "show system info")

**CLI output:**
```
System Name            : router-01
System Type            : 7750 SR-12
Chassis Topology       : Standalone
Location               : DC-Paris-01
Up Time                : 45 days, 12:34:56
```

**Template:**
```
System Name            : {{ system_name }}
System Type            : {{ system_type | ORPHRASE }}
Chassis Topology       : {{ chassis_topology }}
Location               : {{ location }}
Up Time                : {{ up_time | ORPHRASE }}
```

### Example B — Table (like "show router route-table")

**CLI output:**
```
===============================================================================
Route Table (Router: Base)
===============================================================================
Dest Prefix                                   Type    Proto     Age        Pref
-------------------------------------------------------------------------------
10.0.0.0/24                                   Remote  BGP       01d12h     170
10.0.1.0/24                                   Remote  OSPF      05h22m     10
192.168.1.0/24                                Local   Local     45d12h     0
-------------------------------------------------------------------------------
No. of Routes: 3
===============================================================================
```

**Template:**
```
<group name="route_table">
=============================================================================== {{ ignore }}
Route Table (Router: Base) {{ _start_ }}
=============================================================================== {{ ignore }}
------------------------------------------------------------------------------- {{ ignore }}
<group name="routes*" method="table">
Dest Prefix                                   Type    Proto     Age        Pref
{{ prefix | PREFIX }}                                   {{ type }}    {{ protocol }}     {{ age }}        {{ preference | DIGIT }}
</group>
------------------------------------------------------------------------------- {{ _end_ }}
<group name="summary">
No. of Routes: {{ total | DIGIT }}
</group>
=============================================================================== {{ ignore }}
</group>
```

### Example C — Hierarchical with Nested Groups (like "show interfaces")

**CLI output:**
```
===============================================================================
Interface Table (Router: Base)
===============================================================================
-------------------------------------------------------------------------------
system                     Up        10.0.0.1/32        N/A     system
   10.0.0.1/32                                                    n/a
-------------------------------------------------------------------------------
to-core-1                  Up        172.16.0.1/30      MPLS    1/1/1
   172.16.0.1/30                                                  n/a
-------------------------------------------------------------------------------
to-core-2                  Down      172.16.0.5/30      MPLS    1/1/2
   172.16.0.5/30                                                  n/a
-------------------------------------------------------------------------------
Interfaces : 3
===============================================================================
```

**Template:**
```
<group name="interfaces">
=============================================================================== {{ ignore }}
Interface Table (Router: Base) {{ _start_ }}
=============================================================================== {{ ignore }}
<group name="{{ interface_name }}" method="table">
------------------------------------------------------------------------------- {{ ignore }}
Interface                  AdminState  IP                 Mode    Port
{{ interface_name | _start_ }}                     {{ admin_state }}        {{ ip_address }}/{{ prefix_length | DIGIT }}        {{ mode }}     {{ port }}
   <group name="address" method="table">
   {{ address | PREFIX | _start_ }}                                                  {{ state | _end_ }}
   </group>
</group>
<group name="count">
------------------------------------------------------------------------------- {{ ignore }}
Interfaces : {{ total | DIGIT }}
=============================================================================== {{ _end_ }}
</group>
</group>
```

## Using TTP Templates in MCP

When calling `collector_mappings` with action `add` and protocol `cli`, the `cli_template` parameter is a plain string (newlines as `\n`). The `cli_commands` parameter is a JSON-encoded string array.

**How TTP Results Map to Fields:**

1. TTP parses CLI output into structured records (list of maps)
2. The key source is resolved: the TTP variable that `field-mappings` maps onto the model's `is_key` field
3. `FlattenTTPResults` extracts all leaf-level maps containing that key source
4. Records are merged by key value (deduplication)
5. `field-mappings` maps TTP variable names to model field names: `{"ttp_var": "model-field"}`

So the template **must capture the key source as a variable** — if the TTP variable feeding the key
field never appears in the template, every record is dropped.
