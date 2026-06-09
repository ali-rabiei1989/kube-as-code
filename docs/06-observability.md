# 06 - Observability

This document explains the observability components used in the Kubernetes lab.

The lab implements a metrics pipeline that supports both operational visibility and custom-metrics-based autoscaling.

The observability stack includes:

```text
Metrics Server
Prometheus
nginx-prometheus-exporter
Prometheus Adapter
Kubernetes Metrics APIs
```

---

## 1. Observability Goals

The observability design has four main goals:

```text
1. Provide basic node and Pod resource metrics.
2. Collect application-level metrics from the sample web application.
3. Expose selected Prometheus metrics to Kubernetes through the Custom Metrics API.
4. Support HPA scaling based on application request rate.
```

The lab intentionally keeps the stack lightweight.  
It does not deploy a full production monitoring platform such as kube-prometheus-stack, Grafana, Alertmanager, or long-term remote storage.

---

## 2. Component Overview

| Component | Purpose |
|---|---|
| Metrics Server | Provides CPU and memory metrics through `metrics.k8s.io` |
| Prometheus | Scrapes and stores time-series metrics |
| nginx-prometheus-exporter | Converts Nginx `stub_status` data to Prometheus metrics |
| Prometheus Adapter | Exposes selected Prometheus metrics through `custom.metrics.k8s.io` |
| HPA | Consumes metrics and scales the sample application |

High-level flow:

```text
Resource Metrics:
kubelet/cAdvisor
   |
   v
Metrics Server
   |
   v
metrics.k8s.io
   |
   v
kubectl top / CPU-Memory HPA


Application Metrics:
Nginx stub_status
   |
   v
nginx-prometheus-exporter
   |
   v
Prometheus
   |
   v
Prometheus Adapter
   |
   v
custom.metrics.k8s.io
   |
   v
HPA custom metrics
```

---

## 3. Metrics Server

Metrics Server is responsible for resource metrics.

It collects CPU and memory usage from kubelets and exposes them through:

```text
metrics.k8s.io
```

This API is used by:

```text
kubectl top nodes
kubectl top pods
CPU/Memory-based HPA
```
---

## 4. Verify Metrics Server

Check the Metrics Server Pod:

```bash
kubectl get pods -n kube-system | grep metrics-server
```

Check the APIService:

```bash
kubectl get apiservice v1beta1.metrics.k8s.io
```

Expected:

```text
AVAILABLE=True
```

Check node resource metrics:

```bash
kubectl top nodes
```

Check Pod resource metrics:

```bash
kubectl top pods -A
```

If metrics are not immediately available after installation, wait one or two collection intervals and retry.

---

## 5. Prometheus

Prometheus is used for application and platform metrics.

In this lab, Prometheus is deployed using the `prometheus-community/prometheus` Helm chart.  
It is intentionally configured in a lightweight mode.

The following components are disabled:

```text
Alertmanager
kube-state-metrics
node-exporter
pushgateway
```

This keeps the lab smaller and focused on the custom metrics path.

---

## 6. Prometheus Deployment

Prometheus runs in:

```text
Namespace: monitoring
Service: prometheus-server
```

Check Prometheus:

```bash
kubectl get pods -n monitoring | grep prometheus-server
kubectl get svc -n monitoring prometheus-server
```

Expected Pod state:

```text
2/2 Running
```

The two containers are typically:

```text
prometheus-server
prometheus-server-configmap-reload
```

---

## 7. Prometheus Configuration

Prometheus scrapes the sample application metrics from the internal metrics Service:

```text
k8s-lab-sample-webapp-metrics.demo.svc.cluster.local:9113/metrics
```

The scrape job is named:

```text
sample-webapp
```

The scrape job adds labels that are required by Prometheus Adapter:

```text
namespace=demo
service=k8s-lab-sample-webapp
```

Example scrape target:

```yaml
- job_name: sample-webapp
  metrics_path: /metrics
  static_configs:
    - targets:
        - k8s-lab-sample-webapp-metrics.demo.svc.cluster.local:9113
      labels:
        namespace: demo
        service: k8s-lab-sample-webapp
```

These labels are important because the Adapter maps the Prometheus series to Kubernetes objects.

---

## 8. Prometheus Scrape Interval

The lab uses a relatively short scrape interval to make HPA testing more responsive:

```text
scrape_interval: 15s
evaluation_interval: 15s
```

This is useful for a lab because scale-up and scale-down behavior can be observed faster.

For production, a more conservative interval may be preferred:

```text
30s or 60s depending on workload, scale sensitivity, and monitoring cost
```

---

## 9. Application Metrics Export

Nginx does not expose Prometheus metrics directly.

The application Pod uses a sidecar pattern:

