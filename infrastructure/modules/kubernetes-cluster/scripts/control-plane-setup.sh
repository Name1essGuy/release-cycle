#!/bin/bash
# modules/kubernetes-cluster/scripts/control-plane-setup.sh

set -e

# ============================================================================
# Переменные из Terraform
# ============================================================================

kubernetes_version="${kubernetes_version}"
pod_network_cidr="${pod_network_cidr}"
service_network_cidr="${service_network_cidr}"
cluster_name="${cluster_name}"
environment="${environment}"

# ============================================================================
# Логирование
# ============================================================================

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "🚀 Starting Kubernetes control-plane setup for $environment"

# ============================================================================
# 0. Отключение unattended-upgrades и освобождение блокировки
# ============================================================================

echo "🔓 Disabling unattended-upgrades to free dpkg lock..."

# Останавливаем сервис
sudo systemctl stop unattended-upgrades

# Ждём, пока освободится блокировка
while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
  echo "⏳ Waiting for dpkg lock to be released..."
  sleep 5
done

# Удаляем блокировочные файлы
sudo rm -f /var/lib/dpkg/lock-frontend
sudo rm -f /var/lib/dpkg/lock
sudo dpkg --configure -a

echo "✅ Dpkg lock released"

# ============================================================================
# 1. Отключение swap (обязательно для Kubernetes)
# ============================================================================

echo "ℹ️ Disabling swap..."
swapoff -a
sed -i '/swap/d' /etc/fstab

# ============================================================================
# 2. Настройка модулей ядра
# ============================================================================

echo "ℹ️ Configuring kernel modules..."
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# ============================================================================
# 3. Настройка sysctl
# ============================================================================

echo "ℹ️ Configuring sysctl..."
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# ============================================================================
# 4. Установка container runtime (containerd)
# ============================================================================

echo "ℹ️ Installing containerd..."

apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release

# Добавляем репозиторий Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Устанавливаем containerd
apt-get update -y
apt-get install -y containerd.io

# Настраиваем containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

# ============================================================================
# 5. Установка kubeadm, kubelet, kubectl
# ============================================================================

echo "ℹ️ Installing Kubernetes components..."

# Добавляем репозиторий Kubernetes
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update -y

# Устанавливаем конкретную версию
apt-get install -y \
    kubelet=${kubernetes_version}-1.1 \
    kubeadm=${kubernetes_version}-1.1 \
    kubectl=${kubernetes_version}-1.1

# Блокируем автоматическое обновление
apt-mark hold kubelet kubeadm kubectl

# ============================================================================
# 6. Инициализация кластера
# ============================================================================

echo "🔧 Initializing Kubernetes cluster..."

# Создаём конфигурацию kubeadm
cat > /root/kubeadm-init.yaml << EOF
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
controlPlaneEndpoint: "$(hostname -f):6443"
networking:
  serviceSubnet: "${service_network_cidr}"
  podSubnet: "${pod_network_cidr}"
  dnsDomain: "cluster.local"
apiServer:
  certSANs:
  - "$(hostname -f)"
  - "localhost"
  - "127.0.0.1"
  - "$(hostname -f).local"
  - "$(hostname -f).${environment}.local"
EOF

# Инициализируем кластер
kubeadm init --config=/root/kubeadm-init.yaml --upload-certs

# ============================================================================
# 7. Настройка kubectl для пользователя ubuntu
# ============================================================================

echo "🔧 Configuring kubectl..."

mkdir -p /home/ubuntu/.kube
cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube

mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config

# ============================================================================
# 8. Установка сетевого плагина Flannel (ВМЕСТО CALICO)
# ============================================================================

echo "🌐 Installing Flannel network plugin..."

# Ждём, пока API сервер станет доступен
sleep 10

# Устанавливаем Flannel
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Ждём, пока Flannel запустится
echo "⏳ Waiting for Flannel to be ready..."
sleep 30
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n kube-flannel 2>/dev/null || echo "Flannel pods are starting..."

# ============================================================================
# 9. Генерация join-команды для worker-нод
# ============================================================================

echo "🔑 Generating join token..."

# Создаём бессрочный токен и сохраняем команду
kubeadm token create --ttl 0 --print-join-command > /home/ubuntu/join-command.txt
chown ubuntu:ubuntu /home/ubuntu/join-command.txt
cp /home/ubuntu/join-command.txt /root/join-command.txt

# Для автоматизации: сохраняем в /tmp для Terraform
cp /home/ubuntu/join-command.txt /tmp/join-command.txt
chmod 644 /tmp/join-command.txt

# ============================================================================
# 10. Установка дополнительных утилит
# ============================================================================

echo "🔧 Installing additional tools..."

# Helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# kubectl (уже установлен, но проверяем)
kubectl version --client

# ============================================================================
# 11. Проверка статуса кластера
# ============================================================================

echo "📋 Cluster status:"
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A

# ============================================================================
# Информация о завершении
# ============================================================================

echo "=========================================="
echo "✅ Kubernetes control-plane setup completed!"
echo "   Environment: ${environment}"
echo "   Cluster name: ${cluster_name}"
echo "   Kubernetes version: v${kubernetes_version}"
echo "   Pod network CIDR: ${pod_network_cidr}"
echo "   Service network CIDR: ${service_network_cidr}"
echo "=========================================="

echo "📋 Join command for workers:"
cat /home/ubuntu/join-command.txt

echo "🎉 Cluster initialization complete!"