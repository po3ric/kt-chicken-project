
#!/usr/bin/env bash

# ============================================================
# KT Cloud Chicken Team - Kubernetes Worker Join
# ============================================================
# 목적: Worker EC2를 Master Kubernetes 클러스터에 연결
# 대상: Ubuntu 24.04 Worker EC2 전용
#
# 사전 조건:
#   1. k8s-init.sh 실행 완료
#   2. k8s-install.sh 실행 완료
#   3. Master에서 kubeadm init 완료
#   4. Master와 Worker 간 네트워크 통신 가능
#
# 사용 방법:
#   Master에서 Join 명령어 생성:
#     sudo kubeadm token create --print-join-command
#
#   출력된 명령어를 Worker에서 실행:
#     sudo kubeadm join <MASTER_IP>:6443 \
#       --token <TOKEN> \
#       --discovery-token-ca-cert-hash sha256:<HASH>
#
# 주의:
# - Join Token을 스크립트나 GitHub에 저장하지 않습니다.
# - 기존 클러스터에 연결된 Worker에서는 재실행하지 않습니다.
# ============================================================

set -euo pipefail

echo "===== Kubernetes Worker Join ====="

# 1. 관리자 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: sudo 권한으로 실행하세요."
    exit 1
fi

# 2. 기존 클러스터 연결 여부 확인
if [ -f /etc/kubernetes/kubelet.conf ]; then
    echo "ERROR: 이미 Kubernetes 클러스터에 연결된 노드입니다."
    exit 1
fi

# 3. 필수 프로그램 확인
echo "[1/4] 필수 프로그램 확인"

for cmd in kubeadm kubelet containerd; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: $cmd 가 설치되지 않았습니다."
        exit 1
    fi
done

if ! systemctl is-active --quiet containerd; then
    echo "ERROR: containerd가 실행 중이지 않습니다."
    exit 1
fi

# 4. Join 명령어 입력
echo "[2/4] Master Join 정보 입력"

echo "Master에서 생성한 kubeadm join 명령어를 확인하세요."
echo "토큰은 GitHub에 저장하지 않습니다."

read -r -p "Master Private IP: " MASTER_IP
read -r -p "Join Token: " JOIN_TOKEN
read -r -p "Discovery CA Hash (sha256: 포함): " CA_HASH

# 5. 입력값 확인
if [[ ! "$MASTER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: Master IP 형식이 올바르지 않습니다."
    exit 1
fi

if [[ ! "$JOIN_TOKEN" =~ ^[a-z0-9]{6}\.[a-z0-9]{16}$ ]]; then
    echo "ERROR: Join Token 형식이 올바르지 않습니다."
    exit 1
fi

if [[ ! "$CA_HASH" =~ ^sha256:[a-fA-F0-9]{64}$ ]]; then
    echo "ERROR: CA Hash 형식이 올바르지 않습니다."
    exit 1
fi

# 6. Master API 연결 확인
echo "[3/4] Master API 연결 확인"

if ! timeout 5 bash -c \
    "echo > /dev/tcp/${MASTER_IP}/6443" 2>/dev/null; then
    echo "ERROR: Master API Server(6443)에 연결할 수 없습니다."
    echo "AWS Security Group과 네트워크를 확인하세요."
    exit 1
fi

# 7. Worker Join
echo "[4/4] kubeadm join 실행"

kubeadm join "${MASTER_IP}:6443" \
    --token "$JOIN_TOKEN" \
    --discovery-token-ca-cert-hash "$CA_HASH" \
    --cri-socket unix:///run/containerd/containerd.sock

echo ""
echo "===== Worker Join 완료 ====="
echo "Master에서 kubectl get nodes -o wide 로 확인하세요."
