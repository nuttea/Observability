---
name: datadog-log-parsing
description: Generate Datadog Grok log parsing rules from sample log lines. Analyze log patterns, suggest matchers/filters, produce ready-to-use parsing rules with helper rules, and explain extracted attributes. Use when the user shares log samples, log patterns, asks about Datadog log parsing, Grok parsing rules, log pipeline configuration, or needs help writing parsing rules for Datadog Log Management.
---

# Datadog Log Parsing Rule Generator

Generate Datadog Grok parsing rules from user-provided log samples.

## Workflow

### Step 1: Collect Log Samples

Ask the user for:
1. **Sample log lines** (1-5 representative lines showing variations)
2. **Log source** (optional: NGINX, Apache, app logs, syslog, etc.)
3. **Desired attributes** (optional: which fields to extract)

If the user provides logs directly, proceed to analysis.

**Recognizing "Fields and Attributes" JSON:**
Users may paste both the raw log message AND a JSON block of Fields/Attributes from the Datadog Log Explorer. This JSON represents attributes that Datadog has **already parsed** (e.g., from a JSON metadata line, or from the log source integration). When present:
- **Do NOT re-extract** attributes already in the JSON -- they already exist
- **Focus Grok rules only on the unparsed text/message portion**
- **Note which attributes already exist** so the user understands what's covered vs. what needs parsing
- Example: if the JSON shows `"severity":"INFO"` and `"timestamp":"..."`, those are already parsed -- the Grok rule only needs to handle the text message line

### Step 2: Analyze the Log Pattern

For each sample log, identify:
- **Fixed text** (literals, delimiters, separators)
- **Variable fields** (timestamps, IPs, status codes, messages, etc.)
- **Structural patterns** (key-value, CSV, JSON embedded, XML, Go struct, etc.)
- **Optional/alternating sections** (fields that appear only sometimes)
- **Already-parsed attributes** (from Fields and Attributes JSON if provided)

**Recognize body format types:**
| Body Format | Looks Like | Parse Strategy |
|-------------|-----------|----------------|
| JSON | `{"key":"value"}` | Use `%{data::json}` filter |
| Key-Value | `key=value key2=value2` | Use `%{data::keyvalue}` filter |
| Go struct (`%+v`) | `&TypeName{Field:"value", Nested:{}}` or `&{Field:value}` | Extract key fields with `regex()` anchored to field names |
| XML | `<tag>value</tag>` | Use `%{data::xml}` filter |
| Plain text | Human-readable message | Use standard matchers |

**Go struct body identification:**
Go services often log structs with `fmt.Sprintf("%+v")`. Signs: `&{Field:Value}`, `&pkg.TypeName{Field:"value"}`, `[{...} {...}]` for slices, `(*type)(nil)` for nil pointers. These are NOT JSON and cannot use the `json` filter.

### Step 3: Generate Parsing Rules

Use the `%{MATCHER:EXTRACT:FILTER}` syntax. Core principles:

**Rule syntax:**
```
RuleName %{matcher:attribute_name:filter} literal_text %{matcher:attribute_name}
```

**Key rules:**
- Rules MUST match the **entire** log line (implicitly anchored with `^...$`)
- Use unique rule names (alphanumeric, `_`, `.`; must start with alphanumeric)
- Only the first matching rule applies (top to bottom)
- Empty/null values are not displayed in output

**Matcher selection priority (simplest first):**

| Pattern | Use When |
|---------|----------|
| `notSpace` | Token separated by spaces |
| `word` | Alphanumeric + underscore only |
| `integer` | Whole numbers |
| `number` | Decimal numbers |
| `ip` / `ipv4` / `ipv6` | IP addresses |
| `date("pattern")` | Timestamps (see date patterns below) |
| `quotedString` | Single or double-quoted strings |
| `data` | Catch-all (use sparingly, only at end or with filters) |
| `regex("pattern")` | Custom patterns (escape backslashes: `\\d`) |

**Common date patterns:**

| Format | Pattern |
|--------|---------|
| `2024-01-15T10:30:00.000Z` | `yyyy-MM-dd'T'HH:mm:ss.SSSZ` |
| `2024-01-15T10:30:00.000+00:00` | `yyyy-MM-dd'T'HH:mm:ss.SSSZZ` |
| `15/Jan/2024:10:30:00 +0000` | `dd/MMM/yyyy:HH:mm:ss Z` |
| `Jan 15 10:30:00` | `MMM dd HH:mm:ss` |
| `2024-01-15 10:30:00` | `yyyy-MM-dd HH:mm:ss` |
| `01/15/2024` | `MM/dd/yyyy` |

**Filters for post-processing:**

