# 05 - Sample Application

This document explains the sample application deployed in the Kubernetes lab.

The application is intentionally simple, but it is designed to demonstrate several important Kubernetes concepts:

```text
Helm-based deployment
LoadBalancer exposure through MetalLB
Health and readiness probes
Sidecar-based metrics export
Prometheus scraping
Custom metrics for HPA
```

---

## 1. Application Purpose

The sample application is a small Nginx-based web application.

It is used to verify that the cluster can:

```text
- Provide health and readiness endpoints
- Export Nginx metrics through a sidecar
- Feed Prometheus and HPA custom metrics
```

The application is not meant to represent a production business application.  
It is a controlled workload used to validate the Kubernetes platform.

---

## 2. Deployment Method

The application is deployed using a Helm chart located at:

```text
charts/sample-webapp/
```

The chart is copied to the first control-plane node by Ansible and installed using Helm.

The Ansible role responsible for this is:

```text
ansible/roles/sample_app/
```

The application can be deployed or upgraded with:

```bash
cd ansible
ansible-playbook site.yml --tags sample_app
```

---

## 3. Helm Release Naming

The Helm release name is:

```text
k8s-lab
```

The chart name is:

```text
sample-webapp
```

With the standard Helm naming pattern, generated Kubernetes resources are named using:

```text
<release-name>-<chart-name>
```

Therefore, the main application resources use the following names:

```text
Deployment:
k8s-lab-sample-webapp

Main Service:
k8s-lab-sample-webapp

Metrics Service:
k8s-lab-sample-webapp-metrics
```

This naming is preferred over using the same release and chart name, which would produce repetitive names such as:

```text
sample-webapp-sample-webapp
```

The chosen naming keeps the resources readable while still following Helm conventions.

---

## 4. Helm Chart Structure

The chart is structured as follows:

```text
charts/sample-webapp/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── _helpers.tpl
    ├── configmap.yaml
    ├── deployment.yaml
    ├── service.yaml
    └── metrics-service.yaml
```

### `Chart.yaml`

Defines chart metadata, including:

```text
chart name
chart version
application version
```

### `values.yaml`

Defines configurable values such as:

```text
replica count
Nginx image
service type
MetalLB IP annotation
health and readiness probe paths
exporter image
metrics port
resource requests and limits
```

### `templates/deployment.yaml`

Creates the application Deployment.

### `templates/service.yaml`

Creates the public-facing LoadBalancer Service.

### `templates/metrics-service.yaml`

Creates the internal ClusterIP Service used by Prometheus.

### `templates/configmap.yaml`

Creates:

```text
HTML content for the sample web page
Nginx configuration
Health and readiness endpoint behavior
Nginx stub_status configuration
```

### `templates/_helpers.tpl`

Defines reusable Helm template helpers for names, labels, and selectors.

---

## 5. Runtime Architecture

Each application Pod contains two containers:

```text
nginx
nginx-exporter
```

The Nginx container serves the application and exposes internal status information.

The exporter sidecar reads Nginx status data and exposes it in Prometheus format.

```text
Pod: k8s-lab-sample-webapp-xxxxx
├── nginx
│   ├── :80                      application traffic
│   └── 127.0.0.1:8080/stub_status internal Nginx status
└── nginx-exporter
    └── :9113/metrics             Prometheus-format metrics
```

---

## 6. User Traffic Flow

User traffic enters the cluster through the MetalLB-assigned LoadBalancer IP.

```text
User / Load Generator
   |
   v
192.168.200.240:80
   |
   v
Service: k8s-lab-sample-webapp
   |
   v
Nginx container :80
```

The public application endpoint is:

```text
http://192.168.200.240/
```

Health endpoints are also served through the same LoadBalancer Service:

```text
http://192.168.200.240/healthz
http://192.168.200.240/readyz
```

The `/metrics` endpoint is intentionally not exposed through the public LoadBalancer Service.

---

## 7. Metrics Flow

Metrics are collected through an internal path.

