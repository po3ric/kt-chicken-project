#!/usr/bin/env bash

# ============================================================
# KT Cloud Chicken Team - Kubernetes 공통 환경 구성
# ============================================================
# 목적: Kubernetes 설치를 위한 Linux 기본 환경 설정
# 대상: Master EC2 / Worker EC2
# 실행: sudo bash k8s-init.sh
# 설치: Swap, 커널/네트워크 설정, containerd
# 주의: kubeadm, kubelet, kubectl은 별도 설치 예정
# 주의: 기존 containerd 설정 파일을 덮어쓸 수 있음
# ============================================================

set -euo pipefail

echo "===== Kubernetes 공통 환경 구성 ====="

# 1. 관리자 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: sudo 권한으로 실행하세요."
    exit 1
fi

# 2. Swap 비활성화
echo "[1] Swap 설정"
swapoff -a
sed -i.bak '/^[^#].*[[:space:]]swap[[:space:]]/s/^/#/' /etc/fstab

# 3. 커널 모듈 설정
echo "[2] Kernel Modules"
cat > /etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# 4. 네트워크 설정
echo "[3] Network"
cat > /etc/sysctl.d/99-kubernetes.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system

# 5. containerd 설치
echo "[4] containerd"
apt-get update
apt-get install -y containerd

# 6. containerd 설정
echo "[5] containerd Configuration"
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' \
    /etc/containerd/config.toml

systemctl enable --now containerd
systemctl restart containerd

# 7. 설치 확인
echo "[6] Verification"
containerd --version
systemctl is-active containerd

echo "===== 공통 환경 구성 완료 ====="