| Filter | Purpose |
|--------|---------|
| `json` | Parse embedded JSON |
| `keyvalue` / `keyvalue("sep")` | Extract key=value pairs |
| `csv("h1,h2,h3")` | Parse CSV/TSV |
| `xml` | Parse XML |
| `number` / `integer` | Cast to numeric |
| `lowercase` / `uppercase` | Case transform |
| `url` | Parse URL components |
| `scale(factor)` | Multiply numeric value |
| `array("[]", ",")` | Parse list to array |
| `useragent` | Parse user-agent string |
| `querystring` | Extract URL query params |

**Whitespace handling (critical):**
- Delimiter helpers (e.g., `_pipe` = `\s+\|\s+`) handle whitespace **around** delimiters
- But space-separated tokens **within** a field group need explicit `\s+` between matchers
- Example: `POST /api/v1/transfer` -- method and path are space-separated:
  - WRONG: `%{word:http.method}%{notSpace:http.path}` (missing `\s+`)
  - RIGHT: `%{word:http.method}\s+%{notSpace:http.path}`

**Special patterns:**
- **Optional attribute**: `(%{integer:user.id} )?` - wrap in `()?`
- **Alternating**: `(%{integer:id}|%{word:name})` - use `(|)`
- **Escape special chars**: `\[`, `\]`, `\{`, `\}`, `\|`, `\(`, `\)`, `\.`, `\:`
- **Whitespace**: `\s+` for variable whitespace, `\s` for single

### Step 4: Generate Helper Rules (if complex)

For complex logs, extract reusable patterns as helper rules:

```
# Helper rules
_timestamp %{date("yyyy-MM-dd HH:mm:ss"):timestamp}
_ip_port %{ip:network.client.ip}:%{port:network.client.port}
_http_method %{word:http.method}

# Main rule uses helpers
access_log %{_timestamp} %{_ip_port} %{_http_method} ...
```

Prefix helper names with `_` by convention.

### Step 5: Present the Output

For each rule set, provide:

1. **Parsing rule(s)** - ready to paste into Datadog
2. **Helper rules** (if any)
3. **Sample extracted JSON** - show what attributes will be created
4. **Attribute naming** - use Datadog standard attributes when applicable:
   - `http.method`, `http.status_code`, `http.url`
   - `network.client.ip`, `network.client.port`
   - `duration` (in nanoseconds)
   - `usr.id`, `usr.name`, `usr.email`
   - `logger.name`, `logger.thread_name`
   - `error.message`, `error.kind`, `error.stack`
5. **Notes** - mention any caveats, optional fields, or edge cases

### Step 6: Suggest Complementary Processors

After parsing, recommend relevant Datadog processors:
- **Log Date Remapper** - if a timestamp was extracted (parsing dates does NOT set the official log date)
- **Log Status Remapper** - if severity/level was extracted
- **URL Parser** - if URLs were extracted
- **User-Agent Parser** - if user-agent strings were found
- **GeoIP Parser** - if client IPs were extracted
- **Category Processor** - for mapping values to categories

## Parsing Go Struct Bodies

Go services often dump structs in logs using `%+v` format. These look similar to JSON but are NOT -- the `json` filter will not work.

### Strategy: Extract High-Value Fields with Regex Anchors

1. **Parse the text prefix** normally (the human-readable part before the struct)
2. **Identify high-value fields** in the struct body (IDs, statuses, types, amounts)
3. **Use `regex()` anchored to field names** to extract specific values
4. **Capture the full body** as a raw attribute for search

### Flat Go Struct (quoted string values)

Log: `payload to publish: &internalservice.CrossSellResultPayload{CdiToken:"abc", CampProcessStatus:"NOT_MATCHED", ChannelTxnRef:"transfer-123", ...}`

Regex pattern for quoted values: anchor to `FieldName:"` then capture `[^"]*`

```
# Extract key fields from flat Go struct with quoted values
payload_publish payload to publish: &%{notSpace:payload.type}\{%{data:payload.raw}

# More detailed: extract specific quoted fields
payload_publish_detail payload to publish: &%{regex("[^{]*"):payload.type}\{%{regex("[^}]*CdiToken:\"%{regex("[^\"]*"):cdi_token}\"[^}]*CampProcessStatus:\"%{regex("[^\"]*"):camp_process_status}\"[^}]*ChannelTxnRef:\"%{regex("[^\"]*"):channel_txn_ref}\""):payload.raw}\}
```

Simpler approach -- parse prefix, then use **Regex Remapper processors** on `payload.raw`:
```
# Rule: capture type and raw body
payload_publish payload to publish: &%{notSpace:payload.type}\{%{data:payload.raw}
```
Then add Regex Remapper processors:
- Pattern `CdiToken:"(?P<cdi_token>[^"]*)"` on `payload.raw`
- Pattern `CampProcessStatus:"(?P<camp_process_status>[^"]*)"` on `payload.raw`
- Pattern `ChannelTxnRef:"(?P<channel_txn_ref>[^"]*)"` on `payload.raw`

### Nested Go Struct (unquoted values)

Log: `Acquire campaign abc-123 from cache: &{CampaignDetails:{CampaignRefID:abc-123 CampaignID:C_LN_001 ... LatestStatus:ACTIVE} ...}`

