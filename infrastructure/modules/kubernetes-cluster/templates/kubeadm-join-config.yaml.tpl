apiVersion: kubeadm.k8s.io/v1beta3
kind: JoinConfiguration
discovery:
  bootstrapToken:
    apiServerEndpoint: "${control_plane_ip}:6443"
    token: "${token}"
    caCertHashes:
    - "${ca_cert_hash}"
  tlsBootstrapToken: "${token}"
nodeRegistration:
  name: "${hostname}"
  kubeletExtraArgs:
    node-labels: "node-role.kubernetes.io/worker="