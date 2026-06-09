# 04 - Operations Runbook

This document describes the common operational tasks for the Vagrant-based Kubernetes lab.  
It assumes that the cluster has already been provisioned and configured using `ansible/site.yml`.

The purpose of this runbook is to provide repeatable commands for checking, re-running, and troubleshooting the main components of the lab without rebuilding everything from scratch.

---

## 1. Operating Model

The repository is organized around a clear separation of responsibilities:

```text
Vagrant
  Creates virtual machines, network interfaces, hostnames, and static IPs.

Ansible
  Installs and configures Kubernetes, HA components, CNI, MetalLB, monitoring,
  RBAC, the sample application, and HPA.

Helm
  Deploys Kubernetes applications and monitoring components.

Kubernetes
  Runs the control plane, worker workloads, services, autoscaling, and metrics APIs.
```

The main operational entrypoint is:

```bash
cd ansible
ansible-playbook site.yml
```

Individual stages can be re-run using tags.

---

## 2. Common Ansible Tags

Use tags when you need to re-run only part of the automation.

```bash
cd ansible
ansible-playbook site.yml --tags <tag>
```

Common tags:

| Tag | Purpose |
|---|---|
| `os_prepare` | Re-run base OS preparation tasks |
| `containerd` | Reconfigure container runtime |
| `kubernetes` | Reinstall or verify Kubernetes packages |
| `ha` | Reconfigure HAProxy and Keepalived |
| `control_plane` | Bootstrap or verify control-plane configuration |
| `worker` | Join or verify worker nodes |
| `calico` | Install or reconfigure Calico CNI |
| `helm` | Install or verify Helm |
| `metallb` | Install or reconfigure MetalLB |
| `sample_app` | Deploy or upgrade the sample application |
| `rbac` | Create or update the limited application viewer user |
| `metrics_server` | Install or verify Metrics Server |
| `prometheus` | Install or verify Prometheus |
| `prometheus_adapter` | Install or verify Prometheus Adapter |
| `hpa` | Create or update the sample application HPA |
| `custom_metrics` | Work with custom metrics related components |
| `images` | Pre-pull required container images |

Examples:

```bash
ansible-playbook site.yml --tags sample_app
ansible-playbook site.yml --tags prometheus
ansible-playbook site.yml --tags prometheus_adapter
ansible-playbook site.yml --tags hpa
```

---

## 3. VM Operations with Vagrant

### Check VM status

From the repository root:

```bash
vagrant status
```

Expected nodes:

```text
k8s-master-1
k8s-master-2
k8s-master-3
k8s-worker-1
k8s-worker-2
```

### Start all VMs

```bash
vagrant up
```

### SSH to a node

```bash
vagrant ssh k8s-master-1
```

### Stop all VMs

```bash
vagrant halt
```

### Destroy the lab

```bash
vagrant destroy -f
```

Destroying the lab removes the VMs. It should be used only when a full rebuild is required.

---

## 4. Kubernetes Cluster Health

Run the following commands from `k8s-master-1`.

### Check nodes

```bash
kubectl get nodes -o wide
```

Expected result:

```text
All nodes should be Ready.
Control-plane nodes should show the control-plane role.
Worker nodes should be Ready and schedulable.
```

### Check core system Pods

```bash
kubectl get pods -n kube-system -o wide
```

Important components:

```text
kube-apiserver
kube-controller-manager
kube-scheduler
etcd
coredns
calico
metrics-server
```

### Check API availability through the HA endpoint

```bash
curl -k https://192.168.100.10:6443/version
```

The VIP `192.168.100.10` should be served by Keepalived and forwarded by HAProxy to healthy Kubernetes API servers.

---

## 5. HAProxy and Keepalived Operations

HAProxy and Keepalived run on all control-plane nodes.

### Check HAProxy status

```bash
ansible kube_masters -m shell -a "systemctl is-active haproxy"
```

Expected:

```text
active
```

### Check Keepalived status

```bash
ansible kube_masters -m shell -a "systemctl is-active keepalived"
```

Expected:

```text
active
```

### Check where the VIP currently lives

```bash
ansible kube_masters -m shell -a "ip addr | grep 192.168.100.10 || true"
```

Only one control-plane node should currently own the VIP.

### Check HAProxy backend health

On a control-plane node:

```bash
sudo systemctl status haproxy --no-pager
sudo journalctl -u haproxy -n 100 --no-pager
```

---

## 6. Calico Operations

Calico provides Pod networking.

### Check Calico Pods

```bash
kubectl get pods -n calico-system -o wide
```

or if Calico was installed in `kube-system`:

```bash
kubectl get pods -n kube-system | grep calico
```

### Check Pod-to-Pod connectivity

Create two temporary Pods and test connectivity:

```bash
kubectl run test-a --image=busybox:1.36 --restart=Never -- sleep 3600
kubectl run test-b --image=busybox:1.36 --restart=Never -- sleep 3600

kubectl get pods -o wide
```

Then exec into one Pod and ping the other Pod IP:

```bash
kubectl exec -it test-a -- sh
ping <test-b-pod-ip>
```

