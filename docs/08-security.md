# 08 - Security Considerations

This document explains the security design and security recommendations for the Kubernetes lab.

The lab is intentionally simple enough to run locally with Vagrant, but the design includes several production-oriented security practices.

---

## 1. Security Goals

The security goals of this lab are:

```text
- Avoid exposing operational endpoints publicly.
- Use least-privilege access for application visibility.
- Keep administrative access separate from application viewer access.
- Use clear network separation between management and workload traffic.
- Provide production recommendations for RBAC, secrets, network policies, and hardening.
```

This lab is not a complete production security baseline, but it demonstrates the correct security direction.

---

## 2. Security Boundaries

The lab separates several responsibilities and traffic types.

```text
Management access:
  SSH, Ansible, Kubernetes API, HAProxy/Keepalived control-plane traffic

Application traffic:
  User traffic to the sample application through MetalLB

Metrics traffic:
  Internal Prometheus scraping through ClusterIP Services

Administrative access:
  Kubernetes admin kubeconfig

Read-only application access:
  Limited app-viewer kubeconfig
```

The main principle is:

```text
Expose only what must be exposed.
Keep operational and administrative interfaces internal or restricted.
```

---

## 3. Network Separation

The lab uses separate network ranges:

```text
Management network:
192.168.100.0/24

Workload network:
192.168.200.0/24

Pod network:
10.244.0.0/16

Service network:
10.96.0.0/12
```

The management network is used for:

```text
SSH
Ansible
Kubernetes node management
Kubernetes API VIP
HAProxy/Keepalived control-plane access
```

The workload network is used for:

```text
Application LoadBalancer IPs
User-facing service traffic
MetalLB address allocation
```

This separation makes the design easier to reason about and closer to enterprise network segmentation.

---

## 4. Kubernetes API Security

The Kubernetes API is exposed through a highly available VIP:

```text
192.168.100.10:6443
```

This VIP is managed by Keepalived and forwarded by HAProxy to healthy API servers.

Security considerations:

```text
- The API endpoint is on the management network, not the workload network.
- Access should be restricted to trusted administrators and automation systems.
- In production, firewall rules should restrict access to TCP/6443.
- kubeconfig files must be protected.
```

Check API access:

```bash
curl -k https://192.168.100.10:6443/version
```

---

## 5. Admin kubeconfig

The default Kubernetes admin kubeconfig is:

```text
/etc/kubernetes/admin.conf
```

This file has cluster-admin privileges.

It should be treated as a highly sensitive credential.

Recommended practices:

```text
- Do not copy admin.conf unnecessarily.
- Do not commit kubeconfig files to Git.
- Restrict file permissions.
- Use separate non-admin users for day-to-day operations.
- Use short-lived credentials or OIDC in production.
```

In this lab, Ansible uses `admin.conf` to automate cluster-level operations.

---

## 6. Limited Application Viewer User

The lab creates a limited Kubernetes user:

```text
app-viewer
```

This user is intended only for application visibility.

It can:

```text
- list Pods in the demo namespace
- list Services in the demo namespace
- list Deployments and ReplicaSets in the demo namespace
- describe application resources
- read Pod logs
```

It must not be able to:

```text
- list cluster nodes
- create or delete workloads
- read Secrets
- modify RBAC
- access other namespaces
- perform cluster-admin operations
```

The kubeconfig is stored on the first control-plane node:

```text
/opt/kubernetes/users/app-viewer/app-viewer.kubeconfig
```

---

## 7. RBAC Design

The RBAC model uses a namespace-scoped Role and RoleBinding.

Namespace:

```text
demo
```

Role:

```text
app-viewer
```

Allowed resources:

```text
pods
pods/log
services
endpoints
configmaps
deployments
replicasets
```

Allowed verbs:

```text
get
list
watch
```

The role intentionally excludes:

```text
secrets
nodes
roles
rolebindings
clusterroles
clusterrolebindings
```

This follows the principle of least privilege.

---

## 8. Verify app-viewer Access

Allowed commands:

```bash
sudo kubectl --kubeconfig=/opt/kubernetes/users/app-viewer/app-viewer.kubeconfig get pods -n demo

sudo kubectl --kubeconfig=/opt/kubernetes/users/app-viewer/app-viewer.kubeconfig get svc -n demo

sudo kubectl --kubeconfig=/opt/kubernetes/users/app-viewer/app-viewer.kubeconfig logs -n demo deploy/k8s-lab-sample-webapp --tail=20
```