```text
Nginx container
   |
   v
127.0.0.1:8080/stub_status
   |
   v
nginx-prometheus-exporter sidecar
   |
   v
:9113/metrics
```

The exporter exposes metrics such as:

```text
nginx_http_requests_total
nginx_connections_active
nginx_connections_reading
nginx_connections_writing
nginx_connections_waiting
```

The most important metric for HPA is:

```text
nginx_http_requests_total
```

This is a counter.  
It always increases and should not be used directly for autoscaling.

For autoscaling, it is converted into a request rate using PromQL:

```promql
sum(rate(nginx_http_requests_total{namespace="demo",service="k8s-lab-sample-webapp"}[2m]))
```

---

## 10. Verify Application Metrics Directly

Check the metrics Service:

```bash
kubectl get svc -n demo k8s-lab-sample-webapp-metrics -o wide
```

Query the exporter directly through ClusterIP:

```bash
METRICS_IP=$(kubectl -n demo get svc k8s-lab-sample-webapp-metrics -o jsonpath='{.spec.clusterIP}')

curl -s http://${METRICS_IP}:9113/metrics | grep nginx_http_requests_total
```

Expected:

```text
nginx_http_requests_total
```

---

## 11. Verify Prometheus Target

Get the Prometheus ClusterIP:

```bash
PROM_IP=$(kubectl -n monitoring get svc prometheus-server -o jsonpath='{.spec.clusterIP}')
```

Check the scrape target:

```bash
curl -s "http://${PROM_IP}/api/v1/targets?state=any" | jq '.data.activeTargets[] | select(.labels.job=="sample-webapp") | {job: .labels.job, health: .health, scrapeUrl: .scrapeUrl, lastError: .lastError}'
```

Expected:

```json
{
  "job": "sample-webapp",
  "health": "up",
  "scrapeUrl": "http://k8s-lab-sample-webapp-metrics.demo.svc.cluster.local:9113/metrics",
  "lastError": ""
}
```

If the target is down, check:

```text
- Service DNS name
- metrics Service endpoints
- exporter container logs
- Prometheus config
- Prometheus Pod health
```

---

## 12. Query Prometheus Metrics

Query the raw Nginx request counter:

```bash
curl -s "http://${PROM_IP}/api/v1/query?query=nginx_http_requests_total" | jq
```

Query request rate:

```bash
curl -s "http://${PROM_IP}/api/v1/query?query=sum%28rate%28nginx_http_requests_total%7Bnamespace%3D%22demo%22%2Cservice%3D%22k8s-lab-sample-webapp%22%7D%5B2m%5D%29%29" | jq
```

Expected:

```text
status: success
result: non-empty when enough samples exist
```

If the rate query is empty, wait for Prometheus to collect enough samples.

For a `2m` rate window, Prometheus needs enough scrape samples in that time range.

---

## 13. Why Rate Is Used Instead of Counter Value

The metric:

```text
nginx_http_requests_total
```

is a counter.

A counter only increases.  
Using the raw counter value for HPA would be wrong because the value would never naturally go down.

Instead, HPA should use a rate:

```promql
rate(nginx_http_requests_total[2m])
```

This gives request rate over time.

Prometheus Adapter exposes that rate as:

```text
nginx_http_requests_per_second
```

---

## 14. Prometheus Adapter

Prometheus Adapter connects Prometheus to Kubernetes Custom Metrics API.

HPA does not query Prometheus directly.  
It reads metrics from Kubernetes APIs.

For custom metrics, the path is:

```text
HPA
   |
   v
custom.metrics.k8s.io
   |
   v
Prometheus Adapter
   |
   v
Prometheus
```

Prometheus Adapter maps selected Prometheus metrics to Kubernetes objects.

In this lab, it maps:

```text
nginx_http_requests_total
```

to:

```text
nginx_http_requests_per_second
```

---

## 15. Adapter Rule

The Adapter uses a rule similar to this:

```yaml
rules:
  default: false
  custom:
    - seriesQuery: 'nginx_http_requests_total{namespace!="",service!=""}'
      resources:
        overrides:
          namespace:
            resource: namespace
          service:
            resource: service
      name:
        matches: "^nginx_http_requests_total$"
        as: "nginx_http_requests_per_second"
      metricsQuery: 'sum(rate(<<.Series>>{<<.LabelMatchers>>}[2m])) by (<<.GroupBy>>)'
```

This means:

```text
Find nginx_http_requests_total series with namespace and service labels.
Map namespace label to Kubernetes Namespace.
Map service label to Kubernetes Service.
Expose the metric as nginx_http_requests_per_second.
Calculate the value using rate over a 2-minute window.
```

---

## 16. Adapter Timing Parameters

The lab uses relatively responsive Adapter settings:

```text
metrics-relist-interval: 30s
metrics-max-age: 2m
```

Meaning:

