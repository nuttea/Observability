# Datadog Grok Matchers and Filters Reference

## Table of Contents
- [Matchers](#matchers)
- [Filters](#filters)
- [Date Pattern Reference](#date-pattern-reference)
- [Regex Inside Grok](#regex-inside-grok)
- [Special Syntax](#special-syntax)

---

## Matchers

Matchers define WHAT to expect in the log text.

### Text Matchers

| Matcher | Description | Regex Equivalent |
|---------|-------------|-----------------|
| `notSpace` | Any string until next space | `\S+` |
| `word` | Alphanumeric + underscore, word boundaries | `\b\w+\b` |
| `data` | Any string including spaces/newlines (lazy) | `.*?` |
| `doubleQuotedString` | Content in double quotes | `"[^"]*"` |
| `singleQuotedString` | Content in single quotes | `'[^']*'` |
| `quotedString` | Content in single or double quotes | `["'][^"']*["']` |

### Numeric Matchers

| Matcher | Description | Parsed Type |
|---------|-------------|-------------|
| `number` | Decimal floating point | double |
| `numberStr` | Decimal floating point | string |
| `numberExt` | Float with scientific notation (e.g., `1.5e10`) | double |
| `numberExtStr` | Float with scientific notation | string |
| `integer` | Integer number | integer |
| `integerStr` | Integer number | string |
| `integerExt` | Integer with scientific notation | integer |
| `integerExtStr` | Integer with scientific notation | string |

### Network Matchers

| Matcher | Description | Example Match |
|---------|-------------|---------------|
| `ip` | IPv4 or IPv6 address | `192.168.1.1`, `::1` |
| `ipv4` | IPv4 address only | `192.168.1.1` |
| `ipv6` | IPv6 address only | `fe80::1` |
| `hostname` | Hostname | `server01.example.com` |
| `ipOrHost` | IP address or hostname | `192.168.1.1` or `server01` |
| `port` | Port number | `8080` |
| `mac` | MAC address | `00:1B:44:11:3A:B7` |
| `uuid` | UUID | `550e8400-e29b-41d4-a716-446655440000` |

### Special Matchers

| Matcher | Description |
|---------|-------------|
| `boolean("true","false")` | Boolean with optional custom patterns |
| `date("pattern"[,"tz"[,"locale"]])` | Timestamp with Java date format |
| `regex("pattern")` | Custom regex (double-escape backslashes) |

---

## Filters

Filters are post-processors applied AFTER matching. Syntax: `%{matcher:attribute:filter}`

### Type Casting Filters

| Filter | Description |
|--------|-------------|
| `number` | Cast to double |
| `integer` | Cast to integer |
| `boolean` | Cast "true"/"false" to boolean |
| `nullIf("value")` | Return null if match equals value |

### String Filters

| Filter | Description |
|--------|-------------|
| `lowercase` | Convert to lowercase |
| `uppercase` | Convert to uppercase |
| `decodeuricomponent` | Decode URI (e.g., `%2F` → `/`) |
| `scale(factor)` | Multiply numeric value by factor |

### Structured Data Filters

| Filter | Syntax | Description |
|--------|--------|-------------|
| `json` | `%{data::json}` | Parse JSON object |
| `xml` | `%{data::xml}` | Parse XML to JSON |
| `csv` | `%{data:attr:csv("h1,h2,h3"[,"sep"[,"quote"]])}` | Parse CSV/TSV |
| `keyvalue` | `%{data::keyvalue([sep[,allow[,quote[,delim]]]])}` | Extract key=value pairs |
| `array` | `%{data:attr:array("[]",","[,subFilter])}` | Parse list to array |
| `url` | `%{data:attr:url}` | Parse URL components |
| `querystring` | `%{data:attr:querystring}` | Extract URL query params |
| `useragent` | `%{data:attr:useragent}` | Parse user-agent string |
| `rubyhash` | `%{data::rubyhash}` | Parse Ruby hash format |

### keyvalue Filter Details

`keyvalue([separatorStr[, characterAllowList[, quotingStr[, delimiter]]]])`

| Parameter | Default | Description |
|-----------|---------|-------------|
| `separatorStr` | `=` | Separator between key and value |
| `characterAllowList` | `\\w.\\-_@` | Extra chars allowed in unquoted values |
| `quotingStr` | `<>`, `""`, `''` | Quoting characters |
| `delimiter` | space, `,`, `;` | Separator between key-value pairs |

Examples:
```
%{data::keyvalue}                         # key=value (default)
%{data::keyvalue(": ")}                   # key: value
%{data::keyvalue("=", "/:")}              # Allow / and : in values
%{data::keyvalue(":=", "", "{}")}         # key:={value}
%{data::keyvalue("=", "", "", "|")}       # key1=val1|key2=val2
```

### csv Filter Details

`csv(headers[, separator[, quotingcharacter]])`

| Parameter | Default | Description |
|-----------|---------|-------------|
| `headers` | (required) | Comma-separated key names |
| `separator` | `,` | Value delimiter (use `tab` for TSV) |
| `quotingcharacter` | `"` | Quote character |

### array Filter Details

`array([[openCloseStr, ] separator][, subRuleOrFilter])`

Examples:
```
%{data:users:array("[]", ",")}            # [John, Jane, Bob]
%{data:users:array("{}", "-")}            # {John-Jane-Bob}
%{data:users:array("{}", "-", uppercase)} # with sub-filter
```

---

## Date Pattern Reference

The `date()` matcher uses Java SimpleDateFormat patterns.

### Pattern Characters

| Symbol | Meaning | Example |
|--------|---------|---------|
| `yyyy` | 4-digit year | `2024` |
| `yy` | 2-digit year | `24` |
| `MM` | Month (01-12) | `01` |
| `MMM` | Month abbreviation | `Jan` |
| `dd` | Day of month (01-31) | `15` |
| `d` | Day of month (1-31) | `5` |
| `HH` | Hour 24h (00-23) | `14` |
| `hh` | Hour 12h (01-12) | `02` |
| `mm` | Minute (00-59) | `30` |
| `ss` | Second (00-59) | `45` |
| `SSS` | Milliseconds | `123` |
| `SSSSSS` | Microseconds | `123456` |
| `a` | AM/PM | `PM` |
| `EEE` | Day of week (short) | `Mon` |
| `Z` | Timezone offset (+0000) | `+0000` |
| `ZZ` | Timezone offset (+00:00) | `+00:00` |
| `z` | Timezone name | `UTC`, `ADT` |
| `'T'` | Literal character | `T` |

### Timezone Support

| Format | Example |
|--------|---------|
| Named | `UTC`, `GMT`, `Z` |
| Offset | `+hh:mm`, `-hhmm` |
| Prefixed | `UTC+5`, `GMT-3` |
| TZ Database | `Europe/Paris`, `America/New_York` |

Usage: `%{date("pattern", "timezone"):attribute}`

---

## Regex Inside Grok

### Inline (outside `%{}`)
```
rule_name literal\s+%{word:attr}\s+more_literal
```
Backslashes need single escape.

### Inside regex matcher (`%{regex("")}`)
```
%{regex("\\d{3}"):status_code}       # 3 digits
%{regex("[a-zA-Z0-9_-]+"):token}     # Custom token
%{regex("[^}]*"):content}            # Everything until }
%{regex("(?i)error|warn"):level}     # Case-insensitive
%{regex("\\w"):single_char}          # Single word char
```
Backslashes need **double** escape inside `regex("")`.

### Prefer `[^X]*` over `data`
```
# BAD - may timeout on long logs
rule \{%{data:content}\} rest

# GOOD - explicit boundary
rule \{%{regex("[^}]*"):content}\} rest
```

---

## Special Syntax

### Optional Attribute
```
(%{integer:user.id} )?
```
Note: include space INSIDE the optional group before `)?`.

### Alternating Patterns
```
(%{integer:user.id}|%{word:user.name})
```

### Discard Matched Text (no extract)
```
%{notSpace}          # Match but don't extract
%{data:ignore}       # Extract to throwaway attribute
```

### Nested Attributes
```
%{word:user.name}          # Creates {"user": {"name": "..."}}
%{integer:http.status_code} # Creates {"http": {"status_code": ...}}
```

### Escaping Special Characters

Must escape: `[`, `]`, `{`, `}`, `(`, `)`, `|`, `.`, `*`, `+`, `?`, `^`, `$`, `\`, `:`

```
\[ \] \{ \} \( \) \| \. \* \+ \? \^ \$ \\ \:
```
