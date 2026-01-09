# Datadog Logs Features Configuration

This document explains all log collection features configured in the Datadog Agent Helm chart and additional options you can enable.

## Enabled Features

### 1. Auto Multi-Line Detection

**Configuration:**
```yaml
logs:
  autoMultiLineDetection: true
```

**What it does:**
- Automatically detects and aggregates multi-line logs into single log events
- Particularly useful for stack traces, JSON objects, and exception messages
- No manual configuration needed for most common patterns

**Example:**
```
Before (3 separate logs):
  java.lang.NullPointerException: null
      at com.example.Service.process(Service.java:42)
      at com.example.Controller.handle(Controller.java:89)

After (1 log event):
  java.lang.NullPointerException: null
      at com.example.Service.process(Service.java:42)
      at com.example.Controller.handle(Controller.java:89)
```

**Use cases:**
- Java/Python stack traces
- Multi-line JSON logs
- SQL query logs
- Error messages with context

### 2. File-Based Log Collection

**Configuration:**
```yaml
env:
  - name: DD_LOGS_CONFIG_K8S_CONTAINER_USE_FILE
    value: "true"
```

**What it does:**
- Collects logs from `/var/log/pods` instead of Docker socket
- Better performance and scalability
- Reduced CPU overhead
- Recommended for production environments

**Benefits:**
- More efficient resource usage
- Better handling of high log volumes
- No dependency on Docker socket

### 3. Open Files Limit

**Configuration:**
```yaml
env:
  - name: DD_LOGS_CONFIG_OPEN_FILES_LIMIT
    value: "500"
```

**What it does:**
- Limits the number of log files the agent can tail simultaneously
- Prevents resource exhaustion on nodes with many containers
- Default: 100 (if not specified)

**When to adjust:**
- Increase if you have many containers per node
- Decrease to reduce agent memory usage
- Monitor agent status to tune this value

**Calculation:**
```
Recommended value = (Average containers per node × 1.5)
Example: 300 containers per node → set to 450-500
```

### 4. Namespace-Based Filtering

**Configuration:**
```yaml
containerIncludeLogs: "kube_namespace:datadog-test-a kube_namespace:datadog-test-b"
```

**What it does:**
- Only collects logs from specified namespaces
- Reduces log volume and costs
- Improves agent performance

**Syntax:**
```yaml
# Single namespace
containerIncludeLogs: "kube_namespace:production"

# Multiple namespaces
containerIncludeLogs: "kube_namespace:prod kube_namespace:staging"

# Pattern matching
containerIncludeLogs: "kube_namespace:prod-*"
```

## Additional Features (Not Currently Enabled)

### 5. Global Log Processing Rules

**Configuration:**
```yaml
env:
  - name: DD_LOGS_CONFIG_PROCESSING_RULES
    value: '[{"type":"exclude_at_match","name":"exclude_healthcheck","pattern":"GET /health"}]'
```

**Available rule types:**

#### A. Exclude Logs (exclude_at_match)
```yaml
- name: DD_LOGS_CONFIG_PROCESSING_RULES
  value: |
    [
      {
        "type": "exclude_at_match",
        "name": "exclude_healthchecks",
        "pattern": "(GET|POST) /health"
      },
      {
        "type": "exclude_at_match",
        "name": "exclude_debug",
        "pattern": "DEBUG"
      }
    ]
```

**Use cases:**
- Filter out health check logs
- Remove debug logs in production
- Exclude noisy endpoints

#### B. Include Only Matching Logs (include_at_match)
```yaml
- name: DD_LOGS_CONFIG_PROCESSING_RULES
  value: |
    [
      {
        "type": "include_at_match",
        "name": "include_errors_only",
        "pattern": "(ERROR|FATAL|CRITICAL)"
      }
    ]
```

**Use cases:**
- Collect only errors in specific environments
- Focus on critical logs

#### C. Mask Sensitive Data (mask_sequences)
```yaml
- name: DD_LOGS_CONFIG_PROCESSING_RULES
  value: |
    [
      {
        "type": "mask_sequences",
        "name": "mask_credit_cards",
        "replace_placeholder": "[CARD_REDACTED]",
        "pattern": "\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}"
      },
      {
        "type": "mask_sequences",
        "name": "mask_emails",
        "replace_placeholder": "[EMAIL_REDACTED]",
        "pattern": "\\w+@\\w+\\.\\w+"
      },
      {
        "type": "mask_sequences",
        "name": "mask_api_keys",
        "replace_placeholder": "[API_KEY_REDACTED]",
        "pattern": "api[_-]?key[\":\\s]+[a-zA-Z0-9]{32,}"
      }
    ]
```

