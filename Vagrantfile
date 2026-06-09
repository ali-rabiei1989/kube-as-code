# -*- mode: ruby -*-
# vi: set ft=ruby :

K8S_BOX = ENV.fetch("K8S_BOX", "generic/ubuntu2204")

MGMT_NETWORK_PREFIX     = ENV.fetch("MGMT_NETWORK_PREFIX", "192.168.100")
WORKLOAD_NETWORK_PREFIX = ENV.fetch("WORKLOAD_NETWORK_PREFIX", "192.168.200")

K8S_API_VIP = ENV.fetch("K8S_API_VIP", "#{MGMT_NETWORK_PREFIX}.10")

MASTER_CPUS   = ENV.fetch("MASTER_CPUS", "2").to_i
MASTER_MEMORY = ENV.fetch("MASTER_MEMORY", "2048").to_i

WORKER_CPUS   = ENV.fetch("WORKER_CPUS", "2").to_i
WORKER_MEMORY = ENV.fetch("WORKER_MEMORY", "2048").to_i

NODES = [
  {
    name: "master-1",
    role: "master",
    mgmt_ip: "#{MGMT_NETWORK_PREFIX}.11",
    workload_ip: "#{WORKLOAD_NETWORK_PREFIX}.11",
    cpus: MASTER_CPUS,
    memory: MASTER_MEMORY
  },
  {
    name: "master-2",
    role: "master",
    mgmt_ip: "#{MGMT_NETWORK_PREFIX}.12",
    workload_ip: "#{WORKLOAD_NETWORK_PREFIX}.12",
    cpus: MASTER_CPUS,
    memory: MASTER_MEMORY
  },
  {
    name: "master-3",
    role: "master",
    mgmt_ip: "#{MGMT_NETWORK_PREFIX}.13",
    workload_ip: "#{WORKLOAD_NETWORK_PREFIX}.13",
    cpus: MASTER_CPUS,
    memory: MASTER_MEMORY
  },
  {
    name: "worker-1",
    role: "worker",
    mgmt_ip: "#{MGMT_NETWORK_PREFIX}.21",
    workload_ip: "#{WORKLOAD_NETWORK_PREFIX}.21",
    cpus: WORKER_CPUS,
    memory: WORKER_MEMORY
  },
  {
    name: "worker-2",
    role: "worker",
    mgmt_ip: "#{MGMT_NETWORK_PREFIX}.22",
    workload_ip: "#{WORKLOAD_NETWORK_PREFIX}.22",
    cpus: WORKER_CPUS,
    memory: WORKER_MEMORY
  }
]

Vagrant.configure("2") do |config|
  config.vm.box = K8S_BOX

  config.ssh.insert_key = false
  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.vm.boot_timeout = 600

  NODES.each do |node|
    config.vm.define node[:name] do |node_config|
      node_config.vm.hostname = node[:name]

      node_config.vm.network "private_network", ip: node[:mgmt_ip]

      node_config.vm.network "private_network", ip: node[:workload_ip]

      node_config.vm.provider "libvirt" do |lv|
        lv.driver = "kvm"

        lv.cpus = node[:cpus]
        lv.memory = node[:memory]

        lv.default_prefix = "k8s-"

        lv.disk_bus = "virtio"
        lv.nic_model_type = "virtio"
        lv.cpu_mode = "host-passthrough"
        lv.machine_type = "pc"

        lv.graphics_type = "vnc"
      end

      node_config.vm.provider "virtualbox" do |vb|
        vb.name = node[:name]
        vb.cpus = node[:cpus]
        vb.memory = node[:memory]

        vb.customize ["modifyvm", :id, "--ioapic", "on"]
        vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
        vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
      end
    end
  end
end