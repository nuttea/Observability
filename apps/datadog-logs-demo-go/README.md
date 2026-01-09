# Datadog Logs Demo Application (Go)

A comprehensive Go application that generates various types of structured logs to demonstrate Datadog logging capabilities and features.

## Features

This application generates logs for the following use cases:

### 1. Business KPI Metrics
Generates logs for tracking business metrics and creating KPI dashboards:
- **Revenue tracking** - Total revenue, order count, average order value
- **Conversion rates** - Customer segment conversion metrics
- **Regional performance** - Revenue by region
- **Payment methods** - Transaction breakdown by payment type

**Datadog Use Cases:**
- Create custom metrics from logs using `Generate Metrics` feature
- Build business KPI dashboards
- Set up monitors for revenue thresholds
- Track conversion rates by customer segment

### 2. Transaction Logs
Generates payment transaction logs for financial monitoring:
- **Transaction values** - Amount, currency, payment gateway
- **Success/Failure rates** - Transaction status tracking
- **Risk scores** - Fraud detection scores
- **Processing duration** - Transaction latency

**Datadog Use Cases:**
- Calculate transaction success rate: `count(status:success) / count(*)`
- Monitor payment gateway performance
- Alert on high failure rates
- Track transaction volume by gateway

### 3. Error and Warning Logs
Generates error logs for monitoring and alerting:
- **Error types** - Validation, database, API, timeout errors
- **Error codes** - Structured error codes for categorization
- **Stack traces** - Debug information
- **Retry counts** - Failure retry attempts

**Datadog Use Cases:**
- Set up error rate monitors
- Alert on error spikes
- Create error distribution analytics
- Track errors by service and endpoint

### 4. Performance Metrics
Generates performance-related logs for latency and throughput monitoring:
- **Latency** - Response time in milliseconds
- **Throughput** - Requests per second
- **Resource usage** - CPU, memory utilization
- **Cache hit rates** - Caching performance

**Datadog Use Cases:**
- Calculate p50, p95, p99 latency percentiles
- Create distribution widgets for response times
- Monitor resource utilization trends
- Alert on performance degradation

### 5. User Activity Logs
Generates user behavior and engagement logs:
- **Activity types** - Page views, clicks, searches, checkouts
- **Session tracking** - User sessions and duration
- **Device analytics** - Device type, browser, country
- **A/B testing** - Test variant tracking

**Datadog Use Cases:**
- Analyze user engagement by activity type
- Track session duration distribution
- Compare A/B test variant performance
- Monitor user journey funnels

### 6. API Request Logs
Generates API usage logs for monitoring and rate limiting:
- **HTTP methods** - GET, POST, PUT, DELETE, PATCH
- **Status codes** - Success and error codes
- **Request/Response sizes** - Payload sizes
- **Rate limiting** - API quota tracking

**Datadog Use Cases:**
- Monitor API endpoint performance
- Track rate limit consumption
- Alert on 4xx/5xx error rates
- Analyze API usage patterns

### 7. Payment Processing Logs
Generates payment-specific logs for fraud detection:
- **Payment amounts** - Transaction values
- **Fraud scores** - Risk assessment scores
- **3DS verification** - Security verification status
- **Card types** - Payment card brands

**Datadog Use Cases:**
- Detect fraudulent transactions with high risk scores
- Monitor payment processor performance
- Track chargeback rates
- Alert on blocked payments

### 8. Security Event Logs
Generates security and compliance logs:
- **Authentication events** - Login success/failure
- **Access control** - Permission changes, access denied
- **Audit trails** - Security event tracking
- **Failed login attempts** - Brute force detection

**Datadog Use Cases:**
- Monitor failed login attempts
- Alert on multiple failed authentications
- Track security events by user and IP
- Compliance and audit reporting

## Log Structure

All logs are generated in JSON format for easy parsing by Datadog:

```json
{
  "level": "info",
  "msg": "Transaction completed successfully",
  "event_type": "transaction",
  "transaction_id": "TXN_ABC123",
  "transaction_value": 149.99,
  "transaction_status": "success",
  "duration_ms": 450,
  "payment_gateway": "stripe",
  "currency": "USD",
  "country": "US",
  "risk_score": 25.5,
  "merchant_id": "MER_XYZ789",
  "time": "2024-01-09T10:30:00Z"
}
```

## Multi-Namespace Deployment

This application can be deployed to multiple namespaces with different tags to demonstrate:
- Namespace-level tag inheritance
- Environment separation (development vs staging)
- Team-based organization
- Cost center tracking
- Compliance tagging

