# Keycloak Metrics for Prometheus

This document describes the metrics capabilities of Keycloak and how
they integrate with Prometheus in the CC cluster.

## Overview

Keycloak exposes comprehensive metrics through its `/metrics` endpoint
when metrics are enabled. The chart automatically configures:

- Metrics endpoint at `/metrics` on port 8080
- ServiceMonitor resource for Prometheus Operator
- Automatic discovery by Prometheus

## Metrics Endpoint

### Endpoint Configuration

```yaml
# Enabled by default in values.yaml
keycloak:
  metricsEnabled: true
```

Access metrics:

```bash
# Via port-forward
kubectl port-forward svc/keycloak 8080:8080
curl http://localhost:8080/metrics

# From within cluster
curl http://keycloak.oidc.svc.cluster.local:8080/metrics
```

## Available Metrics

Keycloak exposes the following categories of metrics:

### JVM Metrics

- **Memory Usage**
  - `jvm_memory_used_bytes` - Current memory usage
  - `jvm_memory_max_bytes` - Maximum memory
  - `jvm_memory_committed_bytes` - Committed memory
  - Breakdown by heap/non-heap, old gen, young gen, etc.

- **Garbage Collection**
  - `jvm_gc_collection_seconds` - GC pause times
  - `jvm_gc_memory_allocated_bytes_total` - Memory allocated
  - `jvm_gc_memory_promoted_bytes_total` - Memory promoted to old gen

- **Thread Metrics**
  - `jvm_threads_live_threads` - Active thread count
  - `jvm_threads_daemon_threads` - Daemon thread count
  - `jvm_threads_peak_threads` - Peak thread count
  - `jvm_threads_states_threads` - Threads by state

- **Class Loading**
  - `jvm_classes_loaded_classes` - Currently loaded classes
  - `jvm_classes_unloaded_classes_total` - Total unloaded classes

### HTTP Metrics

- **Request Metrics**
  - `http_server_requests_seconds` - HTTP request duration
  - Labels: method, uri, status, outcome
  - Useful for tracking endpoint performance

- **Connection Metrics**
  - `http_server_connections_seconds` - Connection duration
  - Active connection tracking

### Database Metrics

- **Connection Pool**
  - `hikaricp_connections_active` - Active DB connections
  - `hikaricp_connections_idle` - Idle DB connections
  - `hikaricp_connections_pending` - Pending connection requests
  - `hikaricp_connections_timeout_total` - Connection timeouts
  - `hikaricp_connections_creation_seconds` - Time to create connections

### Keycloak-Specific Metrics

- **User Sessions**
  - User login/logout events
  - Active session counts
  - Session duration

- **Authentication**
  - Login attempts (success/failure)
  - Token generation
  - Client authentication

- **Cache Metrics**
  - Cache hit/miss rates (Infinispan)
  - Cache size and evictions
  - Cluster synchronization

## Prometheus Integration

### ServiceMonitor Configuration

The chart creates a ServiceMonitor when enabled:

```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 30s
    scrapeTimeout: 10s
    labels: {}  # Additional labels for Prometheus selector
```

### ServiceMonitor Resource

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: keycloak
  labels:
    # Add labels matching Prometheus serviceMonitorSelector
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: keycloak
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
    scrapeTimeout: 10s
```

### CC Cluster Configuration

For the CC cluster, ensure the ServiceMonitor has labels matching your
Prometheus configuration:

```yaml
# Example for CC cluster
monitoring:
  serviceMonitor:
    enabled: true
    interval: 30s
    labels:
      prometheus: kube-prometheus  # Match your Prometheus selector
```

## Prometheus Queries

### Useful PromQL Queries

#### Memory Usage

```promql
# Heap memory usage percentage
(jvm_memory_used_bytes{area="heap"} / jvm_memory_max_bytes{area="heap"}) * 100

# Memory usage by pool
sum by (id) (jvm_memory_used_bytes)
```

#### Request Rate

```promql
# Requests per second
rate(http_server_requests_seconds_count[5m])

# Request rate by endpoint
sum by (uri) (rate(http_server_requests_seconds_count[5m]))

# Error rate (non-2xx responses)
sum(rate(http_server_requests_seconds_count{status!~"2.."}[5m]))
```

#### Response Time

```promql
# Average response time
rate(http_server_requests_seconds_sum[5m]) / rate(http_server_requests_seconds_count[5m])

# 95th percentile response time
histogram_quantile(0.95, rate(http_server_requests_seconds_bucket[5m]))

