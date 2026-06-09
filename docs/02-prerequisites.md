# 02 - Prerequisites

This document describes the required tools, host resources, networking assumptions, and environmental requirements for running the Vagrant-based Kubernetes HA lab.

The goal of this lab is to provision a multi-node Kubernetes cluster with Vagrant and configure it using Ansible. Vagrant is responsible for creating the virtual machines and their networks, while Ansible is responsible for configuring the operating system, Kubernetes, networking, observability, RBAC, and autoscaling components.

---

## 1. Host Machine Requirements

The lab is designed to run on a developer or administrator workstation with local virtualization support.

The default topology uses five virtual machines:

| Node Type | Count | Purpose |
|---|---:|---|
| Kubernetes control-plane | 3 | HA control plane, HAProxy, Keepalived |
| Kubernetes worker | 2 | Application and workload execution |

Control-plane nodes are configured with lower lab-sized resources than a production cluster. These values are intentionally small for local testing and must not be treated as production sizing guidance.

---

## 2. Required Tools on the Host

The following tools should be installed on the host machine before starting the lab.

| Tool | Purpose |
|---|---|
| Vagrant | Creates and manages the virtual machines |
| Vagrant provider | Runs the VMs using libvirt or VirtualBox |
| Ansible | Configures the Kubernetes cluster and add-on components |
| SSH client | Connects to Vagrant VMs |
| Git | Clones and manages the project repository |

Optional but useful tools:

| Tool | Purpose |
|---|---|
| kubectl | Optional host-side Kubernetes troubleshooting |
| helm | Optional host-side chart validation |
| jq | Pretty-printing Kubernetes and Prometheus API JSON outputs |
| curl | Testing HTTP endpoints and Prometheus queries |

In this project, the main Kubernetes operations are executed from the first control-plane node using `/etc/kubernetes/admin.conf`. Therefore, `kubectl` and `helm` on the host are useful but not strictly required for the automated workflow.

---

## 3. Virtualization Provider

The lab can run with different Vagrant providers, but the tested and preferred provider for this setup is:

```text
libvirt
```

VirtualBox can also be used if it is supported by the host operating system and Vagrant version. However, running VirtualBox and KVM/libvirt at the same time can cause virtualization conflicts on Linux hosts.

Recommended approach:

```text
Use one virtualization provider consistently for the lab.
```

For Linux hosts, libvirt is usually the cleaner option when KVM is already available.

---

## 4. Vagrant Box

The default guest operating system is Ubuntu 22.04 LTS.

The Vagrant box can be overridden through an environment variable if required:

```bash
K8S_BOX=generic/ubuntu2204 vagrant up --provider=libvirt
```

This makes the Vagrantfile more portable because the box can be changed without editing the Vagrantfile directly.

The selected box must meet these requirements:

- systemd-based Linux distribution
- SSH access through Vagrant
- support for containerd and Kubernetes packages
- predictable network interface behavior
- compatible with the selected Vagrant provider

---

## 5. Network Requirements

The lab separates management traffic and workload traffic.

| Network | CIDR | Purpose |
|---|---|---|
| Management network | `192.168.100.0/24` | SSH, Ansible, Kubernetes node IPs, control-plane communication |
| Workload network | `192.168.200.0/24` | LoadBalancer IPs and workload-facing traffic |
| Pod network | `10.244.0.0/16` | Kubernetes Pod CIDR used by Calico |
| Service network | `10.96.0.0/12` | Kubernetes ClusterIP Service CIDR |

The Kubernetes API virtual IP is placed on the management network:

```text
192.168.100.10
```

The sample application is exposed through MetalLB on the workload network:

```text
192.168.200.240
```

The host machine must be able to reach both Vagrant host-only networks if direct testing from the host is required.

---

## 6. Internet Access and Proxy Requirements

The lab needs internet access for:

- OS package installation
- Kubernetes package installation
- container image pulls
- Helm chart downloads
- GitHub or Helm repository access

In restricted or slow internet environments, it is recommended to pre-pull or cache external dependencies.

