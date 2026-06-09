# 10 - Troubleshooting Commands

This document is a compact troubleshooting command reference for the Kubernetes lab.

Use it when you need to quickly check the health of a specific component.

---

## 1. General Cluster Checks

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get svc -A -o wide
kubectl get events -A --sort-by=.metadata.creationTimestamp | tail -100
helm list -A
```

---

## 2. Vagrant and VM Checks

```bash
vagrant status
vagrant ssh k8s-master-1
vagrant ssh k8s-worker-1
```

For libvirt:

```bash
virsh list --all
virsh dominfo k8s-master-1
```

---

## 3. Ansible Checks

```bash
cd ansible

ansible all -m ping
ansible-playbook site.yml --syntax-check
ansible-playbook site.yml --list-tags
```

Run a specific stage:

```bash
ansible-playbook site.yml --tags sample_app
ansible-playbook site.yml --tags prometheus
ansible-playbook site.yml --tags prometheus_adapter
ansible-playbook site.yml --tags hpa
```

---

## 4. Node and Kubelet Checks

On a node:

```bash
systemctl status kubelet --no-pager
journalctl -u kubelet -n 100 --no-pager
systemctl status containerd --no-pager
crictl ps -a
```

From Kubernetes:

```bash
kubectl describe node <node-name>
kubectl get pods -n kube-system -o wide
```

---

## 5. Control Plane Checks

```bash
kubectl get pods -n kube-system -o wide | grep -E 'kube-apiserver|kube-controller-manager|kube-scheduler|etcd'
curl -k https://192.168.100.10:6443/version
```

Static Pod logs:

```bash
kubectl logs -n kube-system kube-apiserver-k8s-master-1 --tail=100
kubectl logs -n kube-system kube-controller-manager-k8s-master-1 --tail=100
kubectl logs -n kube-system kube-scheduler-k8s-master-1 --tail=100
kubectl logs -n kube-system etcd-k8s-master-1 --tail=100
```

---

## 6. HAProxy and Keepalived Checks

```bash
ansible kube_masters -m shell -a "systemctl is-active haproxy"
ansible kube_masters -m shell -a "systemctl is-active keepalived"
ansible kube_masters -m shell -a "ip addr | grep 192.168.100.10 || true"
```

On a master:

```bash
systemctl status haproxy --no-pager
systemctl status keepalived --no-pager
journalctl -u haproxy -n 100 --no-pager
journalctl -u keepalived -n 100 --no-pager
```

---

## 7. DNS and CoreDNS Checks

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
kubectl logs -n kube-system deploy/coredns --tail=100
kubectl get cm -n kube-system coredns -o yaml
```

DNS test:

```bash
kubectl run dns-test --image=busybox:1.36 --restart=Never --rm -it -- nslookup kubernetes.default.svc.cluster.local
```

---

## 8. Calico Checks

```bash
kubectl get pods -A | grep -i calico
kubectl get nodes -o wide
```

Logs:

```bash
kubectl logs -n calico-system -l k8s-app=calico-node --tail=100
kubectl logs -n kube-system -l k8s-app=calico-node --tail=100
```

Pod-to-Pod test:

```bash
kubectl run test-a --image=busybox:1.36 --restart=Never -- sleep 3600
kubectl run test-b --image=busybox:1.36 --restart=Never -- sleep 3600
kubectl get pods -o wide
kubectl delete pod test-a test-b --ignore-not-found
```

---

## 9. MetalLB Checks

```bash
kubectl get pods -n metallb-system -o wide
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
kubectl get svc -n demo -o wide
kubectl describe svc -n demo k8s-lab-sample-webapp
```

---

## 10. Sample Application Checks

```bash
kubectl get all -n demo -o wide
kubectl get pods -n demo
kubectl get svc -n demo
kubectl get endpoints -n demo
helm list -n demo
helm status k8s-lab -n demo
```

Application test:

```bash
curl -i http://192.168.200.240/
curl -i http://192.168.200.240/healthz
curl -i http://192.168.200.240/readyz
```

Logs:

```bash
kubectl logs -n demo deploy/k8s-lab-sample-webapp -c nginx --tail=100
kubectl logs -n demo deploy/k8s-lab-sample-webapp -c nginx-exporter --tail=100
```