**Use cases:**
- Redact credit card numbers
- Mask email addresses
- Hide API keys and secrets
- Comply with GDPR/PCI-DSS

### 6. Per-Container Log Processing (Pod Annotations)

Instead of global rules, apply processing rules to specific containers:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
  annotations:
    ad.datadoghq.com/app.logs: |
      [{
        "source": "nodejs",
        "service": "my-app",
        "auto_multi_line_detection": true,
        "log_processing_rules": [
          {
            "type": "exclude_at_match",
            "name": "exclude_healthcheck",
            "pattern": "GET /health"
          },
          {
            "type": "mask_sequences",
            "name": "mask_user_ids",
            "replace_placeholder": "[USER_ID]",
            "pattern": "user_id=\\d+"
          }
        ]
      }]
```

**Benefits:**
- Fine-grained control per container
- Different rules for different services
- Override global rules

### 7. File Wildcard Selection Mode

**Configuration:**
```yaml
env:
  - name: DD_LOGS_CONFIG_FILE_WILDCARD_SELECTION_MODE
    value: "by_modification_time"
```

**Options:**
- `by_name` (default): Tail files by alphabetical order
- `by_modification_time`: Tail most recently modified files first

**Use case:**
- Prioritize active log files
- Useful when hitting `open_files_limit`

### 8. Log Collection from Specific Paths

**Configuration:**
```yaml
env:
  - name: DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL
    value: "false"
  - name: DD_LOGS_CONFIG_LOGS_DD_URL
    value: "https://http-intake.logs.us5.datadoghq.com:443"
```

For custom log paths, use Autodiscovery annotations.

### 9. Compression

**Configuration:**
```yaml
env:
  - name: DD_LOGS_CONFIG_USE_COMPRESSION
    value: "true"
  - name: DD_LOGS_CONFIG_COMPRESSION_LEVEL
    value: "6"  # 1-9, higher = more compression
```

**What it does:**
- Compresses logs before sending to Datadog
- Reduces network bandwidth usage
- Slight increase in CPU usage

**Recommended:**
- Enable in high-volume environments
- Use level 6 (balance between compression and CPU)

### 10. Batch Settings

**Configuration:**
```yaml
env:
  - name: DD_LOGS_CONFIG_BATCH_WAIT
    value: "5"  # seconds
  - name: DD_LOGS_CONFIG_BATCH_MAX_SIZE
    value: "1000"  # number of logs
  - name: DD_LOGS_CONFIG_BATCH_MAX_CONTENT_SIZE
    value: "5242880"  # bytes (5MB)
```

**What it does:**
- Batches logs before sending to reduce API calls
- Improves throughput

**Tuning:**
- Decrease batch wait for real-time requirements
- Increase for high-volume, non-critical logs

## Feature Comparison Matrix

| Feature | Enabled | Performance Impact | Use Case | Configuration Level |
|---------|---------|-------------------|----------|---------------------|
| Auto Multi-Line | ✅ Yes | Low | Stack traces, JSON logs | Global |
| File-Based Collection | ✅ Yes | Improves performance | Production environments | Global |
| Open Files Limit | ✅ Yes (500) | Controls memory | High container density | Global |
| Namespace Filtering | ✅ Yes | Reduces volume | Cost optimization | Global |
| Processing Rules | ❌ No | Low | Sensitive data, filtering | Global or Pod |
| Compression | ❌ No | Slight CPU increase | High volume | Global |
| Batch Settings | ❌ No (defaults) | Improves throughput | High volume | Global |

## Common Configuration Patterns

### Pattern 1: Production Setup (High Volume)

```yaml
logs:
  enabled: true
  containerCollectAll: false
  autoMultiLineDetection: true

env:
  - name: DD_LOGS_CONFIG_K8S_CONTAINER_USE_FILE
    value: "true"
  - name: DD_LOGS_CONFIG_OPEN_FILES_LIMIT
    value: "1000"
  - name: DD_LOGS_CONFIG_USE_COMPRESSION
    value: "true"
  - name: DD_LOGS_CONFIG_COMPRESSION_LEVEL
    value: "6"
  - name: DD_LOGS_CONFIG_BATCH_MAX_SIZE
    value: "1000"
