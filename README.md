# Kubernetes as Code: Automated HA Kubernetes Lab with Ansible and Vagrant

This repository builds a local Kubernetes lab using Vagrant and Ansible.

It demonstrates:

```text
- Multi-node Kubernetes cluster
- HA control plane with HAProxy and Keepalived
- Calico CNI
- MetalLB LoadBalancer
- Helm-based sample application deployment
- Metrics Server
- Prometheus
- Prometheus Adapter
- HPA based on custom Nginx request-rate metrics
- Limited RBAC user for application visibility
```

The project is designed as a practical Kubernetes service implementation lab.

---

## 1. Repository Purpose

The goal is to provide a repeatable and understandable Kubernetes lab that shows not only how to install services, but also how the components work together.

The lab focuses on:

```text
automation
high availability
networking
observability
custom metrics
autoscaling
RBAC
security-aware design
```

---

## 2. High-Level Architecture

```text
Vagrant
   |
   v
Virtual Machines

Ansible
   |
   v
Kubernetes HA Cluster
   |
   +--> Calico CNI
   +--> MetalLB
   +--> Metrics Server
   +--> Prometheus
   +--> Prometheus Adapter
   +--> Sample Web Application
   +--> HPA with Custom Metrics
```

---

## 3. Cluster Topology

The lab uses five VMs:

```text
k8s-master-1
k8s-master-2
k8s-master-3
k8s-worker-1
k8s-worker-2
```

Networks:

```text
Management network: 192.168.100.0/24
Workload network:   192.168.200.0/24
Pod network:        10.244.0.0/16
Service network:    10.96.0.0/12
```

Kubernetes API VIP:

```text
192.168.100.10:8443
```

Application LoadBalancer IP:

```text
192.168.200.240
```

---

## 4. Main Components

| Component | Purpose |
|---|---|
| Vagrant | Creates local VMs and networks |
| Ansible | Automates OS, Kubernetes, and service configuration |
| kubeadm | Bootstraps Kubernetes |
| containerd | Container runtime |
| HAProxy | Load balances Kubernetes API traffic |
| Keepalived | Provides Kubernetes API virtual IP |
| Calico | Provides Pod networking |
| MetalLB | Provides LoadBalancer IPs |
| Helm | Deploys Kubernetes applications |
| Metrics Server | Provides CPU and memory metrics |
| Prometheus | Scrapes application metrics |
| Prometheus Adapter | Exposes Prometheus metrics to Kubernetes Custom Metrics API |
| HPA | Scales the sample application based on custom metrics |

---

## 5. Sample Application

The sample app is deployed using Helm.

Helm release name:

```text
k8s-lab
```

Chart name:

```text
sample-webapp
```

Generated resource names:

```text
Deployment:      k8s-lab-sample-webapp
Main Service:    k8s-lab-sample-webapp
Metrics Service: k8s-lab-sample-webapp-metrics
```

Public application URL:

```text
http://192.168.200.240/
```

Metrics target:

```text
k8s-lab-sample-webapp-metrics.demo.svc.cluster.local:9113/metrics
```

---

## 6. Metrics and HPA Flow

```text
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
HPA
   |
   v
Deployment/k8s-lab-sample-webapp
```

The HPA uses:

```text
Metric: nginx_http_requests_per_second
Object: Service/k8s-lab-sample-webapp
Target type: AverageValue
Target: 500m
```

---

## 7. Repository Structure

```text
Lab/
├── README.md
├── Vagrantfile
├── ansible/
│   ├── site.yml
│   ├── inventory.ini
│   ├── group_vars/
│   └── roles/
├── charts/
│   └── sample-webapp/
├── scripts/
│   └── load-test.sh
└── docs/
    ├── 01-architecture.md
    ├── 02-prerequisites.md
    ├── 03-installation.md
    ├── 04-operations.md
    ├── 05-application.md
    ├── 06-observability.md
    ├── 07-hpa-custom-metrics.md
    ├── 08-security.md
    └── 09-troubleshooting.md
```

---

## 8. Documentation

Read the documentation in this order:

```text
1. Architecture
2. Prerequisites
3. Installation
4. Operations
5. Application
6. Observability
7. HPA with Custom Metrics
8. Security
9. Troubleshooting
```

Files:

```text
docs/01-architecture.md
docs/02-prerequisites.md
docs/03-installation.md
docs/04-operations.md
docs/05-application.md
docs/06-observability.md
docs/07-hpa-custom-metrics.md
docs/08-security.md
docs/09-troubleshooting.md
```

---

## 9. Quick Start

From the repository root:

```bash
vagrant up
```

Then run Ansible:

```bash
cd ansible
ansible-playbook site.yml
```

Verify the cluster:

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

Verify the sample application:

```bash
curl http://192.168.200.240/
```

---

## 10. Running Specific Stages

The project supports Ansible tags.

Examples:

```bash
cd ansible

ansible-playbook site.yml --tags sample_app
ansible-playbook site.yml --tags prometheus
ansible-playbook site.yml --tags prometheus_adapter
ansible-playbook site.yml --tags hpa
ansible-playbook site.yml --tags rbac
```

---

## 11. Verify Monitoring

Check Metrics Server:

```bash
kubectl top nodes
kubectl top pods -A
```

Check Prometheus:

```bash
PROM_IP=$(kubectl -n monitoring get svc prometheus-server -o jsonpath='{.spec.clusterIP}')

curl -s "http://${PROM_IP}/api/v1/query?query=nginx_http_requests_total" | jq
```

Check Custom Metrics API:

```bash
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq
```

Check HPA:

```bash
kubectl get hpa -n demo
kubectl describe hpa -n demo sample-webapp-hpa
```

---

## 12. Generate Load

Use the load generator script:

```bash
WORKERS=10 APP_URL=http://192.168.200.240 ./scripts/load-test.sh start
```

Watch HPA:

```bash
watch -n 2 'kubectl get hpa -n demo; echo; kubectl get deploy -n demo k8s-lab-sample-webapp'
```

Stop load:

```bash
./scripts/load-test.sh stop
```

---

## 13. Security Notes

The lab includes several security-aware design choices:

```text
- Kubernetes API is exposed on the management network.
- Application traffic is exposed on the workload network.
- Metrics endpoint is internal only.
- A limited app-viewer user is created with namespace-scoped RBAC.
- Admin kubeconfig is separate from viewer kubeconfig.
```

The public application Service does not expose `/metrics`.

Metrics are scraped internally through:

```text
k8s-lab-sample-webapp-metrics.demo.svc.cluster.local:9113
```

---

## 14. Cleanup

Stop the VMs:

```bash
vagrant halt
```

Destroy the lab:

```bash
vagrant destroy -f
```

Remove the sample application only:

```bash
helm uninstall k8s-lab -n demo --kubeconfig /etc/kubernetes/admin.conf
```

---

## 15. Notes

This is a lab environment, not a complete production platform.

Before using a similar design in production, additional controls are required, such as:

```text
enterprise authentication
strict RBAC
NetworkPolicies
secret management
persistent monitoring storage
centralized logging
backup and disaster recovery
upgrade strategy
```

For more details, read:

```text
docs/08-security.md
```
