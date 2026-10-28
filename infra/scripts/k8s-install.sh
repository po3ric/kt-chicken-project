
#!/usr/bin/env bash

# ============================================================
# KT Cloud Chicken Team - Kubernetes 패키지 설치
# ============================================================
# 목적: kubelet, kubeadm, kubectl 설치
# 대상: Ubuntu 24.04 Master EC2 / Worker EC2
# 버전: Kubernetes v1.36.5
#
# 실행 순서:
#   1. sudo bash k8s-init.sh
#   2. sudo bash k8s-install.sh
#
# 주의:
# - Master와 Worker 모두 실행
# - kubeadm init / join은 여기서 실행하지 않음
# - 기존 Kubernetes 노드에서는 재설치하지 않음
# ============================================================

set -euo pipefail

K8S_VERSION="1.36.5"
K8S_REPO_VERSION="v1.36"

echo "===== Kubernetes 패키지 설치 ====="

# 1. 관리자 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: sudo bash k8s-install.sh 로 실행하세요."
    exit 1
fi

# 2. 기존 클러스터 보호
if [ -f /etc/kubernetes/kubelet.conf ] || \
   [ -f /etc/kubernetes/admin.conf ]; then
    echo "ERROR: 이미 Kubernetes가 구성된 노드입니다."
    exit 1
fi

# 3. containerd 확인
echo "[1/5] containerd 확인"

if ! systemctl is-active --quiet containerd; then
    echo "ERROR: containerd가 실행 중이지 않습니다."
    echo "먼저 k8s-init.sh를 실행하세요."
    exit 1
fi

# 4. Kubernetes 패키지 저장소 등록
echo "[2/5] Kubernetes 저장소 설정"

apt-get update
apt-get install -y apt-transport-https ca-certificates curl gpg

install -m 0755 -d /etc/apt/keyrings

curl -fsSL \
  "https://pkgs.k8s.io/core:/stable:/${K8S_REPO_VERSION}/deb/Release.key" \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_REPO_VERSION}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list

# 5. Kubernetes 패키지 설치
echo "[3/5] Kubernetes 패키지 설치"

apt-get update

apt-get install -y \
  "kubelet=${K8S_VERSION}-1.1" \
  "kubeadm=${K8S_VERSION}-1.1" \
  "kubectl=${K8S_VERSION}-1.1"

# 6. 버전 고정
echo "[4/5] Kubernetes 버전 고정"

apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet

# 7. 설치 검증
echo "[5/5] 설치 확인"

echo "- kubeadm:"
kubeadm version -o short

echo "- kubelet:"
kubelet --version

echo "- kubectl:"
kubectl version --client

echo "- 패키지 고정:"
apt-mark showhold | grep -E '^(kubelet|kubeadm|kubectl)$'

echo "===== Kubernetes 패키지 설치 완료 ====="
echo "다음 단계: Master는 kubeadm init, Worker는 kubeadm join"