# Response time by endpoint
sum by (uri) (rate(http_server_requests_seconds_sum[5m])) / sum by (uri) (rate(http_server_requests_seconds_count[5m]))
```

#### Database Connections

```promql
# Active database connections
hikaricp_connections_active

# Connection pool utilization
(hikaricp_connections_active / hikaricp_connections_max) * 100

# Connection wait time
rate(hikaricp_connections_acquire_seconds_sum[5m]) / rate(hikaricp_connections_acquire_seconds_count[5m])
```

#### GC Metrics

```promql
# GC pause time rate
rate(jvm_gc_pause_seconds_sum[5m])

# GC frequency
rate(jvm_gc_pause_seconds_count[5m])
```

#### Thread Pool

```promql
# Thread count by state
sum by (state) (jvm_threads_states_threads)

# Thread pool utilization
jvm_threads_live_threads / jvm_threads_peak_threads
```

## Grafana Dashboards

### Recommended Dashboards

1. **JVM Dashboard**
   - Dashboard ID: 4701 (JVM Micrometer)
   - Shows memory, GC, threads, classes

2. **HTTP Request Dashboard**
   - Custom dashboard tracking request rates, latencies, errors

3. **Database Connection Pool**
   - HikariCP metrics visualization

### Example Dashboard Panels

#### Request Rate Panel

```json
{
  "targets": [{
    "expr": "rate(http_server_requests_seconds_count{job='keycloak'}[5m])"
  }],
  "title": "Request Rate"
}
```

#### Memory Usage Panel

```json
{
  "targets": [{
    "expr": "(jvm_memory_used_bytes{area='heap'} /
              jvm_memory_max_bytes{area='heap'}) * 100"
  }],
  "title": "Heap Memory Usage %"
}
```

## Alerting Rules

The chart includes a PrometheusRule CRD with pre-configured alert rules.
Enable and configure them in your values:

```yaml
monitoring:
  prometheusRule:
    enabled: true
    rules:
      highMemoryThreshold: 90  # Alert when heap > 90%
      highErrorRateThreshold: 0.05  # Alert when error rate > 5%
      slowResponseThreshold: 2  # Alert when p95 latency > 2s
      dbConnectionThreshold: 0.8  # Alert when connections > 80%
      gcFrequencyThreshold: 1  # Alert when GC rate > 1/s
```

### Included Alerts

- **KeycloakHighMemoryUsage**: Heap memory usage above threshold
- **KeycloakHighErrorRate**: HTTP error rate above threshold
- **KeycloakSlowResponseTime**: 95th percentile response time too slow
- **KeycloakDatabaseConnectionIssues**: Connection pool nearly exhausted
- **KeycloakFrequentGC**: Excessive garbage collection activity

The PrometheusRule is created at:
`templates/prometheusrule.yaml`

## Troubleshooting

### Metrics Not Appearing in Prometheus

1. **Check ServiceMonitor labels**

   ```bash
   kubectl get servicemonitor keycloak -o yaml
   ```

   Ensure labels match Prometheus serviceMonitorSelector

2. **Verify Prometheus discovery**

   ```bash
   # Check Prometheus targets
   kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090
   # Visit http://localhost:9090/targets
   ```

3. **Check metrics endpoint**

   ```bash
   kubectl port-forward svc/keycloak 8080:8080
   curl http://localhost:8080/metrics
   ```

### Missing Metrics

If specific metrics are missing:

1. Verify Keycloak metrics are enabled:

   ```bash
   kubectl logs statefulset/keycloak | grep metrics
   ```

2. Check Keycloak configuration:

   ```bash
   kubectl exec keycloak-0 -- curl -s localhost:9000/health
   ```

### High Cardinality Issues

Some Keycloak metrics can have high cardinality (many unique label combinations):

- URI paths with IDs can create many unique metrics
- Consider using metric relabeling to drop or aggregate high-cardinality labels

Example relabel config in Prometheus:

```yaml
metricRelabelings:
  - sourceLabels: [uri]
    regex: '/admin/realms/[^/]+/.*'
    replacement: '/admin/realms/*/...'
    targetLabel: uri
```

## References

- [Keycloak Metrics Documentation](https://www.keycloak.org/server/configuration-metrics)
- [Micrometer Metrics](https://micrometer.io/docs)
- [Prometheus Best Practices](https://prometheus.io/docs/practices/)
- [HikariCP Metrics](https://github.com/brettwooldridge/HikariCP/wiki/Dropwizard-Metrics)
