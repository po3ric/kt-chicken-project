

#!/usr/bin/env bash

# ============================================================
# KT Cloud Chicken Team - Calico CNI 설치
# ============================================================
# 대상: Kubernetes Master EC2
# 버전: Calico v3.31.4
# 방식: Tigera Operator
#
# 사전 조건:
#   - kubeadm init 완료
#   - kubectl 연결 정상
#   - Master와 Worker 간 네트워크 허용
#
# 실행: bash k8s-calico.sh
#
# 주의:
#   - 기존 Calico가 설치된 클러스터에는 실행하지 않음
#   - Pod CIDR은 k8s-master.sh와 일치해야 함
# ============================================================

set -euo pipefail

CALICO_VERSION="v3.31.4"
POD_CIDR="192.168.0.0/16"

echo "===== Calico CNI 설치 ====="

# 1. kubectl 확인
if ! command -v kubectl >/dev/null 2>&1; then
    echo "ERROR: kubectl이 설치되지 않았습니다."
    exit 1
fi

# 2. Kubernetes 연결 확인
echo "[1/6] Kubernetes 연결 확인"

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "ERROR: Kubernetes API Server 연결 실패"
    exit 1
fi

# 3. 기존 설치 확인
echo "[2/6] 기존 Calico 설치 여부 확인"

if kubectl get namespace tigera-operator >/dev/null 2>&1 ||
   kubectl get installation.operator.tigera.io default >/dev/null 2>&1; then
    echo "ERROR: 기존 Calico 설치가 감지되었습니다."
    exit 1
fi

# 4. Tigera Operator 설치
echo "[3/6] Tigera Operator 설치"

kubectl create -f \
    "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"

# 5. CRD 등록 대기
echo "[4/6] Calico Installation CRD 준비 대기"

kubectl wait \
    --for=condition=Established \
    crd/installations.operator.tigera.io \
    --timeout=180s

# 6. Calico 설치 설정
echo "[5/6] Calico Installation 생성"

cat <<EOF | kubectl create -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    bgp: Enabled
    ipPools:
      - cidr: ${POD_CIDR}
        encapsulation: VXLANCrossSubnet
        natOutgoing: Enabled
        nodeSelector: all()
EOF

# 7. 설치 진행 확인
echo "[6/6] Calico 설치 상태 확인"

kubectl get pods -n tigera-operator

echo ""
echo "===== Calico 설치 요청 완료 ====="
echo "설치가 완료될 때까지 아래 명령어로 확인하세요."
echo ""
echo "kubectl get pods -n calico-system -w"
echo "kubectl get nodes -o wide"
