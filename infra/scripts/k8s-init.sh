#!/usr/bin/env bash

# ============================================================
# KT Cloud Chicken Team - Kubernetes 공통 환경 구성
# ============================================================
# 목적: Kubernetes 설치 전 Linux / containerd 환경 설정
# 대상: Ubuntu 24.04 Master EC2 / Worker EC2
# 실행: sudo bash k8s-init.sh
#
# 주요 작업:
#   1. Swap 비활성화
#   2. Kubernetes 커널 모듈 설정
#   3. 네트워크 커널 설정
#   4. containerd 설치 및 systemd cgroup 설정
#   5. 설정 검증
#
# 주의:
# - 신규 서버용이니 이미 실행 중인 Kubernetes 노드에서는 실행하지 마세요.
# - 기존 containerd 설정은 덮어쓰지 않습니다.
# - kubeadm / kubelet / kubectl은 별도 설치합니다.
# ============================================================

set -euo pipefail

echo "===== Kubernetes 공통 환경 구성 ====="

# 1. root 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: sudo bash k8s-init.sh 로 실행하세요."
    exit 1
fi

# 기존 Kubernetes 노드 보호
if [ -f /etc/kubernetes/kubelet.conf ] || \
   [ -f /etc/kubernetes/admin.conf ]; then
    echo "ERROR: 이미 Kubernetes가 구성된 노드입니다."
    echo "기존 클러스터 보호를 위해 실행을 중단합니다."
    exit 1
fi

# 2. Swap 비활성화
echo "[1/5] Swap 설정"

swapoff -a

# /etc/fstab 백업 후 swap 항목 주석 처리
if ! [ -f /etc/fstab.k8s-backup ]; then
    cp /etc/fstab /etc/fstab.k8s-backup
fi

sed -i '/^[[:space:]]*[^#[:space:]].*[[:space:]]swap[[:space:]]/s/^[[:space:]]*/# /' /etc/fstab

# 3. 커널 모듈 설정
echo "[2/5] Kernel Modules"

cat > /etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# 4. 네트워크 설정
echo "[3/5] Network"

cat > /etc/sysctl.d/99-kubernetes.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system

# 5. containerd 설치 및 설정
echo "[4/5] containerd"

if ! command -v containerd >/dev/null 2>&1; then
    apt-get update
    apt-get install -y containerd
fi

mkdir -p /etc/containerd

# 기존 설정을 보존하고, 최초 설치 시에만 기본 설정 생성
if [ ! -f /etc/containerd/config.toml ]; then
    containerd config default > /etc/containerd/config.toml
fi

# SystemdCgroup을 true로 설정
# 기존 설정에 해당 항목이 있을 때만 변경
if grep -Eq '^[[:space:]]*SystemdCgroup[[:space:]]*=' \
    /etc/containerd/config.toml; then

    cp /etc/containerd/config.toml \
       /etc/containerd/config.toml.k8s-backup

    sed -i -E \
      's/^([[:space:]]*SystemdCgroup[[:space:]]*=[[:space:]]*).*/\1true/' \
      /etc/containerd/config.toml
else
    echo "ERROR: SystemdCgroup 설정을 찾지 못했습니다."
    echo "containerd 설정 파일을 확인하세요."
    exit 1
fi

systemctl enable --now containerd
systemctl restart containerd

# 6. 검증
echo "[5/5] Verification"

echo "- Swap:"
swapon --show

echo "- containerd:"
containerd --version

echo "- containerd service:"
systemctl is-active --quiet containerd
echo "active"

echo "- SystemdCgroup:"
grep -E '^[[:space:]]*SystemdCgroup[[:space:]]*=' \
    /etc/containerd/config.toml

echo "===== Kubernetes 공통 환경 구성 완료 ====="