Unquoted values are harder -- anchor to `FieldName:` then capture until space or `}`

```
# Parse prefix + extract key nested fields
campaign_acquired Acquire campaign %{notSpace:campaign.ref_id} from cache: &\{CampaignDetails:\{CampaignRefID:%{notSpace:campaign.details.ref_id} CampaignID:%{regex("[^\\s}]+"):campaign.details.id}%{regex("[^}]*")}LatestStatus:%{regex("[A-Z_]+"):campaign.details.status}\}%{data:campaign.raw}
```

### Decision Guide

| Struct Complexity | Strategy |
|-------------------|----------|
| Flat, few fields, quoted values | Extract in Grok rule with `regex("[^"]*")` |
| Flat, many fields | Capture raw body + Regex Remapper processors |
| Deeply nested | Capture raw body only, recommend JSON logging |
| Mixed (prefix + struct) | Parse prefix in Grok, capture body as raw |

For common Go struct patterns, see [references/common-patterns.md](references/common-patterns.md#go-struct-logs).

## Improving Auto-Suggested Rules

Datadog's "Parse My Logs" auto-suggest generates functional but generic rules. Always improve them:

### 1. Rename Generic Attributes
Auto-suggest uses `token_1`, `token_2`, etc. Replace with semantic names:
| Auto-Suggested | Improved | Why |
|----------------|----------|-----|
| `token_1` | `correlation_id` | Enables tracing across services |
| `token_2` | `request_id` | Standard request tracking |
| `token_1` | `session_id` | User session context |
| `http.url_1` | `http.url` | Standard attribute |

### 2. Rename Auto-Generated Rule Names
Replace `autoFilledRule1` with descriptive names: `api_begin`, `api_end`, `kafka_produce`, `error_log`.

### 3. Extract Helper Rules
If auto-suggest creates multiple rules with repeated patterns (e.g., `\s+\|\s+` appearing in every rule), extract to helpers:
```
# Before (auto-suggest) -- generic names, duplicated patterns
autoFilledRule1 BEGIN\s+\|\s+%{word:http.method}\s+%{notSpace:http.url}\s+\|\s+%{notSpace:token_1}
autoFilledRule2 END\s+\|\s+%{integer:http.status_code}\s+\|\s+%{word:http.method}\s+%{notSpace:http.url}\s+\|\s+%{notSpace:token_1}

# After (improved) -- semantic names, helpers, \s+ between method and path
_pipe \s+\|\s+
_method_path %{word:http.method}\s+%{notSpace:http.path}
api_begin BEGIN%{_pipe}%{_method_path}%{_pipe}%{notSpace:correlation_id}
api_end END%{_pipe}%{integer:http.status_code}%{_pipe}%{_method_path}%{_pipe}%{notSpace:correlation_id}
```

Note: `_pipe` handles whitespace around `|` delimiters. The `\s+` inside `_method_path` handles the space between `POST` and `/api/v1/...`. These are separate concerns -- delimiter whitespace vs. intra-field whitespace.

### 4. Use Datadog Standard Attributes
Map to standard names for out-of-the-box dashboard/monitor support.

### 5. Handle Multi-Line Logs
If the log has a text line followed by a JSON metadata line:
- Configure **multi-line aggregation** at the Agent level first
- Then use `\n` in the rule to match across lines: `%{data:message}\n%{data::json}`

## Best Practices to Communicate

When generating rules, follow and communicate these:

1. **Start simple**: Use `notSpace`, `word`, `integer` before `regex` or `data`
2. **Avoid `data` in the middle** of rules - use `[^DELIMITER]*` via `regex("[^}]*")` instead
3. **Use `data` only at the end** of lines or with filters (`json`, `keyvalue`)
4. **Test incrementally**: Build rules one attribute at a time, use `.*` at the end during development
5. **Use standard attribute names** from [Datadog Standard Attributes](https://docs.datadoghq.com/standard-attributes/)
6. **Limit to 10 parsing rules** per Grok parser
7. **Escape special characters**: `\[`, `\]`, `\|`, `\(`, `\)`, `\.`, `\:`, `\{`, `\}`
8. **Name attributes semantically**: Never leave `token_1` - always rename to `correlation_id`, `request_id`, `trace_id`, etc.
9. **Pipe-delimited logs**: Use `\s+\|\s+` pattern (handles variable whitespace around pipes)
10. **Multi-line logs**: Require Agent-level multi-line aggregation before Grok parsing

## References

- For complete matcher/filter reference: see [references/matchers-filters.md](references/matchers-filters.md)
- For common log format patterns (NGINX, Apache, syslog, etc.): see [references/common-patterns.md](references/common-patterns.md)
- Datadog docs: https://docs.datadoghq.com/logs/log_configuration/parsing/
- Regex guide: https://docs.datadoghq.com/logs/guide/regex_log_parsing/
