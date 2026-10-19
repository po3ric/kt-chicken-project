
#!/usr/bin/env bash

# ============================================================
# KT Cloud Chicken Team - Kubernetes Master 초기화
# ============================================================
# 목적: kubeadm을 이용한 Kubernetes Control Plane 구축
# 대상: Ubuntu 24.04 Master EC2 전용
#
# 사전 조건:
#   1. k8s-init.sh 공통 환경 구성 완료
#   2. k8s-install.sh Kubernetes 패키지 설치 완료
#   3. Master / Worker 간 AWS 보안 그룹 통신 허용
#
# 실행:
#   sudo bash k8s-master.sh
#
# 주의:
# - Worker에서는 실행하지 않습니다.
# - 기존 클러스터에서는 다시 실행하지 않습니다.
# - Calico CNI는 다음 스크립트에서 설치합니다.
# ============================================================

set -euo pipefail

echo "===== Kubernetes Master 초기화 ====="

# 1. root 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: sudo bash k8s-master.sh 로 실행하세요."
    exit 1
fi

# 2. 기존 Control Plane 보호
if [ -f /etc/kubernetes/admin.conf ] || \
   [ -f /etc/kubernetes/manifests/kube-apiserver.yaml ]; then
    echo "ERROR: 기존 Kubernetes Control Plane이 감지되었습니다."
    echo "중복 초기화를 방지하기 위해 중단합니다."
    exit 1
fi

# 3. 필수 프로그램 확인
echo "[1/5] 필수 프로그램 확인"

for cmd in kubeadm kubelet kubectl containerd; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: $cmd 가 설치되지 않았습니다."
        exit 1
    fi
done

if ! systemctl is-active --quiet containerd; then
    echo "ERROR: containerd가 실행 중이지 않습니다."
    exit 1
fi

# 4. Master Private IP 확인
echo "[2/5] Master Private IP 확인"

# AWS EC2 메타데이터(IMDSv2)에서 실제 Private IP 조회
TOKEN=$(curl -fsS --connect-timeout 2 --max-time 5 \
    -X PUT \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" \
    http://169.254.169.254/latest/api/token)

MASTER_IP=$(curl -fsS --connect-timeout 2 --max-time 5 \
    -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/local-ipv4)

echo "Master Private IP: $MASTER_IP"

# 5. kubeadm 초기화
echo "[3/5] kubeadm init"

kubeadm init \
    --apiserver-advertise-address="$MASTER_IP" \
    --pod-network-cidr=192.168.0.0/16 \
    --cri-socket=unix:///run/containerd/containerd.sock

# 6. kubectl 설정
echo "[4/5] kubectl 설정"

# sudo로 실행한 사용자의 홈 디렉터리에 kubeconfig 배치
TARGET_USER="${SUDO_USER:-root}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

mkdir -p "$TARGET_HOME/.kube"

cp /etc/kubernetes/admin.conf "$TARGET_HOME/.kube/config"

chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.kube/config"
chmod 600 "$TARGET_HOME/.kube/config"

# 7. 설치 검증
echo "[5/5] Master 상태 확인"

KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide

echo ""
echo "===== Master 초기화 완료 ====="
echo "다음 단계: Calico CNI 설치"
echo ""
echo "Worker Join 명령어 생성:"
echo "sudo kubeadm token create --print-join-command"