See the [Deployment Guide](DEPLOYMENT_GUIDE.md) for detailed instructions on deploying to both `datadog-test-a` and `datadog-test-b` namespaces.

### Quick Multi-Namespace Deployment

```bash
# Deploy to both namespaces at once
make k8s-deploy-all

# Check status of both deployments
make k8s-status-all

# View logs from each namespace
make k8s-logs-a  # datadog-test-a
make k8s-logs-b  # datadog-test-b
```

**Tag Differences:**

| Namespace | Environment | Team | Cost Center | Compliance |
|-----------|-------------|------|-------------|------------|
| datadog-test-a | development | platform-engineering | engineering | sox |
| datadog-test-b | staging | application-team | product | pci-dss |

See [Tags Reference](TAGS_REFERENCE.md) for complete tag comparison.

## Building and Running

### Local Development

```bash
# Install dependencies
go mod download

# Run the application
go run main.go
```

### Docker Build

```bash
# Build the Docker image
docker build -t datadog-logs-demo:latest .

# Run the container
docker run datadog-logs-demo:latest
```

### Kubernetes Deployment

```bash
# Create namespaces
kubectl apply -f k8s/namespace.yaml

# Deploy the application
kubectl apply -f k8s/deployment.yaml

# Verify deployment
kubectl get pods -n datadog-test-a
```

## Datadog Configuration Examples

### 1. Creating Custom Metrics from Logs

In Datadog, navigate to **Logs → Generate Metrics** and create metrics:

**Revenue Metric:**
- Query: `event_type:business_kpi`
- Metric name: `business.revenue`
- Measure: `@revenue` (SUM)
- Group by: `@region`, `@payment_method`

**Order Count Metric:**
- Query: `event_type:order_completed`
- Metric name: `business.orders.count`
- Measure: Count (*)
- Group by: `@customer_type`

**Transaction Success Rate:**
- Query: `event_type:transaction transaction_status:success`
- Metric name: `transaction.success.count`
- Measure: Count (*)
- Group by: `@payment_gateway`

### 2. Log Analytics Queries

**Calculate Average Order Value by Region:**
```
event_type:business_kpi |
measure @revenue by @region |
timeseries avg(@revenue)
```

**P95 API Latency:**
```
event_type:api_request |
measure @duration_ms |
p95(@duration_ms)
```

**Error Rate by Service:**
```
level:error |
count by @service |
timeseries
```

**Fraud Score Distribution:**
```
event_type:payment_processing |
measure @fraud_score |
distribution
```

### 3. Creating Monitors and Alerts

**High Error Rate Alert:**
- Type: Log Monitor
- Query: `level:error`
- Alert threshold: `> 50` errors in 5 minutes
- Group by: `@service`, `@endpoint`

**Payment Fraud Alert:**
- Type: Log Monitor
- Query: `event_type:fraud_alert fraud_score:>80`
- Alert threshold: `> 5` high-risk payments in 10 minutes

**Transaction Failure Rate Alert:**
- Type: Log Monitor
- Query: `event_type:transaction transaction_status:failed`
- Alert threshold: Failure rate `> 10%` over 5 minutes

**API Latency Alert:**
- Type: Log Monitor
- Query: `event_type:api_request`
- Alert threshold: p95(@duration_ms) `> 1000ms` over 10 minutes

### 4. Sampling Configuration

In Datadog, configure log sampling using **Logs → Indexes**:

**Keep All Critical Logs:**
- Query: `level:error OR level:warn OR event_type:fraud_alert`
- Sample rate: 100%

**Sample Debug Logs:**
- Query: `level:info event_type:user_activity`
- Sample rate: 10%

**Exclude Noisy Logs:**
- Query: `event_type:performance status_code:200`
- Sample rate: 5%

### 5. Building Dashboards

**Business KPI Dashboard Widgets:**

1. **Total Revenue Timeseries:**
   - Widget: Timeseries
   - Query: `event_type:business_kpi | sum:@revenue`
   - Group by: `@region`

2. **Order Count by Customer Segment:**
   - Widget: Top List
   - Query: `event_type:order_completed | count by @customer_type`

3. **Conversion Rate:**
   - Widget: Query Value
   - Formula: `(count(event_type:order_completed) / count(event_type:user_activity activity_type:page_view)) * 100`

4. **Average Order Value:**
   - Widget: Query Value
   - Query: `event_type:order_completed | avg:@order_value`

**Performance Dashboard Widgets:**

1. **API Latency Percentiles:**
   - Widget: Timeseries
   - Queries:
     - `event_type:api_request | p50:@duration_ms`
     - `event_type:api_request | p95:@duration_ms`
     - `event_type:api_request | p99:@duration_ms`