```text
Nginx stub_status on 127.0.0.1:8080/stub_status
   |
   | read by
   v
nginx-prometheus-exporter sidecar
   |
   | exposes
   v
:9113/metrics
   |
   | exposed internally by
   v
Service: k8s-lab-sample-webapp-metrics
   |
   | scraped by
   v
Prometheus
```

The Prometheus target is:

```text
k8s-lab-sample-webapp-metrics.demo.svc.cluster.local:9113/metrics
```

This separation is intentional:

```text
Application traffic is public through MetalLB.
Metrics traffic is internal to the cluster.
```

---

## 8. Main Service

The main Service exposes the web application.

Expected Service:

```text
Name: k8s-lab-sample-webapp
Namespace: demo
Type: LoadBalancer
External IP: 192.168.200.240
Port: 80
```

Check it with:

```bash
kubectl get svc -n demo k8s-lab-sample-webapp -o wide
```

Expected result:

```text
TYPE           EXTERNAL-IP
LoadBalancer   192.168.200.240
```

Test the application:

```bash
curl -i http://192.168.200.240/
```

---

## 9. Metrics Service

The metrics Service is internal only.

Expected Service:

```text
Name: k8s-lab-sample-webapp-metrics
Namespace: demo
Type: ClusterIP
Port: 9113
```

Check it with:

```bash
kubectl get svc -n demo k8s-lab-sample-webapp-metrics -o wide
```

Test metrics:

```bash
METRICS_IP=$(kubectl -n demo get svc k8s-lab-sample-webapp-metrics -o jsonpath='{.spec.clusterIP}')

curl -s http://${METRICS_IP}:9113/metrics | grep nginx_http_requests_total
```

Expected result:

```text
nginx_http_requests_total
```

---

## 10. Health and Readiness

The application provides two HTTP endpoints:

```text
/healthz
/readyz
```

These are used by Kubernetes probes.

### Liveness probe

The liveness probe checks whether the container should continue running.

```text
Path: /healthz
Port: http
```

If this probe fails repeatedly, Kubernetes restarts the container.

### Readiness probe

The readiness probe checks whether the Pod should receive traffic.

```text
Path: /readyz
Port: http
```

If this probe fails, the Pod is removed from Service endpoints until it becomes ready again.

Test manually:

```bash
curl -i http://192.168.200.240/healthz
curl -i http://192.168.200.240/readyz
```

Expected responses:

```text
ok
ready
```

---

## 11. Why Metrics Are Not Exposed Publicly

The application does not expose metrics through:

```text
http://192.168.200.240/metrics
```

This is intentional.

Metrics endpoints may expose operational details such as:

```text
request rates
connection counts
internal labels
runtime behavior
```

For this reason, metrics are exposed only through an internal ClusterIP Service:

```text
k8s-lab-sample-webapp-metrics.demo.svc.cluster.local:9113
```

Prometheus can scrape this internal endpoint, but external users cannot access it through the application LoadBalancer.

---

## 12. Nginx stub_status

Nginx does not expose Prometheus metrics directly.

Instead, it exposes basic status information through the `stub_status` module.

The internal status endpoint is:

```text
127.0.0.1:8080/stub_status
```

It is configured to allow only local access from inside the Pod.

The exporter sidecar reads this endpoint and converts the data into Prometheus-format metrics.

This design avoids exposing the raw Nginx status endpoint outside the Pod.

---

## 13. nginx-prometheus-exporter Sidecar

The sidecar container runs:

```text
nginx/nginx-prometheus-exporter
```

It reads:

```text
http://127.0.0.1:8080/stub_status
```

And exposes Prometheus metrics on:

```text
:9113/metrics
```

Important metric:

```text
nginx_http_requests_total
```

Prometheus Adapter later converts this counter into a request-rate custom metric:

```text
nginx_http_requests_per_second
```

---

## 14. Resource Requests and Limits

The application defines resource requests and limits for both containers.

Example:

```text
nginx:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 250m
    memory: 128Mi

nginx-exporter:
  requests:
    cpu: 20m
    memory: 32Mi
  limits:
    cpu: 100m
    memory: 128Mi
```

