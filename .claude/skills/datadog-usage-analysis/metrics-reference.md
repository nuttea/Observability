# Datadog Usage Metrics Reference

Complete catalog of `datadog.estimated_usage.*` metrics and product allotment tables.

> EUM metrics may differ from actual billable usage by 10–20%. Authoritative source: **Plan & Usage** page (lags 1–2 days).

---

## Metric Type Quick Reference

| Type | Products | Each point represents | How to get monthly total |
|------|----------|----------------------|-------------------------|
| **Gauge** | Hosts, containers, custom metrics, profiler, DBM, USM, NPM, NDM, CSPM, CWS, ASM, IoT | Rolling-window snapshot (60 min or 5 min) | Read `avg`/`max` directly; do NOT sum over time |
| **Count** | Logs events/bytes, RUM sessions, APM spans/bytes, Synthetics runs, CI Visibility | Events in that interval | `.as_count()` then `cumsum()` or `.rollup(sum, monthly)` |

---

## Infrastructure (gauge)

| Metric | Measures | Window |
|--------|----------|--------|
| `datadog.estimated_usage.hosts[.by_tag]` | Infra hosts (Agent, AWS, GCP, Azure, Alibaba, Heroku, OTel, vSphere) | 60 min |
| `datadog.estimated_usage.containers[.by_tag]` | Containers (incl. Agent containers) | 5 min |
| `datadog.estimated_usage.iot.devices[.by_tag]` | IoT devices | 60 min |

> Azure App Services hosts are NOT included in `estimated_usage.hosts` or `apm_hosts`.

## Custom Metrics (gauge)

| Metric | Measures | Window |
|--------|----------|--------|
| `datadog.estimated_usage.metrics.custom[.by_tag]` | Indexed custom metrics | 60 min |
| `datadog.estimated_usage.metrics.custom.by_metric` | Same, tagged by `metric_name` | 60 min |
| `datadog.estimated_usage.metrics.custom.ingested[.by_tag]` | Ingested custom metrics (MwL only) | 60 min |
| `datadog.estimated_usage.metrics.standard` | Standard metrics (select customers) | 60 min |

## APM (mixed)

| Metric | Type | Measures | Window |
|--------|------|----------|--------|
| `datadog.estimated_usage.apm_hosts[.by_tag]` | gauge | APM hosts | 60 min |
| `datadog.estimated_usage.apm.fargate_tasks[.by_tag]` | gauge | APM Fargate tasks | 5 min |
| `datadog.estimated_usage.apm.indexed_spans` | count | Indexed spans | rolling |
| `datadog.estimated_usage.apm.ingested_bytes` | count | Ingested span bytes | rolling |
| `datadog.estimated_usage.apm.data_streams_monitoring_hosts[.by_tag]` | gauge | DSM hosts | 60 min |

## Logs (count)

| Metric | Measures | Key tags |
|--------|----------|----------|
| `datadog.estimated_usage.logs.ingested_events` | Events ingested (incl. excluded) | `datadog_index`, `datadog_is_excluded`, `service`, `status` |
| `datadog.estimated_usage.logs.ingested_bytes` | Ingested volume (for ingest fee) | `datadog_index`, `datadog_is_excluded`, `service` |

