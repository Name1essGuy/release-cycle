#!/bin/bash
# modules/kubernetes-cluster/scripts/worker-setup.sh

set -e

# ============================================================================
# Переменные из Terraform
# ============================================================================

kubernetes_version="${kubernetes_version}"
control_plane_ip="${control_plane_ip}"
environment="${environment}"
join_command="${join_command}"

# ============================================================================
# Логирование
# ============================================================================

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "🚀 Starting Kubernetes worker setup for $environment"

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
# 1. Отключение swap
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

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y containerd.io

mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

# ============================================================================
# 5. Установка kubeadm, kubelet, kubectl
# ============================================================================

echo "ℹ️ Installing Kubernetes components..."

# Добавляем репозиторий Kubernetes (НОВЫЙ способ)
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update -y
apt-get install -y \
    kubelet=${kubernetes_version}-1.1 \
    kubeadm=${kubernetes_version}-1.1 \
    kubectl=${kubernetes_version}-1.1

apt-mark hold kubelet kubeadm kubectl

# ============================================================================
# 6. Ожидание готовности control-plane
# ============================================================================

echo "⏳ Waiting for control-plane to be ready..."
sleep 30

# ============================================================================
# 7. Присоединение к кластеру
# ============================================================================

echo "ℹ️ Joining cluster..."

# Проверяем, что join_command передан
if [ -n "${join_command}" ]; then
    echo "ℹ️ Using provided join command from Terraform..."
    
    # Выполняем join-команду
    eval "${join_command}"
    
    # Проверяем успешность
    if [ $? -eq 0 ]; then
        echo "✅ Successfully joined the cluster!"
    else
        echo "❌ Failed to join cluster. Check logs: journalctl -u kubelet"
        exit 1
    fi
else
    echo "⚠️ No join command provided. Trying to get from control-plane via SSH (legacy method)..."
    
    # Fallback: пытаемся получить через SSH (старый способ)
    for i in {1..10}; do
        if scp -o StrictHostKeyChecking=no ubuntu@${control_plane_ip}:/home/ubuntu/join-command.txt /tmp/join-command.txt 2>/dev/null; then
            break
        fi
        echo "Attempt $i: Waiting for join-command.txt..."
        sleep 10
    done

    if [ -f /tmp/join-command.txt ]; then
        echo "ℹ️ Joining using join-command.txt from control-plane..."
        bash /tmp/join-command.txt
    else
        echo "❌ Failed to get join command. Please run manually:"
        echo "sudo kubeadm join <IP>:6443 --token ..."
        exit 1
    fi
fi

# ============================================================================
# 8. Проверка статуса kubelet
# ============================================================================

sleep 10
if systemctl is-active --quiet kubelet; then
    echo "✅ kubelet is active and running!"
else
    echo "⚠️ Warning: kubelet is not active. Check logs: journalctl -u kubelet"
fi

# ============================================================================
# Информация о завершении
# ============================================================================

echo "=========================================="
echo "✅ Kubernetes worker setup completed!"
echo "   Environment: ${environment}"
echo "   Control plane IP: ${control_plane_ip}"
echo "=========================================="

echo "🎉 Worker setup complete!"