Requests are important because they help the scheduler place Pods correctly.

Limits protect the cluster from a container consuming too many resources.

For production, these values should be tuned based on real load testing.

---

## 15. Verifying the Application

Run the following checks after deployment.

### Check Helm release

```bash
helm list -n demo
helm status k8s-lab -n demo
```

### Check Pods

```bash
kubectl get pods -n demo -o wide
```

Expected:

```text
READY 2/2
STATUS Running
```

### Check Services

```bash
kubectl get svc -n demo -o wide
```

Expected:

```text
k8s-lab-sample-webapp           LoadBalancer
k8s-lab-sample-webapp-metrics   ClusterIP
```

### Check endpoints

```bash
kubectl get endpoints -n demo
```

The main and metrics Services should both have endpoints.

### Check web traffic

```bash
curl http://192.168.200.240/
```

### Check health

```bash
curl http://192.168.200.240/healthz
curl http://192.168.200.240/readyz
```

### Check metrics

```bash
METRICS_IP=$(kubectl -n demo get svc k8s-lab-sample-webapp-metrics -o jsonpath='{.spec.clusterIP}')

curl -s http://${METRICS_IP}:9113/metrics | grep nginx_http_requests_total
```

---

## 16. Prometheus Verification

Prometheus should scrape the internal metrics Service.

```bash
PROM_IP=$(kubectl -n monitoring get svc prometheus-server -o jsonpath='{.spec.clusterIP}')

curl -s "http://${PROM_IP}/api/v1/query?query=nginx_http_requests_total" | jq
```

Expected:

```text
result array is not empty
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

---

## 17. HPA Relationship

The application is connected to HPA through the following flow:

```text
Nginx request count
   |
   v
nginx_http_requests_total
   |
   v
Prometheus rate query
   |
   v
Prometheus Adapter custom metric
   |
   v
nginx_http_requests_per_second
   |
   v
HPA scales Deployment/k8s-lab-sample-webapp
```

The HPA does not read metrics directly from Nginx or Prometheus.

Instead, it reads from the Kubernetes Custom Metrics API exposed by Prometheus Adapter.

---

## 18. Load Testing

The repository includes a load generator script:

```text
scripts/load-test.sh
```

Start load:

```bash
WORKERS=10 APP_URL=http://192.168.200.240 ./scripts/load-test.sh start
```

Check status:

```bash
./scripts/load-test.sh status
```

Stop load:

```bash
./scripts/load-test.sh stop
```

Watch HPA:

```bash
watch -n 2 'kubectl get hpa -n demo; echo; kubectl get deploy -n demo k8s-lab-sample-webapp'
```

---

## 19. Updating the Application

To redeploy the application after chart changes:

```bash
cd ansible
ansible-playbook site.yml --tags sample_app
```

If the application naming or Service names change, re-run dependent components:

```bash
ansible-playbook site.yml --tags prometheus
ansible-playbook site.yml --tags prometheus_adapter
ansible-playbook site.yml --tags hpa
```

This is required because Prometheus and HPA reference the application Service names.

---

## 20. Cleanup

To remove the application only:

```bash
helm uninstall k8s-lab -n demo --kubeconfig /etc/kubernetes/admin.conf
```

To remove the namespace:

```bash
kubectl delete ns demo --ignore-not-found
```

If the namespace is removed, redeploy the app with:

```bash
cd ansible
ansible-playbook site.yml --tags sample_app
```

---

## 21. Summary

The sample application demonstrates a production-style pattern in a lab environment:

```text
Helm deployment
LoadBalancer exposure through MetalLB
Internal-only metrics endpoint
Sidecar-based metric export
Prometheus scraping
Custom metrics integration
HPA autoscaling
```

The key design choice is the separation between user traffic and metrics traffic.

```text
User traffic:
192.168.200.240:80 -> k8s-lab-sample-webapp -> nginx

Metrics traffic:
Prometheus -> k8s-lab-sample-webapp-metrics:9113 -> nginx-exporter -> Nginx stub_status
```

This makes the application easy to test while keeping operational metrics internal to the cluster.
