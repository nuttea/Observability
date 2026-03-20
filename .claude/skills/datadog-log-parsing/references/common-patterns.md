# Common Log Format Parsing Patterns

Ready-to-use Datadog Grok parsing rules for common log formats.

## Table of Contents
- [NGINX Access Log](#nginx-access-log)
- [Apache Combined Log](#apache-combined-log)
- [Syslog (RFC 3164)](#syslog-rfc-3164)
- [Syslog (RFC 5424)](#syslog-rfc-5424)
- [JSON with Text Prefix](#json-with-text-prefix)
- [Key-Value / Logfmt](#key-value-logfmt)
- [Pipe-Delimited Transaction Logs (BEGIN/END)](#pipe-delimited-transaction-logs-beginend)
- [Kafka / Message Broker Logs](#kafka-message-broker-logs)
- [Multi-line: Message + JSON Metadata](#multi-line-message-json-metadata)
- [Datadog Agent Collector](#datadog-agent-collector)
- [Kubernetes / Glog](#kubernetes-glog)
- [Java Stack Trace](#java-stack-trace)
- [Python Log](#python-log)
- [Application with Embedded JSON](#application-with-embedded-json)
- [AWS ALB Access Log](#aws-alb-access-log)
- [Go Struct Logs](#go-struct-logs)
- [Generic Timestamp + Level + Message](#generic-timestamp-level-message)

---

## NGINX Access Log

**Sample:**
```
93.180.71.3 - - [17/May/2015:08:05:32 +0000] "GET /downloads/product_1 HTTP/1.1" 304 0 "-" "Debian APT-HTTP/1.3 (0.8.16~exp12ubuntu10.21)"
```

**Rule:**
```
nginx_access %{ipOrHost:network.client.ip} %{notSpace:http.ident} %{notSpace:http.auth} \[%{date("dd/MMM/yyyy:HH:mm:ss Z"):timestamp}\] "%{word:http.method} %{notSpace:http.url} HTTP/%{number:http.version}" %{integer:http.status_code} %{integer:network.bytes_written} "%{data:http.referer}" "%{data:http.useragent}"
```

**Extracted JSON:**
```json
{
  "network": { "client": { "ip": "93.180.71.3" }, "bytes_written": 0 },
  "http": {
    "ident": "-", "auth": "-",
    "method": "GET", "url": "/downloads/product_1", "version": 1.1,
    "status_code": 304, "referer": "-",
    "useragent": "Debian APT-HTTP/1.3 (0.8.16~exp12ubuntu10.21)"
  },
  "timestamp": 1431849932000
}
```

**Recommended processors:** Log Date Remapper (timestamp), GeoIP Parser (network.client.ip), User-Agent Parser (http.useragent)

---

## Apache Combined Log

**Sample:**
```
127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326 "http://www.example.com/start.html" "Mozilla/4.08"
```

**Rule:**
```
apache_combined %{ipOrHost:network.client.ip} %{notSpace:http.ident} %{notSpace:http.auth} \[%{date("dd/MMM/yyyy:HH:mm:ss Z"):timestamp}\] "%{word:http.method} %{notSpace:http.url} HTTP/%{number:http.version}" %{integer:http.status_code} %{integer:network.bytes_written} "%{data:http.referer}" "%{data:http.useragent}"
```

Same structure as NGINX. Apache and NGINX Combined Log Format are identical.

---

## Syslog (RFC 3164)

**Sample:**
```
Jan 15 10:30:00 myhost myapp[1234]: Connection established from 192.168.1.100
```

**Rule:**
```
syslog_3164 %{date("MMM dd HH:mm:ss"):timestamp} %{notSpace:syslog.hostname} %{word:syslog.appname}\[%{integer:syslog.procid}\]: %{data:message}
```

**Extracted JSON:**
```json
{
  "timestamp": 1705312200000,
  "syslog": { "hostname": "myhost", "appname": "myapp", "procid": 1234 },
  "message": "Connection established from 192.168.1.100"
}
```

---

## Syslog (RFC 5424)

**Sample:**
```
<165>1 2024-01-15T10:30:00.000Z myhost myapp 1234 ID47 - Connection established
```

**Rule:**
```
syslog_5424 <%{integer:syslog.priority}>%{integer:syslog.version} %{date("yyyy-MM-dd'T'HH:mm:ss.SSSZ"):timestamp} %{notSpace:syslog.hostname} %{notSpace:syslog.appname} %{notSpace:syslog.procid} %{notSpace:syslog.msgid} %{notSpace:syslog.sd} %{data:message}
```

---

## JSON with Text Prefix

**Sample:**
```
2024-01-15T10:30:00.000Z INFO server-01 {"method":"GET","status_code":200,"url":"/api/users","duration":45}
```

**Rule:**
```
json_prefix %{date("yyyy-MM-dd'T'HH:mm:ss.SSSZ"):timestamp} %{word:level} %{notSpace:host} %{data::json}
```

**Extracted JSON:**
```json
{
  "timestamp": 1705311000000,
  "level": "INFO",
  "host": "server-01",
  "method": "GET",
  "status_code": 200,
  "url": "/api/users",
  "duration": 45
}
```

Note: The `json` filter automatically flattens all JSON keys into the top-level extracted object.

---

## Key-Value / Logfmt

**Sample:**
```
time=2024-01-15T10:30:00Z level=info msg="request completed" method=GET path=/api/users status=200 duration=45ms
```

**Rule:**
```
logfmt %{data::keyvalue}
```

For non-default separators:
```
# Colon-separated: key: value
logfmt_colon %{data::keyvalue(": ")}

# With special chars in values (allow / and :)
logfmt_url %{data::keyvalue("=", "/:")}

# Pipe-delimited pairs: key=val|key=val
logfmt_pipe %{data::keyvalue("=", "", "", "|")}
```

---

## Pipe-Delimited Transaction Logs (BEGIN/END)

Common in microservice API gateways and orchestration services. Logs use `|` as a delimiter with `BEGIN`/`END` markers to track request lifecycle.

**Samples:**
```
BEGIN | POST /api/v1/transfer/submit | ee02dd40-0384-4157-a5d6-656607b935d9-crid
END | 200 | POST /api/v1/transfer/submit | 5375def4-53c8-41d4-b84c-2f5528c5dd65-crid
```

**Datadog auto-suggests** rules like:
```
autoFilledRule1 BEGIN\s+\|\s+%{word:http.method}\s+%{notSpace:http.url}\s+\|\s+%{notSpace:token_1}
autoFilledRule2 END\s+\|\s+%{integer:http.status_code}\s+\|\s+%{word:http.method}\s+%{notSpace:http.url}\s+\|\s+%{notSpace:token_1}
```

**Improved rules** (better attribute names, explicit `\s+` between method and path):
```
api_begin BEGIN\s+\|\s+%{word:http.method}\s+%{notSpace:http.path}\s+\|\s+%{notSpace:correlation_id}
api_end END\s+\|\s+%{integer:http.status_code}\s+\|\s+%{word:http.method}\s+%{notSpace:http.path}\s+\|\s+%{notSpace:correlation_id}
```

**With helper rules** (DRY approach):
```
# Helper rules
_pipe \s+\|\s+
_method_path %{word:http.method}\s+%{notSpace:http.path}

# Parsing rules -- _pipe handles | delimiters, \s+ in _method_path handles POST /path
api_begin BEGIN%{_pipe}%{_method_path}%{_pipe}%{notSpace:correlation_id}
api_end END%{_pipe}%{integer:http.status_code}%{_pipe}%{_method_path}%{_pipe}%{notSpace:correlation_id}
```

**Extracted JSON (BEGIN):**
```json
{
  "http": { "method": "POST", "path": "/api/v1/transfer/submit" },
  "correlation_id": "ee02dd40-0384-4157-a5d6-656607b935d9-crid"
}
```

**Extracted JSON (END):**
```json
{
  "http": { "method": "POST", "path": "/api/v1/transfer/submit", "status_code": 200 },
  "correlation_id": "5375def4-53c8-41d4-b84c-2f5528c5dd65-crid"
}
```

**Key improvements over auto-suggest:**
- `token_1` renamed to `correlation_id` (semantic meaning for tracing)
- `http.url` renamed to `http.path` (it's an API path, not a full URL)
- Helper rules reduce duplication across BEGIN/END
- `_pipe` handles delimiter whitespace; `\s+` in `_method_path` handles `POST /path` spacing
- Rule names describe the log type instead of generic `autoFilledRule1`

**Important: Fields and Attributes awareness**
If the user also provides JSON attributes like `{"severity":"INFO","timestamp":"...","statusCode":200}`, those are already parsed by Datadog from the JSON metadata line. The Grok rule only needs to parse the text message line -- do NOT re-extract attributes that already exist in the JSON.

**Recommended processors:** Log Status Remapper (use Category Processor to map BEGIN=info, END=status_code based)

---

## Kafka / Message Broker Logs

Logs from services that produce/consume messages to Kafka, RabbitMQ, or similar brokers. Often contain embedded JSON payloads.

**Sample:**
```
Message was saved to partition: 21. Message offset is: 19347172. Message: {"channel":"NN","channelTxnRef":"transfer-51370b09","correlationId":"10b809dd-crid","timestamp":"2026-02-16T10:09:39+07:00","amount":"149","transferType":"PROMPTPAY"}. Topic: camp.cross-sell.request.process. Key: %!s(<nil>).
```

**Rule:**
```
kafka_produce Message was saved to partition: %{integer:kafka.partition}\. Message offset is: %{integer:kafka.offset}\. Message: %{regex("[^}]*\\}"):message_body}\. Topic: %{notSpace:kafka.topic}\. Key: %{data:kafka.key}\.
```

**Alternate (extracting JSON payload):**
```
kafka_produce_json Message was saved to partition: %{integer:kafka.partition}\. Message offset is: %{integer:kafka.offset}\. Message: %{data:message_payload:json}\. Topic: %{notSpace:kafka.topic}\. Key: %{data:kafka.key}\.
```

Note: If using `data:json` for the message body, ensure the JSON does not contain `.` followed by a space (which could match the `. Topic:` delimiter). Prefer `regex("[^}]*\\}")` for safety.

**Extracted JSON:**
```json
{
  "kafka": { "partition": 21, "offset": 19347172, "topic": "camp.cross-sell.request.process", "key": "%!s(<nil>)" },
  "channel": "NN", "channelTxnRef": "transfer-51370b09",
  "correlationId": "10b809dd-crid", "amount": "149", "transferType": "PROMPTPAY"
}
```

---

## Multi-line: Message + JSON Metadata

Many microservices emit logs where the first line is human-readable text, followed by a second line of JSON metadata (severity, timestamp, latency, etc.). These are commonly seen in Go services.

**Sample (simple):**
```
authorization header missing, please check again.
{"severity":"ERROR","timestamp":"2026-02-16 10:08:32.932845773 +0700 +07"}
```

**Sample (BEGIN with JSON details):**
```
BEGIN | POST /api/v1/transfer/submit | b095a795-crid
{"severity":"INFO","realIp":"171.97.140.156","path":"/api/v1/transfer/submit","method":"POST","X-Correlation-Id":"b095a795-crid","host":"orch-camp:1323","timestamp":"2026-02-16 10:08:05.419183786 +0700 +07"}
```

**Sample (END with JSON details):**
```
END | 200 | POST /api/v1/transfer/submit | 780a6d3c-crid
{"severity":"INFO","method":"POST","X-Correlation-Id":"780a6d3c-crid","latency":"2.660541ms","responseCode":"00000","path":"/api/v1/transfer/submit","statusCode":200,"timestamp":"2026-02-16 10:04:57.322800831 +0700 +07"}
```

**Strategy:** In Datadog, multi-line logs need to be aggregated first using multi-line aggregation rules at the Agent level. Then parse the combined message.

**Rules for combined single-line (after multi-line aggregation):**
```
# BEGIN transaction with JSON metadata
begin_json BEGIN\s+\|\s+%{word:http.method}\s+%{notSpace:http.path}\s+\|\s+%{notSpace:correlation_id}\n%{data::json}

# END transaction with JSON metadata
end_json END\s+\|\s+%{integer:http.status_code}\s+\|\s+%{word:http.method}\s+%{notSpace:http.path}\s+\|\s+%{notSpace:correlation_id}\n%{data::json}

# Plain message with JSON metadata
msg_json %{data:message}\n%{data::json}
```

**Important:** The `\n` matches the newline between the text line and JSON line. This only works if multi-line aggregation is configured to combine these lines into one log event.

**Recommended processors:** Log Date Remapper (timestamp from JSON), Log Status Remapper (severity from JSON)

---

## Datadog Agent Collector

**Sample:**
```
2024-01-15 08:54:44 UTC | INFO | dd.collector | checks.collector(collector.py:530) | Finished run #1780. Collection time: 4.06s. Emit time: 0.01s
```

**Helper rules:**
```
_date %{date("yyyy-MM-dd HH:mm:ss z"):timestamp}
_severity %{word:level}
_collector %{notSpace:logger.name}
_source %{regex("[^(]*"):logger.source}\(%{notSpace:logger.file}:%{integer:logger.lineno}\)
```

**Rule:**
```
dd_collector %{_date} \| %{_severity} \| %{_collector} \| %{_source} \| %{data:message}
```

---

## Kubernetes / Glog

**Sample:**
```
W0424 11:47:41.605188       1 authorization.go:47] Authorization is disabled
```

**Rule:**
```
kube_glog %{regex("\\w"):level}%{date("MMdd HH:mm:ss.SSSSSS"):timestamp}\s+%{number:logger.thread_id} %{notSpace:logger.name}:%{number:logger.lineno}\] %{data:message}
```

**Level mapping:** `I`=Info, `W`=Warning, `E`=Error, `F`=Fatal

---

## Java Stack Trace

**Sample:**
```
2024-01-15 10:30:00.123 ERROR [main] com.example.App - NullPointerException: value cannot be null
```

**Rule:**
```
java_log %{date("yyyy-MM-dd HH:mm:ss.SSS"):timestamp} %{word:level} \[%{notSpace:logger.thread_name}\] %{notSpace:logger.name} - %{word:error.kind}: %{data:error.message}
```

**Alternate (without exception):**
```
java_log_msg %{date("yyyy-MM-dd HH:mm:ss.SSS"):timestamp} %{word:level} \[%{notSpace:logger.thread_name}\] %{notSpace:logger.name} - %{data:message}
```

Place the more specific rule (with exception pattern) ABOVE the generic one.

---

## Python Log

**Sample:**
```
2024-01-15 10:30:00,123 - myapp.module - WARNING - Connection timeout after 30s
```

**Rule:**
```
python_log %{date("yyyy-MM-dd HH:mm:ss,SSS"):timestamp} - %{notSpace:logger.name} - %{word:level} - %{data:message}
```

---

## Application with Embedded JSON

**Sample:**
```
Sep 06 09:13:38 vagrant program[123]: server.1 {"method":"GET", "status_code":200, "url":"https://app.datadoghq.com/logs/pipelines", "duration":123456}
```

**Rule:**
```
app_json %{date("MMM dd HH:mm:ss"):timestamp} %{word:vm} %{word:app}\[%{number:logger.thread_id}\]: %{notSpace:server} %{data::json}
```

---

## AWS ALB Access Log

**Sample:**
```
h2 2024-01-15T10:30:00.123456Z app/my-alb/50dc6c495c0c9188 192.168.1.1:443 10.0.0.1:80 0.001 0.003 0.000 200 200 123 456 "GET https://example.com:443/api/users HTTP/2.0" "Mozilla/5.0" ECDHE-RSA-AES128-GCM-SHA256 TLSv1.2
```

**Helper rules:**
```
_alb_ts %{date("yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ"):timestamp}
_alb_elb %{notSpace:elb.name}
_alb_client %{ip:network.client.ip}:%{port:network.client.port}
_alb_target %{ip:network.destination.ip}:%{port:network.destination.port}
_alb_times %{number:elb.request_processing_time} %{number:elb.target_processing_time} %{number:elb.response_processing_time}
_alb_codes %{integer:elb.status_code} %{integer:http.status_code}
_alb_bytes %{integer:network.bytes_read} %{integer:network.bytes_written}
```

**Rule:**
```
alb_access %{notSpace:http.protocol} %{_alb_ts} %{_alb_elb} %{_alb_client} %{_alb_target} %{_alb_times} %{_alb_codes} %{_alb_bytes} "%{word:http.method} %{notSpace:http.url} %{notSpace:http.version}" "%{data:http.useragent}" %{notSpace:ssl.cipher} %{notSpace:ssl.protocol}
```

---

## Go Struct Logs

Go services using `fmt.Sprintf("%+v", struct)` or `fmt.Sprintf("%v", struct)` produce struct dumps that look similar to JSON but are NOT JSON. The `json` filter will NOT work. Two common variants:

### Flat Go Struct (quoted string values, with type name)

Common in Go services logging payloads/results. Type name prefix like `&pkg.TypeName{...}`.

**Sample:**
```
payload to publish: &internalservice.CrossSellResultPayload{CdiToken:"iCL1Krv6ND6mFcH", DyContext:internalservice.DyContext{DyIDServer:"", DyID:"", DyVariationID:"", DyDecisionID:"", DySessionID:""}, Locale:"th", ReqDateTime:"2026-02-16T10:59:46+07:00", CampProcessStatus:"NOT_MATCHED", ChannelTxnRef:"payment-f401c102-1b12-4173-9fc8-17e292c44ed0", CampaignRefID:"", CampaignCode:"", Page:"", Placement:"", PositionID:"", ImageURL:"", ImageTitle:"", ImageMessage:"", IsUrlShareable:(*bool)(nil), NavigationPath:"", NavigationPathType:"", TemplateID:"", AssetID:"", Cmpsrc:""}
```

**Basic rule** (capture type + raw body for search):
```
payload_publish payload to publish: &%{notSpace:payload.type}\{%{data:payload.raw}
```

**Enhanced rule** (extract key fields with regex anchored to field names):
```
# Helper to extract a quoted Go struct field: FieldName:"value"
# Use regex("[^"]*") to capture everything inside the quotes

payload_publish_v2 payload to publish: &%{notSpace:payload.type}\{%{regex("[^\"]*CdiToken:\"%{regex("[^\"]*"):cdi_token}\""):_discard1}%{regex("[^\"]*CampProcessStatus:\"%{regex("[^\"]*"):camp_process_status}\""):_discard2}%{regex("[^\"]*ChannelTxnRef:\"%{regex("[^\"]*"):channel_txn_ref}\""):_discard3}%{data}
```

**Recommended approach** (simpler + Regex Remapper processors):
```
# Grok rule: parse prefix and capture raw body
payload_publish payload to publish: &%{notSpace:payload.type}\{%{data:payload.raw}
```

Then add **Regex Remapper** processors to extract from `payload.raw`:
| Regex Pattern | Target Attribute |
|---------------|-----------------|
| `CdiToken:"(?P<cdi_token>[^"]*)"` | `cdi_token` |
| `CampProcessStatus:"(?P<camp_process_status>[^"]*)"` | `camp_process_status` |
| `ChannelTxnRef:"(?P<channel_txn_ref>[^"]*)"` | `channel_txn_ref` |
| `CampaignRefID:"(?P<campaign_ref_id>[^"]*)"` | `campaign_ref_id` |
| `Locale:"(?P<locale>[^"]*)"` | `locale` |

**Extracted JSON (basic):**
```json
{
  "payload": {
    "type": "internalservice.CrossSellResultPayload",
    "raw": "CdiToken:\"iCL1Krv6ND6mFcH\", ... (full struct body)"
  }
}
```

**Extracted JSON (with Regex Remappers):**
```json
{
  "payload": { "type": "internalservice.CrossSellResultPayload", "raw": "..." },
  "cdi_token": "iCL1Krv6ND6mFcH",
  "camp_process_status": "NOT_MATCHED",
  "channel_txn_ref": "payment-f401c102-1b12-4173-9fc8-17e292c44ed0"
}
```

### Nested Go Struct (unquoted values, no type name)

Common in Go services logging cache/DB results. Prefix `&{...}` without type name.

**Sample:**
```
Acquire campaign 00ed3f84-2434-4dfc-b51f-7ad14cc69bc4 from cache: &{CampaignDetails:{CampaignRefID:00ed3f84-2434-4dfc-b51f-7ad14cc69bc4 CampaignID:C_LN_DL_AQ_BD_AL_26_01_002 CampaignChannel:[{AttributeID:DC0002} {AttributeID:DC0001}] LatestStatus:ACTIVE} CampaignAssetsKeyVisuals:{ChannelType:DIGITAL ...}}
```

**Basic rule** (parse prefix + capture body):
```
campaign_acquired Acquire campaign %{notSpace:campaign.ref_id} from cache: %{data:campaign.raw}
```

**Enhanced rule** (extract key fields from nested struct):
```
# For unquoted values: anchor to FieldName: then capture until space or }
campaign_acquired_v2 Acquire campaign %{notSpace:campaign.ref_id} from cache: &\{CampaignDetails:\{CampaignRefID:%{notSpace:campaign.details.ref_id} CampaignID:%{regex("[^\\s}]+"):campaign.details.id}%{regex("[^}]*")}LatestStatus:%{regex("[A-Z_]+"):campaign.details.status}\}%{data:campaign.raw}
```

**Extracted JSON (enhanced):**
```json
{
  "campaign": {
    "ref_id": "00ed3f84-2434-4dfc-b51f-7ad14cc69bc4",
    "details": {
      "ref_id": "00ed3f84-2434-4dfc-b51f-7ad14cc69bc4",
      "id": "C_LN_DL_AQ_BD_AL_26_01_002",
      "status": "ACTIVE"
    },
    "raw": " CampaignAssetsKeyVisuals:{ChannelType:DIGITAL ...}"
  }
}
```

### Go Struct Parsing Tips

1. **Quoted values** (`Field:"value"`): Use `regex("[^"]*")` anchored after `FieldName:"`
2. **Unquoted values** (`Field:value`): Use `regex("[^\\s}]+")` to capture until space or `}`
3. **Skip nested content**: Use `regex("[^}]*")` or `%{data}` to jump over sections you don't need
4. **Nil pointers** (`(*type)(nil)`): These can be matched with `regex("\\(\\*[^)]+\\)\\(nil\\)")` or just skipped
5. **Prefer Regex Remapper processors** for flat structs with many fields -- easier to maintain than complex Grok rules
6. **Always capture raw body** for full-text search even when extracting specific fields

---

## Generic Timestamp + Level + Message

**Sample:**
```
[2024-01-15T10:30:00.000Z] [INFO] [RequestHandler] Processing request for user 12345
```

**Rule:**
```
generic_log \[%{date("yyyy-MM-dd'T'HH:mm:ss.SSSZ"):timestamp}\] \[%{word:level}\] \[%{notSpace:logger.name}\] %{data:message}
```

---

## Tips for Custom Formats

1. **Identify delimiters first** - brackets `[]`, pipes `|`, dashes `-`, colons `:`
2. **Map fixed text** - literals that appear in every log line
3. **Choose simplest matcher** for each variable field
4. **Handle variations** - use `(pattern)?` for optional, `(a|b)` for alternation
5. **Test with edge cases** - long URLs, special characters, missing fields
6. **Use helper rules** when patterns repeat across multiple rules