Cleanup:

```bash
kubectl delete pod test-a test-b --ignore-not-found
```

### Operational note

This lab uses Calico VXLAN mode to avoid requiring external routing for Pod CIDRs.  
This makes the lab more portable across Vagrant providers and host environments.

---

## 7. MetalLB Operations

MetalLB provides LoadBalancer IPs for bare-metal or lab Kubernetes clusters.

### Check MetalLB Pods

```bash
kubectl get pods -n metallb-system -o wide
```

Expected components:

```text
controller
speaker
```

### Check address pool

```bash
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
```

### Check LoadBalancer assignment

```bash
kubectl get svc -n demo -o wide
```

Expected main application Service:

```text
k8s-lab-sample-webapp
TYPE: LoadBalancer
EXTERNAL-IP: 192.168.200.240
```

### Test the application through MetalLB

```bash
curl -i http://192.168.200.240/
curl -i http://192.168.200.240/healthz
curl -i http://192.168.200.240/readyz
```

The `/metrics` endpoint is intentionally not exposed through the public LoadBalancer Service.

---

## 8. Sample Application Operations

The sample application is deployed using Helm.

### Check Helm release

```bash
helm list -n demo
helm status k8s-lab -n demo
```

### Check Kubernetes resources

```bash
kubectl get all -n demo -o wide
```

Expected resources:

```text
Deployment: k8s-lab-sample-webapp
Main Service: k8s-lab-sample-webapp
Metrics Service: k8s-lab-sample-webapp-metrics
Pods: 2/2 Ready because each Pod has nginx and nginx-exporter containers
```

### Check Pod containers

```bash
kubectl get pods -n demo
```

Expected:

```text
READY 2/2
```

The two containers are:

```text
nginx
nginx-exporter
```

### Check application endpoint

```bash
curl http://192.168.200.240/
```

### Check health endpoints

```bash
curl http://192.168.200.240/healthz
curl http://192.168.200.240/readyz
```

Expected:

```text
ok
ready
```

### Check internal metrics endpoint

```bash
METRICS_IP=$(kubectl -n demo get svc k8s-lab-sample-webapp-metrics -o jsonpath='{.spec.clusterIP}')

curl -s http://${METRICS_IP}:9113/metrics | grep nginx_http_requests_total
```

Expected:

```text
nginx_http_requests_total
```

---

## 9. Metrics Server Operations

Metrics Server provides resource metrics through the `metrics.k8s.io` API.

### Check Metrics Server

```bash
kubectl get pods -n kube-system | grep metrics-server
kubectl get apiservice v1beta1.metrics.k8s.io
```

Expected:

```text
AVAILABLE=True
```

### Check node metrics

```bash
kubectl top nodes
```

### Check Pod metrics

```bash
kubectl top pods -A
```

If metrics are not available immediately after installation, wait for one or two collection intervals and retry.

---

## 10. Prometheus Operations

Prometheus scrapes the sample application metrics through the internal metrics Service.

### Check Prometheus Pod

```bash
kubectl get pods -n monitoring | grep prometheus-server
```

Expected:

```text
prometheus-server-...  2/2  Running
```

### Check Prometheus Service

```bash
kubectl get svc -n monitoring prometheus-server
```

### Query Prometheus from inside the cluster

```bash
PROM_IP=$(kubectl -n monitoring get svc prometheus-server -o jsonpath='{.spec.clusterIP}')

curl -s "http://${PROM_IP}/api/v1/query?query=nginx_http_requests_total" | jq
```

### Query request rate

```bash
curl -s "http://${PROM_IP}/api/v1/query?query=sum%28rate%28nginx_http_requests_total%7Bnamespace%3D%22demo%22%2Cservice%3D%22k8s-lab-sample-webapp%22%7D%5B2m%5D%29%29" | jq
```

### Check Prometheus targets

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

## 11. Prometheus Adapter Operations

Prometheus Adapter exposes selected Prometheus metrics through the Kubernetes Custom Metrics API.

### Check Adapter Pod

```bash
kubectl get pods -n monitoring | grep prometheus-adapter
```

Expected:

```text
Running
```

### Check Custom Metrics APIService

```bash
kubectl get apiservice v1beta1.custom.metrics.k8s.io
```

Expected:

```text
AVAILABLE=True
```

### List custom metrics

```bash
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq
```

Expected metric:

```text
services/nginx_http_requests_per_second
```

### Query the custom metric for the application Service

```bash
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1/namespaces/demo/services/k8s-lab-sample-webapp/nginx_http_requests_per_second | jq
```

Expected:

```text
MetricValueList with a non-empty items array
```

---

## 12. HPA Operations

The sample application HPA uses the custom metric exposed by Prometheus Adapter.

### Check HPA

```bash
kubectl get hpa -n demo
kubectl describe hpa -n demo sample-webapp-hpa
```

Expected:

```text
ScalingActive=True
Reason=ValidMetricFound
```

The HPA uses:

```text
Metric: nginx_http_requests_per_second
Object: Service/k8s-lab-sample-webapp
Target type: AverageValue
Target value: 500m
```