```text
metrics-relist-interval:
How often the Adapter refreshes its list of available metrics.

metrics-max-age:
How far back the Adapter looks when deciding whether a metric series still exists.
```

The max age should be larger than the scrape interval and large enough to avoid metrics disappearing temporarily.

Current lab design:

```text
Prometheus scrape interval: 15s
Adapter relist interval: 30s
Adapter max age: 2m
PromQL rate window: 2m
```

This is fast enough for a lab while keeping the metric stable.

---

## 17. Verify Prometheus Adapter

Check Adapter Pod:

```bash
kubectl get pods -n monitoring | grep prometheus-adapter
```

Check APIService:

```bash
kubectl get apiservice v1beta1.custom.metrics.k8s.io
```

Expected:

```text
AVAILABLE=True
```

List custom metrics:

```bash
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq
```

Expected resource:

```text
services/nginx_http_requests_per_second
```

Query the metric for the sample application Service:

```bash
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1/namespaces/demo/services/k8s-lab-sample-webapp/nginx_http_requests_per_second | jq
```

Expected:

```text
kind: MetricValueList
items: non-empty
```

---

## 18. HPA Metrics Path

The HPA consumes:

```text
nginx_http_requests_per_second
```

from:

```text
custom.metrics.k8s.io
```

The metric is attached to:

```text
Service/k8s-lab-sample-webapp
```

The HPA target uses:

```text
type: Object
target: AverageValue
```

Detailed HPA behavior is documented in:

```text
docs/07-hpa-custom-metrics.md
```

---

## 19. Useful Queries

### Raw request counter

```promql
nginx_http_requests_total
```

### Request rate for the sample Service

```promql
sum(rate(nginx_http_requests_total{namespace="demo",service="k8s-lab-sample-webapp"}[2m]))
```

### Active Nginx connections

```promql
nginx_connections_active
```

### Waiting connections

```promql
nginx_connections_waiting
```

### Prometheus target health

```promql
up{job="sample-webapp"}
```

---

## 20. Common Failure Modes

### Prometheus Pod is CrashLoopBackOff

Check logs:

```bash
kubectl -n monitoring logs deploy/prometheus-server -c prometheus-server --tail=100
```

Common causes:

```text
invalid prometheus.yml
duplicate job names
duplicate global section
unsupported field in config
```

### Prometheus target is down

Check target status:

```bash
curl -s "http://${PROM_IP}/api/v1/targets?state=any" | jq '.data.activeTargets[] | select(.labels.job=="sample-webapp")'
```

Common causes:

```text
wrong Service DNS name
metrics Service has no endpoints
exporter container not ready
network policy blocking traffic
```

### Custom metric is not visible

Check APIService:

```bash
kubectl get apiservice v1beta1.custom.metrics.k8s.io
```

Check metric list:

```bash
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq
```

Common causes:

```text
Adapter rule mismatch
missing namespace/service labels
Prometheus query returns empty result
Adapter cache not refreshed yet
metrics-max-age too short
```

### HPA shows `<unknown>`

Check direct custom metric query:

```bash
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1/namespaces/demo/services/k8s-lab-sample-webapp/nginx_http_requests_per_second | jq
```

If this works but HPA still shows `<unknown>`, check HPA manifest and controller events.

---

## 21. Logging

Prometheus logs:

```bash
kubectl logs -n monitoring deploy/prometheus-server -c prometheus-server --tail=100
```

Prometheus Adapter logs:

```bash
kubectl logs -n monitoring deploy/prometheus-adapter --tail=100
```

Exporter logs:

```bash
kubectl logs -n demo deploy/k8s-lab-sample-webapp -c nginx-exporter --tail=100
```

Nginx logs:

```bash
kubectl logs -n demo deploy/k8s-lab-sample-webapp -c nginx --tail=100
```

---

## 22. Security Considerations

The metrics endpoint is internal only.

```text
Public application Service:
k8s-lab-sample-webapp
LoadBalancer
192.168.200.240:80

Internal metrics Service:
k8s-lab-sample-webapp-metrics
ClusterIP
:9113
```

This prevents exposing operational metrics directly to external users.

For production:

```text
Use NetworkPolicies to restrict Prometheus access to metrics endpoints.
Protect Prometheus UI and API with authentication.
Use TLS where appropriate.
Avoid exposing metrics endpoints through public load balancers.
Use centralized logging and alerting.
Use persistent or remote storage for Prometheus.
```

---

## 23. Summary

The observability design provides two metric paths:

```text
Resource metrics:
kubelet -> Metrics Server -> metrics.k8s.io

Application custom metrics:
Nginx -> nginx-exporter -> Prometheus -> Prometheus Adapter -> custom.metrics.k8s.io
```

This allows the lab to demonstrate both standard Kubernetes metrics and custom application-level autoscaling metrics.