This project separates image pulling from component installation where possible. This makes the installation more predictable and easier to troubleshoot.

Recommended enterprise approach:

```text
Use an internal package repository, internal container registry, and internal Helm chart repository.
```

For environments that require an HTTP/HTTPS proxy, the proxy should be configured consistently for:

- host package managers
- Vagrant box downloads
- guest OS package managers
- containerd image pulls
- Helm chart downloads

---

## 7. SSH and Ansible Assumptions

Ansible connects to the Vagrant-created machines over SSH using the management network.

The inventory is expected to contain groups similar to:

```ini
[kube_masters]
k8s-master-1
k8s-master-2
k8s-master-3

[kube_workers]
k8s-worker-1
k8s-worker-2

[kube_cluster:children]
kube_masters
kube_workers
```

The project uses `kube_masters` as the control-plane inventory group name.

Most cluster bootstrapping operations are executed from the first control-plane node:

```text
groups['kube_masters'][0]
```

This is acceptable for the lab, but the documentation should clearly state that the first control-plane node acts as the orchestration entry point for cluster add-on installation.

---

## 8. Software Version Assumptions

The current lab has been built around these component choices:

| Component | Role in the Lab |
|---|---|
| Ubuntu 22.04 LTS | Guest operating system |
| containerd | Kubernetes container runtime |
| kubeadm | Kubernetes cluster bootstrap |
| kubelet | Kubernetes node agent |
| kubectl | Kubernetes CLI |
| Calico | Kubernetes CNI plugin |
| HAProxy | Local API server load balancer on control-plane nodes |
| Keepalived | Kubernetes API virtual IP failover |
| MetalLB | LoadBalancer implementation for bare-metal/local lab |
| Helm | Application and add-on deployment |
| Metrics Server | Resource metrics for Kubernetes |
| Prometheus | Metrics collection and PromQL query engine |
| Prometheus Adapter | Custom Metrics API provider for HPA |
| nginx-prometheus-exporter | Nginx metrics exporter for the sample application |

For reproducibility, Kubernetes packages, Helm chart versions, and container image versions should be pinned in Ansible variables.

---

## 9. Naming Assumptions

The sample application Helm release name is:

```text
k8s-lab
```

The chart name is:

```text
sample-webapp
```

Therefore, Helm-generated application resources follow this naming pattern:

```text
<release-name>-<chart-name>
```

Expected names:

| Resource | Name |
|---|---|
| Main application Deployment | `k8s-lab-sample-webapp` |
| Main application Service | `k8s-lab-sample-webapp` |
| Metrics Service | `k8s-lab-sample-webapp-metrics` |
| Prometheus scrape target | `k8s-lab-sample-webapp-metrics.demo.svc.cluster.local:9113` |

This naming strategy avoids duplicated names like `sample-webapp-sample-webapp` while still following Helm-native release naming behavior.

---

## 10. Recommended Pre-Flight Checks

Before running the full deployment, validate the host environment.

Check Vagrant:

```bash
vagrant --version
```

Check the selected Vagrant provider:

```bash
vagrant plugin list
```

For libvirt-based runs, verify libvirt is available:

```bash
virsh list --all
```

Check Ansible:

```bash
ansible --version
```

Check that the project inventory is readable:

```bash
cd ansible
ansible-inventory -i inventory.ini --list
```

Validate Ansible syntax:

```bash
ansible-playbook site.yml --syntax-check
```

After VMs are created, verify SSH connectivity:

```bash
ansible all -m ping
```

## 11. Summary

The prerequisites for this lab are intentionally lightweight enough to run on a local workstation, but the architecture is designed to demonstrate enterprise-oriented Kubernetes concepts:

- separated VM provisioning and cluster configuration
- HA control-plane design
- separated management and workload networks
- CNI-based Pod networking
- LoadBalancer support with MetalLB
- Helm-based application deployment
- Prometheus-based custom metrics
- HPA with Kubernetes Custom Metrics API
- least-privilege RBAC user for application visibility

Once these prerequisites are met, the cluster can be provisioned using Vagrant and configured using Ansible.