Denied commands:

```bash
sudo kubectl --kubeconfig=/opt/kubernetes/users/app-viewer/app-viewer.kubeconfig get nodes

sudo kubectl --kubeconfig=/opt/kubernetes/users/app-viewer/app-viewer.kubeconfig get secrets -n demo

sudo kubectl --kubeconfig=/opt/kubernetes/users/app-viewer/app-viewer.kubeconfig delete pod -n demo <pod-name> --dry-run=server
```

Expected behavior:

```text
Allowed commands succeed.
Denied commands return Forbidden.
```

---

## 9. Metrics Endpoint Security

The application has two Services:

```text
Public Service:
k8s-lab-sample-webapp
Type: LoadBalancer
External IP: 192.168.200.240
Port: 80

Internal Metrics Service:
k8s-lab-sample-webapp-metrics
Type: ClusterIP
Port: 9113
```

The public Service exposes only application traffic:

```text
/
 /healthz
 /readyz
```

The metrics endpoint is not publicly exposed:

```text
http://192.168.200.240/metrics
```

This is intentional.

Operational metrics can reveal internal behavior such as:

```text
request volume
connection counts
runtime information
internal labels
service names
```

For this reason, metrics should be available only to monitoring components.

---

## 10. Nginx stub_status Security

Nginx exposes internal status on:

```text
127.0.0.1:8080/stub_status
```

This endpoint is available only inside the Pod.

The exporter sidecar reads it locally:

```text
nginx-prometheus-exporter -> 127.0.0.1:8080/stub_status
```

It is not exposed through the public LoadBalancer.

This design prevents direct external access to raw Nginx status information.

---

## 11. Prometheus Security

In this lab, Prometheus is exposed only through an internal ClusterIP Service:

```text
prometheus-server.monitoring.svc.cluster.local
```

Recommended practices:

```text
- Do not expose Prometheus publicly without authentication.
- Protect the Prometheus API.
- Restrict access using NetworkPolicies.
- Use TLS and authentication in production.
- Avoid storing sensitive labels or secrets in metrics.
```

For production, Prometheus should be integrated with:

```text
- authentication
- authorization
- TLS
- alerting
- remote storage or long-term retention
```

---

## 12. Prometheus Adapter Security

Prometheus Adapter exposes selected metrics through:

```text
custom.metrics.k8s.io
```

The Adapter should expose only required metrics.

In this lab, only one custom metric is exposed:

```text
nginx_http_requests_per_second
```

This is better than exposing all Prometheus metrics to the Kubernetes API.

Recommended practices:

```text
- Keep Adapter rules narrow.
- Expose only metrics required by HPA.
- Avoid exposing sensitive application metrics.
- Monitor Adapter logs for query errors.
```

---

## 13. Secrets Management

This lab avoids complex application secrets, but the platform itself still has sensitive data.

Sensitive files include:

```text
/etc/kubernetes/admin.conf
/etc/kubernetes/pki/*
/opt/kubernetes/users/app-viewer/*.key
Ansible variables containing passwords or tokens
```

Recommendations:

```text
- Never commit private keys or kubeconfigs to Git.
- Use Ansible Vault for sensitive variables.
- Use Kubernetes Secrets for application secrets.
- Use an external secret manager in production.
```

Production-grade options:

```text
HashiCorp Vault
External Secrets Operator
Sealed Secrets
Cloud KMS-backed secret stores
SOPS
```

---

## 14. Ansible Secret Handling

Avoid storing plaintext secrets in:

```text
group_vars/all.yml
host_vars/*
role defaults
template files
```

For sensitive values, use:

```bash
ansible-vault encrypt_string
ansible-vault create group_vars/vault.yml
```

Example:

```bash
ansible-vault create ansible/group_vars/vault.yml
```

Then run:

```bash
ansible-playbook site.yml --ask-vault-pass
```

In this lab, some values may be lab-only placeholders.  
Documentation should clearly state that such values must be changed before production use.

---

## 15. NetworkPolicy Recommendations

The lab may run without NetworkPolicies for simplicity.

For production, NetworkPolicies should restrict traffic.

Recommended policies:

```text
- Allow Prometheus to scrape only metrics Services.
- Allow users to reach only the application Service.
- Restrict namespace-to-namespace traffic.
- Restrict access to monitoring namespace.
- Restrict access to Kubernetes system components.
```