---

## 11. Metrics Service Checks

```bash
kubectl get svc -n demo k8s-lab-sample-webapp-metrics -o wide
kubectl get endpoints -n demo k8s-lab-sample-webapp-metrics
```

Direct metrics test:

```bash
METRICS_IP=$(kubectl -n demo get svc k8s-lab-sample-webapp-metrics -o jsonpath='{.spec.clusterIP}')

curl -s http://${METRICS_IP}:9113/metrics | grep nginx_http_requests_total
curl -s http://${METRICS_IP}:9113/metrics | grep '^nginx_'
```

---

## 12. Metrics Server Checks

```bash
kubectl get pods -n kube-system | grep metrics-server
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top nodes
kubectl top pods -A
kubectl logs -n kube-system deploy/metrics-server --tail=100
```

---

## 13. Prometheus Checks

```bash
kubectl get pods -n monitoring | grep prometheus-server
kubectl get svc -n monitoring prometheus-server
kubectl get cm -n monitoring prometheus-server -o yaml
kubectl logs -n monitoring deploy/prometheus-server -c prometheus-server --tail=100
```

Previous crash log:

```bash
POD=$(kubectl get pod -n monitoring -l app.kubernetes.io/component=server -o jsonpath='{.items[0].metadata.name}')

kubectl logs -n monitoring ${POD} -c prometheus-server --previous
```

Config check:

```bash
kubectl -n monitoring get cm prometheus-server -o jsonpath='{.data.prometheus\.yml}' > /tmp/prometheus.yml

grep -nE "global:|job_name:|sample-webapp|scrape_interval" /tmp/prometheus.yml
```

---

## 14. Prometheus Query Checks

```bash
PROM_IP=$(kubectl -n monitoring get svc prometheus-server -o jsonpath='{.spec.clusterIP}')
```

Raw counter:

```bash
curl -s "http://${PROM_IP}/api/v1/query?query=nginx_http_requests_total" | jq
```

Request rate:

```bash
curl -s "http://${PROM_IP}/api/v1/query?query=sum%28rate%28nginx_http_requests_total%7Bnamespace%3D%22demo%22%2Cservice%3D%22k8s-lab-sample-webapp%22%7D%5B2m%5D%29%29" | jq
```

Target health:

```bash
curl -s "http://${PROM_IP}/api/v1/targets?state=any" | jq '.data.activeTargets[] | select(.labels.job=="sample-webapp") | {job: .labels.job, health: .health, scrapeUrl: .scrapeUrl, lastError: .lastError}'
```

Actual metric labels:

```bash
curl -s "http://${PROM_IP}/api/v1/query?query=nginx_http_requests_total" | jq '.data.result[].metric'
```

---

## 15. Prometheus Adapter Checks

```bash
kubectl get pods -n monitoring | grep prometheus-adapter
kubectl get svc -n monitoring prometheus-adapter
kubectl get apiservice v1beta1.custom.metrics.k8s.io
kubectl logs -n monitoring deploy/prometheus-adapter --tail=100
```

Deployment args:

```bash
kubectl -n monitoring get deploy prometheus-adapter -o yaml | grep -E "metrics-relist|max-age|prometheus-url" -A2 -B2
```

List custom metrics:

```bash
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq
```

Query application custom metric:

```bash
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1/namespaces/demo/services/k8s-lab-sample-webapp/nginx_http_requests_per_second | jq
```

---

## 16. HPA Checks

```bash
kubectl get hpa -n demo
kubectl describe hpa -n demo sample-webapp-hpa
kubectl get hpa -n demo sample-webapp-hpa -o yaml
```

Watch HPA and Deployment:

```bash
watch -n 2 'kubectl get hpa -n demo; echo; kubectl get deploy -n demo k8s-lab-sample-webapp'
```

Check current metric from HPA status:

```bash
kubectl get hpa -n demo sample-webapp-hpa -o jsonpath='{.status.currentMetrics[0].object.current.averageValue}'
echo
```

---

## 17. Load Generator Checks

Start load:

```bash
WORKERS=10 APP_URL=http://192.168.200.240 ./scripts/load-test.sh start
```

Status:

```bash
./scripts/load-test.sh status
```