```

### Pattern 2: Security & Compliance

```yaml
logs:
  enabled: true
  autoMultiLineDetection: true

env:
  - name: DD_LOGS_CONFIG_PROCESSING_RULES
    value: |
      [
        {
          "type": "mask_sequences",
          "name": "mask_credit_cards",
          "replace_placeholder": "[CARD]",
          "pattern": "\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}"
        },
        {
          "type": "mask_sequences",
          "name": "mask_ssn",
          "replace_placeholder": "[SSN]",
          "pattern": "\\d{3}-\\d{2}-\\d{4}"
        }
      ]
```

### Pattern 3: Cost Optimization

```yaml
logs:
  enabled: true
  containerCollectAll: false

containerIncludeLogs: "kube_namespace:production kube_namespace:staging"

env:
  - name: DD_LOGS_CONFIG_PROCESSING_RULES
    value: |
      [
        {
          "type": "exclude_at_match",
          "name": "exclude_healthcheck",
          "pattern": "(GET|POST) /(health|ready|live)"
        },
        {
          "type": "exclude_at_match",
          "name": "exclude_debug",
          "pattern": "\\[DEBUG\\]"
        }
      ]
```

## Monitoring and Verification

### Check Agent Status

```bash
# Get agent pod
kubectl get pods -n datadog

# Check agent status
kubectl exec -n datadog -it <datadog-agent-pod> -- agent status

# Check logs configuration
kubectl exec -n datadog -it <datadog-agent-pod> -- agent config | grep -A 20 logs_config
```

### Verify Features in Datadog

1. **Multi-line logs:**
   - Search: `service:your-service`
   - Look for stack traces as single events

2. **Processing rules:**
   - Search for patterns you excluded
   - Verify they don't appear

3. **Masked data:**
   - Search for `[CARD_REDACTED]` or your placeholder
   - Verify sensitive data is redacted

### Performance Metrics

Monitor these metrics in Datadog:

```
# Agent log collection rate
datadog.agent.logs.sent

# Agent CPU usage
system.cpu.usage{process:datadog-agent}

# Agent memory usage
system.mem.used{process:datadog-agent}

# Files being tailed
datadog.agent.logs.files_tailed
```

## Troubleshooting

### Issue: Logs not appearing

**Check:**
1. Namespace is included in `containerIncludeLogs`
2. Pods have proper annotations
3. Agent status shows log collection is active

```bash
kubectl exec -n datadog -it <agent-pod> -- agent status | grep -A 20 "Logs Agent"
```

### Issue: Multi-line logs split

**Solutions:**
1. Verify `autoMultiLineDetection: true`
2. Add per-container annotation:
   ```yaml
   ad.datadoghq.com/container.logs: '[{"auto_multi_line_detection": true}]'
   ```

### Issue: Too many files warning

**Solution:**
Increase `DD_LOGS_CONFIG_OPEN_FILES_LIMIT`:
```yaml
- name: DD_LOGS_CONFIG_OPEN_FILES_LIMIT
  value: "1000"
```

## Best Practices

1. **Always enable auto multi-line detection** for stack traces
2. **Use file-based collection** in production
3. **Set appropriate open files limit** based on container count
4. **Use namespace filtering** to reduce costs
5. **Mask sensitive data** at the agent level
6. **Monitor agent performance** and adjust settings
7. **Test processing rules** in non-production first
8. **Use compression** for high-volume environments

## Reference Documentation

- [Kubernetes Log Collection](https://docs.datadoghq.com/containers/kubernetes/log/)
- [Auto Multi-Line Detection](https://docs.datadoghq.com/agent/logs/auto_multiline_detection/)
- [Advanced Log Collection](https://docs.datadoghq.com/agent/logs/advanced_log_collection/)
- [Log Data Security](https://docs.datadoghq.com/data_security/logs/)
- [Datadog Helm Chart Values](https://github.com/DataDog/helm-charts/tree/main/charts/datadog)

## Updates

To apply configuration changes:

```bash
# Update values
vim datadog-values.yaml

# Upgrade Helm release
helm upgrade datadog -f datadog-values.yaml datadog/datadog -n datadog

# Verify rollout
kubectl rollout status daemonset/datadog -n datadog
```