**Standard Index billing:** filter `{datadog_is_excluded:false}` for billable events. Break down by `{datadog_index}` then map index → retention from [Logs → Indexes](https://app.datadoghq.com/logs/pipelines/indexes).

**Flex Logs:** No EUM metric. Check [Plan & Usage → Logs](https://app.datadoghq.com/billing/usage?category=logs) → "Flex Logs Stored (Starter)".

| Tier | SKU | Billing unit | Retention |
|------|-----|-------------|-----------|
| Standard | `LOGS_INDEXED_*DAY` | New events per day, summed monthly | 3/7/15/30/45/60 days |
| Flex Starter | `FLEX-LOGS-STARTER` | Avg cumulative stored events × $0.60/M/month | 3/6/12/15 months |
| Flex Scalable | `FLEX-STORED-LOGS` + compute | Stored events + compute tier | 30–450 days |

Flex committed amount = monthly_ingest × retention_months (at steady state).

**Ingest fee waiver:** If 100% of logs are indexed (no exclusion filters), ingest fee ($0.10/GB) is waived.

### Logs query patterns

```
# Standard indexed events — monthly total
cumsum(sum:datadog.estimated_usage.logs.ingested_events{datadog_is_excluded:false}.as_count())

# By index (to see per-retention-tier)
cumsum(sum:datadog.estimated_usage.logs.ingested_events{datadog_is_excluded:false} by {datadog_index}.as_count())

# Ingested bytes — monthly total
cumsum(sum:datadog.estimated_usage.logs.ingested_bytes{*}.as_count())
```

## RUM (count)

Three independent SKUs under RUM Without Limits:

| SKU | Metric | Controls |
|-----|--------|----------|
| **RUM Measure** | `datadog.estimated_usage.rum.ingested_sessions` | `sessionSampleRate` (keep at 100%) |
| **RUM Investigate** | `datadog.estimated_usage.rum.indexed_sessions` | Retention Filters in UI |
| **Session Replay** | `datadog.estimated_usage.rum.sessions{sku:replay}` | `sessionReplaySampleRate` |

Relationship: `Measure ≥ Investigate ≥ Session Replay`. If no retention filters: Measure = Investigate.

### RUM query patterns (MUST use `.as_count()`)

```
# Monthly totals
sum:datadog.estimated_usage.rum.ingested_sessions{*}.as_count().rollup(sum, monthly)
sum:datadog.estimated_usage.rum.indexed_sessions{*}.as_count().rollup(sum, monthly)
sum:datadog.estimated_usage.rum.sessions{sku:replay}.as_count().rollup(sum, monthly)

# Running cumulative
cumsum(sum:datadog.estimated_usage.rum.indexed_sessions{*}.as_count())
```

## Serverless

### AWS Lambda (legacy SKU)

| Metric | Type | Measures |
|--------|------|----------|
| `datadog.estimated_usage.serverless.aws_lambda_functions[.by_tag]` | gauge | Active Lambda functions (60 min) |
| `datadog.estimated_usage.serverless.invocations[.by_tag]` | count | Lambda invocations |
| `datadog.estimated_usage.serverless.traced_invocations` | count | APM-traced invocations |

### Serverless Apps (new `SERVERLESS_APPS` SKU — Fargate, Azure, GCP)

| Workload | Infra metric |
|----------|-------------|
| AWS Fargate | `datadog.estimated_usage.fargate_tasks[.by_tag]` |
| Azure App Services | `count_nonzero(default_zero(sum:azure.app_services.cpu_time{*} by {instance,name}.rollup(sum, 300)))` |
| Azure Functions | `count_nonzero(default_zero(sum:azure.functions.function_execution_count{...} by {name,instance}.as_count().rollup(sum, 300)))` |
| Azure Container Apps | `count_nonzero(default_zero(sum:azure.app_containerapps.replicas{*} by {name}.rollup(sum, 300)))` |
| GCP Cloud Run | `sum:gcp.run.container.instance_count{state:active}.rollup(avg, 300)` |
| GCP Cloud Functions | `sum:gcp.cloudfunctions.function.instance_count{state:active,cloudfunction_generation:gen_1}.rollup(avg, 300)` |

## Other Products (gauge unless noted)

| Metric | Product |
|--------|---------|
| `datadog.estimated_usage.profiling.hosts[.by_tag]` | Continuous Profiler hosts |
| `datadog.estimated_usage.profiling.containers[.by_tag]` | Profiler containers |
| `datadog.estimated_usage.dbm.hosts[.by_tag]` | Database Monitoring hosts |
| `datadog.estimated_usage.usm.hosts[.by_tag]` | USM hosts (excl. APM hosts) |
| `datadog.estimated_usage.network.hosts[.by_tag]` | NPM hosts |
| `datadog.estimated_usage.network.devices[.by_tag]` | NDM devices |
| `datadog.estimated_usage.cspm.hosts[.by_tag]` | CSPM hosts |
| `datadog.estimated_usage.cws.hosts[.by_tag]` | CWS hosts |
| `datadog.estimated_usage.asm.hosts[.by_tag]` | ASM hosts |
| `datadog.estimated_usage.security_monitoring.analyzed_bytes` (count) | Cloud SIEM bytes |
| `datadog.estimated_usage.sds.scanned_bytes` (count) | SDS bytes |
| `datadog.estimated_usage.synthetics.api_test_runs` (count) | Synthetics API runs |
| `datadog.estimated_usage.synthetics.browser_test_runs` (count) | Synthetics Browser runs |
| `datadog.estimated_usage.incident_management.active_users` (gauge, MTD) | IM active users |
| `datadog.estimated_usage.ci_visibility.test.committers` (count) | CI Test committers |
| `datadog.estimated_usage.ci_visibility.pipeline.committers` (count) | CI Pipeline committers |

---

# Product Allotment Tables

Allotments = free child-product usage bundled with parent products.
Formula: `On-demand = Actual − max(Actual_parent, Committed_parent) × allotment_rate`

## Infrastructure Containers

| Parent SKU | Containers/host/hr | Custom Metrics/host | Custom Events/host/mo |
|-----------|-------------------|--------------------|-----------------------|
| Infra Pro | 5 | 100 | 500 |
| Infra Pro Plus | 5 | 100 | 500 |
| Infra Enterprise | 10 | 200 | 1,000 |

Container overage = $0.002/container/hour. Allotments NOT shared across types.

## APM Containers (Profiled)

| Parent SKU | Profiled containers/host/hr |
|-----------|---------------------------|
| APM Enterprise | 4 |
| Continuous Profiler | 4 |

## Security Containers

| Parent SKU | Containers/host/hr |
|-----------|-------------------|
| CWS | 4 |
| CSPM Pro | 4 |
| CSPM Enterprise | 20 |

## APM Spans

### Indexed Spans (15-day retention)

| Parent SKU | Monthly/host |
|-----------|-------------|
| APM / APM Pro / APM Enterprise | 1M spans |
| Fargate Task (APM) | 65K spans/task |
| Serverless APM | 300K spans/1M invocations |
| ASM | 100K spans/ASM host |

### Ingested Spans

| Parent SKU | Monthly/host |
|-----------|-------------|
| APM / APM Pro / APM Enterprise | 150 GB |
| Fargate Task (APM) | 10 GB/task |
| Serverless APM | 50 GB/1M invocations |

## Custom Metrics

| Parent SKU | Indexed CM/unit | Ingested CM/unit |
|-----------|----------------|-----------------|
| Infra Pro / Pro Plus | 100/host | 100/host |
| Infra Enterprise | 200/host | 200/host |
| Serverless Functions | 5/function | 5/function |
| Serverless Apps | 5/instance | 5/instance |
| IoT | 20/device | — |

## NPM Network Flows

| Parent SKU | Flows/host/month |
|-----------|-----------------|
| NPM | 6M (8,220/hr) |