Stop load:

```bash
./scripts/load-test.sh stop
```

Find manual curl loops:

```bash
pgrep -af "curl.*192.168.200.240"
```

Stop manual curl loops:

```bash
pkill -f "curl.*192.168.200.240" || true
```

---

## 18. RBAC Checks

Check RBAC objects:

```bash
kubectl get role -n demo
kubectl get rolebinding -n demo
kubectl get role -n demo app-viewer -o yaml
kubectl get rolebinding -n demo app-viewer -o yaml
```

Allowed access:

```bash
sudo kubectl --kubeconfig=/opt/kubernetes/users/app-viewer/app-viewer.kubeconfig get pods -n demo
sudo kubectl --kubeconfig=/opt/kubernetes/users/app-viewer/app-viewer.kubeconfig get svc -n demo
sudo kubectl --kubeconfig=/opt/kubernetes/users/app-viewer/app-viewer.kubeconfig logs -n demo deploy/k8s-lab-sample-webapp --tail=20
```

Denied access:

```bash
sudo kubectl --kubeconfig=/opt/kubernetes/users/app-viewer/app-viewer.kubeconfig get nodes
sudo kubectl --kubeconfig=/opt/kubernetes/users/app-viewer/app-viewer.kubeconfig get secrets -n demo
```

Auth checks:

```bash
sudo kubectl --kubeconfig=/opt/kubernetes/users/app-viewer/app-viewer.kubeconfig auth can-i get pods -n demo
sudo kubectl --kubeconfig=/opt/kubernetes/users/app-viewer/app-viewer.kubeconfig auth can-i get nodes
sudo kubectl --kubeconfig=/opt/kubernetes/users/app-viewer/app-viewer.kubeconfig auth can-i get secrets -n demo
```

---

## 19. Helm Checks

```bash
helm list -A
helm list -n demo
helm status k8s-lab -n demo
helm get values k8s-lab -n demo
helm get manifest k8s-lab -n demo
```

Uninstall application release:

```bash
helm uninstall k8s-lab -n demo --kubeconfig /etc/kubernetes/admin.conf
```

---

## 20. Image and Runtime Checks

```bash
crictl images
crictl ps -a
ctr -n k8s.io images list
```

Check specific images:

```bash
ctr -n k8s.io images list | grep nginx
ctr -n k8s.io images list | grep prometheus
ctr -n k8s.io images list | grep metallb
ctr -n k8s.io images list | grep calico
```

---

## 21. Restart Commands

Restart sample app:

```bash
kubectl rollout restart deployment -n demo k8s-lab-sample-webapp
kubectl rollout status deployment -n demo k8s-lab-sample-webapp
```

Restart Prometheus:

```bash
kubectl rollout restart deployment -n monitoring prometheus-server
kubectl rollout status deployment -n monitoring prometheus-server
```

Restart Prometheus Adapter:

```bash
kubectl rollout restart deployment -n monitoring prometheus-adapter
kubectl rollout status deployment -n monitoring prometheus-adapter
```

Restart Metrics Server:

```bash
kubectl rollout restart deployment -n kube-system metrics-server
kubectl rollout status deployment -n kube-system metrics-server
```

Restart CoreDNS:

```bash
kubectl rollout restart deployment -n kube-system coredns
kubectl rollout status deployment -n kube-system coredns
```

---

## 22. Re-run Common Recovery Stages

Application stack:

```bash
cd ansible
ansible-playbook site.yml --tags sample_app
ansible-playbook site.yml --tags prometheus
ansible-playbook site.yml --tags prometheus_adapter
ansible-playbook site.yml --tags hpa
```

Monitoring stack:

```bash
cd ansible
ansible-playbook site.yml --tags metrics_server
ansible-playbook site.yml --tags prometheus
ansible-playbook site.yml --tags prometheus_adapter
```

Networking stack:

```bash
cd ansible
ansible-playbook site.yml --tags calico
ansible-playbook site.yml --tags metallb
```

HA stack:

```bash
cd ansible
ansible-playbook site.yml --tags ha
```

RBAC:

```bash
cd ansible
ansible-playbook site.yml --tags rbac
```

---

## 23. Final Health Checklist

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
curl -i http://192.168.200.240/
```
