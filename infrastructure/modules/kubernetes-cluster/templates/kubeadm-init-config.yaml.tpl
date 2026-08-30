apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "0.0.0.0"
  bindPort: 6443
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
clusterName: ${cluster_name}
kubernetesVersion: v${kubernetes_version}
controlPlaneEndpoint: "${hostname}:6443"
networking:
  serviceSubnet: "${service_network_cidr}"
  podSubnet: "${pod_network_cidr}"
  dnsDomain: "cluster.local"
apiServer:
  certSANs:
  - "${hostname}"
  - "localhost"
  - "127.0.0.1"
  - "${hostname}.local"
  - "${hostname}.${environment}.local"