Example policy intent:

```text
Only Pods in namespace monitoring with label app=prometheus
can access k8s-lab-sample-webapp-metrics on TCP/9113.
```

This is not mandatory for the lab, but it is recommended for production.

---

## 16. Container Security

The sample application should follow basic container security practices.

Recommended settings:

```text
- Define resource requests and limits.
- Avoid running as root where possible.
- Use read-only root filesystem where possible.
- Drop Linux capabilities where possible.
- Avoid privileged containers.
- Avoid hostPath mounts unless required.
```

For this lab, the Nginx image may run with its default user model.  
For production, use hardened images and stricter Pod security contexts.

---

## 17. Image Security

Images used in the lab include:

```text
nginx
nginx-prometheus-exporter
metrics-server
prometheus
prometheus-adapter
calico
metallb
```

Recommended practices:

```text
- Pin image tags.
- Prefer digest pinning for production.
- Use a private registry or registry mirror.
- Scan images for vulnerabilities.
- Avoid using latest tags.
- Pre-pull images in restricted environments.
```

The lab pre-pulls images to reduce install failures caused by slow internet access.

---

## 18. Kubernetes Package Security

Kubernetes components are pinned to a specific version.

Recommended practices:

```text
- Pin kubeadm, kubelet, and kubectl versions.
- Hold packages to avoid accidental upgrades.
- Upgrade using a controlled plan.
- Upgrade one minor version at a time.
- Back up etcd before upgrading.
```

Check held packages:

```bash
apt-mark showhold | grep -E 'kubelet|kubeadm|kubectl'
```

---

## 19. Node Hardening

The lab configures basic prerequisites such as:

```text
swap disabled
kernel modules
sysctl values
container runtime configuration
```

Production hardening should also include:

```text
host firewall rules
SSH hardening
automatic security updates policy
audit logging
restricted sudo access
kernel hardening
time synchronization
centralized logging
vulnerability management
```

---

## 20. HA Security Considerations

HAProxy and Keepalived provide Kubernetes API availability.

Security recommendations:

```text
- Restrict API VIP access to administrators and automation systems.
- Use firewall rules around TCP/6443.
- Protect Keepalived configuration.
- Use strong Keepalived authentication values.
- Avoid exposing API VIP on public networks.
```

If a Keepalived authentication password is used, it should be treated as a secret.

For production, store it using Ansible Vault.

---

## 20. Access Model Summary

| Access Type | Credential | Scope |
|---|---|---|
| Cluster admin | `/etc/kubernetes/admin.conf` | Full cluster administration |
| App viewer | `/opt/kubernetes/users/app-viewer/app-viewer.kubeconfig` | Read-only access to demo application resources |
| Prometheus | Cluster-internal Service access | Metrics scraping |
| HPA | Custom Metrics API | Reads autoscaling metrics |
| Users | MetalLB LoadBalancer IP | HTTP application traffic only |

---

## 21. Lab vs Production

### Lab design

```text
Self-contained Vagrant environment
Local VM networking
Internal Prometheus
Simple RBAC user
Lab-friendly HPA thresholds
Some insecure TLS flags for compatibility
```

### Production recommendations

```text
Use OIDC or enterprise identity provider.
Use external load balancers.
Use a private registry.
Use NetworkPolicies.
Use secrets encryption at rest.
Use backup and disaster recovery procedures.
Use centralized logging and monitoring.
Use admission control and Pod Security Standards.
Use GitOps for workload deployment.
```

---

## 22. Security Checklist

Before sharing or publishing the repository, verify:

```text
No private keys are committed.
No kubeconfig files are committed.
No passwords are committed.
No generated certificates are committed.
No .vagrant or local state directories are committed.
No sensitive IPs or real domain names are included unless intentional.
All lab-only passwords are documented as lab-only values.
```

Recommended `.gitignore` entries:

```text
.vagrant/
.ansible/
*.retry
*.key
*.pem
*.crt
*.csr
admin.conf
kubeconfig
```

---

## 23. Summary

The lab implements several important security practices:

```text
management and workload network separation
internal-only metrics endpoint
limited RBAC user for application visibility
separation of admin and viewer access
non-public Prometheus and metrics Services
pinned packages and images
clear production hardening recommendations
```

The main production gap is that this is still a lab environment.  
Before using a similar design in production, additional controls such as OIDC, NetworkPolicies, secret management, audit logging, and backup/restore procedures must be implemented.