### Watch HPA behavior

```bash
watch -n 2 'kubectl get hpa -n demo; echo; kubectl get deploy -n demo k8s-lab-sample-webapp'
```

### Important note about scale-down

Scale-down is intentionally slower than scale-up.  
This avoids replica flapping when traffic briefly drops.

Current lab behavior:

```text
scaleUp stabilization: 0s
scaleDown stabilization: 60s
Prometheus rate window: 2m
Adapter relist interval: 30s
```

---

## 13. Load Test Operations

The repository includes a load generation script:

```text
scripts/load-test.sh
```

### Start load

```bash
WORKERS=10 APP_URL=http://192.168.200.240 ./scripts/load-test.sh start
```

### Check load generator status

```bash
./scripts/load-test.sh status
```

### Stop load

```bash
./scripts/load-test.sh stop
```

### Observe scaling

While the load generator is running:

```bash
watch -n 2 'kubectl get hpa -n demo; echo; kubectl get deploy -n demo k8s-lab-sample-webapp'
```

After stopping the load generator, wait for the Prometheus rate window and HPA scale-down stabilization period before expecting replicas to decrease.

---

## 14. RBAC Operations

A limited application viewer user is created for viewing application status and logs.

### Check kubeconfig

```bash
sudo ls -l /opt/kubernetes/users/app-viewer/app-viewer.kubeconfig
```

### Allowed operations

```bash
sudo kubectl --kubeconfig=/opt/kubernetes/users/app-viewer/app-viewer.kubeconfig get pods -n demo
sudo kubectl --kubeconfig=/opt/kubernetes/users/app-viewer/app-viewer.kubeconfig get svc -n demo
sudo kubectl --kubeconfig=/opt/kubernetes/users/app-viewer/app-viewer.kubeconfig logs -n demo deploy/k8s-lab-sample-webapp --tail=20
```

### Denied operations

These should fail:

```bash
sudo kubectl --kubeconfig=/opt/kubernetes/users/app-viewer/app-viewer.kubeconfig get nodes

sudo kubectl --kubeconfig=/opt/kubernetes/users/app-viewer/app-viewer.kubeconfig delete pod -n demo <pod-name> --dry-run=server
```

This confirms that the user is restricted to application visibility only.

---

## 15. Restarting Common Components

### Restart sample application

```bash
kubectl rollout restart deployment -n demo k8s-lab-sample-webapp
kubectl rollout status deployment -n demo k8s-lab-sample-webapp
```

### Restart Prometheus

```bash
kubectl rollout restart deployment -n monitoring prometheus-server
kubectl rollout status deployment -n monitoring prometheus-server
```

### Restart Prometheus Adapter

```bash
kubectl rollout restart deployment -n monitoring prometheus-adapter
kubectl rollout status deployment -n monitoring prometheus-adapter
```

### Restart Metrics Server

```bash
kubectl rollout restart deployment -n kube-system metrics-server
kubectl rollout status deployment -n kube-system metrics-server
```

### Restart static control-plane components

For kubeadm clusters, control-plane components are static Pods.  
Deleting the Pod causes kubelet to recreate it.

Example:

```bash
kubectl -n kube-system delete pod kube-controller-manager-k8s-master-1
```

Use this carefully.

---

## 16. Logs and Events

### Cluster-wide recent events

```bash
kubectl get events -A --sort-by=.metadata.creationTimestamp | tail -100
```

### Events for the demo namespace

```bash
kubectl get events -n demo --sort-by=.metadata.creationTimestamp | tail -50
```

### Prometheus logs

```bash
kubectl logs -n monitoring deploy/prometheus-server -c prometheus-server --tail=100
```

### Prometheus Adapter logs

```bash
kubectl logs -n monitoring deploy/prometheus-adapter --tail=100
```

### Sample application logs

```bash
kubectl logs -n demo deploy/k8s-lab-sample-webapp -c nginx --tail=100
kubectl logs -n demo deploy/k8s-lab-sample-webapp -c nginx-exporter --tail=100
```

---

## 17. Operational Best Practices

For this lab:

```text
Use Ansible tags for controlled re-runs.
Avoid manual changes unless troubleshooting.
Do not expose metrics publicly through the LoadBalancer.
Use the internal metrics Service for Prometheus scraping.
Use the limited app-viewer kubeconfig for read-only application checks.
Use the admin kubeconfig only for administrative operations.
```

For production:

```text
Use GitOps for application deployment.
Use an external load balancer for the Kubernetes API.
Use a real PKI or OIDC-based authentication model.
Use NetworkPolicies to restrict traffic.
Use centralized logging and alerting.
Use persistent storage for Prometheus or a remote metrics backend.
Back up etcd regularly.
Avoid using insecure TLS flags except in controlled lab environments.
```

---

## 18. Quick Operational Checklist

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc -n demo
kubectl get hpa -n demo
kubectl top nodes
kubectl top pods -A
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl get apiservice v1beta1.custom.metrics.k8s.io
helm list -A
```

If all checks are healthy, the lab is operational.