2. **API Status Code Distribution:**
   - Widget: Pie Chart
   - Query: `event_type:api_request | count by @status_code`

3. **Throughput by Endpoint:**
   - Widget: Timeseries
   - Query: `event_type:api_request | count by @endpoint`

### 6. Facet Configuration

Configure facets in Datadog Log Explorer for filtering and analytics:

**String Facets:**
- `@event_type` - Type of log event
- `@service` - Service name
- `@endpoint` - API endpoint
- `@payment_gateway` - Payment provider
- `@customer_segment` - Customer type
- `@region` - Geographic region
- `@fraud_status` - Fraud risk level

**Numeric Facets (Measures):**
- `@revenue` - Revenue amount
- `@transaction_value` - Transaction amount
- `@duration_ms` - Request/transaction duration
- `@fraud_score` - Fraud risk score (0-100)
- `@order_count` - Number of orders
- `@latency_ms` - API latency

**Boolean Facets:**
- `@3ds_verified` - 3D Secure verification status

## Log Event Types Reference

| Event Type | Description | Key Fields | Use Case |
|------------|-------------|------------|----------|
| `business_kpi` | Business metrics | revenue, order_count, conversion_rate | Revenue dashboards, KPI tracking |
| `order_completed` | Order completion | order_value, customer_type, product_count | Order analytics, customer segmentation |
| `transaction` | Payment transactions | transaction_value, status, duration_ms | Transaction monitoring, success rate |
| `error` | Application errors | error_type, error_code, severity | Error tracking, alerting |
| `performance` | Performance metrics | latency_ms, throughput_rps, cpu_usage | Performance monitoring, SLOs |
| `user_activity` | User actions | activity_type, session_id, device_type | User analytics, engagement |
| `api_request` | API calls | method, endpoint, status_code | API monitoring, rate limiting |
| `payment_processing` | Payment processing | amount, fraud_score, payment_method | Fraud detection, payment analytics |
| `security_event` | Security events | security_event, user_id, ip_address | Security monitoring, compliance |
| `fraud_alert` | Fraud detection | fraud_score, alert_level | Fraud prevention, risk management |

## Environment Variables

The application supports the following environment variables:

- `DD_ENV` - Environment name (injected from pod labels)
- `DD_SERVICE` - Service name (injected from pod labels)
- `DD_VERSION` - Application version (injected from pod labels)

## Logs Rotation

Logs are generated every 5 seconds, cycling through all 8 event types. Each cycle takes approximately 40 seconds.

## Resource Requirements

- **CPU**: 100m (request), 200m (limit)
- **Memory**: 64Mi (request), 128Mi (limit)
- **Replicas**: 2 (default)

## Tags Applied

The application has the following tags configured:

**Global Tags (from Datadog Agent):**
- `env:dev`

**Pod Labels:**
- `service:logs-demo`
- `env:development`
- `version:1.0.0`

**Autodiscovery Annotations:**
- `application:logs-demo`
- `team:platform`
- `component:demo`
- `source:golang`

## Reference Documentation

- [Datadog Go Log Collection](https://docs.datadoghq.com/logs/log_collection/go/)
- [Log-based Metrics](https://docs.datadoghq.com/logs/logs_to_metrics/)
- [Log Analytics](https://docs.datadoghq.com/logs/explorer/analytics/)
- [Log Monitors](https://docs.datadoghq.com/monitors/types/log/)
- [Log Sampling](https://docs.datadoghq.com/logs/indexes/#sampling)
- [Datadog Dashboards](https://docs.datadoghq.com/dashboards/)

## Directory Structure

```
datadog-logs-demo-go/
├── main.go                    # Main application with 8 log generators
├── go.mod                     # Go module definition
├── go.sum                     # Go dependencies checksums
├── Dockerfile                 # Multi-stage Docker build
├── .dockerignore              # Docker ignore patterns
├── .gitignore                 # Git ignore patterns
├── Makefile                   # Build and deployment automation
├── README.md                  # This file (comprehensive feature documentation)
├── QUICKSTART.md              # Quick start guide
├── DEPLOYMENT_GUIDE.md        # Multi-namespace deployment guide
├── TAGS_REFERENCE.md          # Tags reference and comparison
└── k8s/
    ├── namespace.yaml         # Namespace definitions with tags
    ├── deployment.yaml        # Original deployment (deprecated)
    ├── deployment-test-a.yaml # Deployment for datadog-test-a namespace
    └── deployment-test-b.yaml # Deployment for datadog-test-b namespace
```

## License

This is a demonstration application for Datadog logging capabilities.
