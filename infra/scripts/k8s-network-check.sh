
#!/usr/bin/env bash

# ============================================================
# KT Cloud Chicken Team - Kubernetes 네트워크 점검
# ============================================================
# 목적: Calico CNI / BGP / Pod 네트워크 상태 확인
# 대상: Kubernetes Master EC2
#
# 사전 조건:
#   1. kubeadm init 완료
#   2. Worker Join 완료
#   3. Calico CNI 설치 완료
#
# 실행: bash k8s-network-check.sh
#
# 주의:
# - 조회 전용 스크립트 (설정 변경 없음)
# - 실제 Pod 간 HTTP 통신 테스트는 별도 수행
# ============================================================

set -u

echo "===== Kubernetes 네트워크 점검 ====="

# 1. kubectl 설치 여부
if ! command -v kubectl >/dev/null 2>&1; then
    echo "ERROR: kubectl이 설치되지 않았습니다."
    exit 1
fi

# 2. Kubernetes API 연결 확인
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "ERROR: Kubernetes API Server 연결 실패"
    exit 1
fi

# 3. 노드 상태
echo ""
echo "[1/7] Kubernetes Nodes"
kubectl get nodes -o wide

# 4. Pod CIDR
echo ""
echo "[2/7] Node Pod CIDR"
kubectl get nodes \
    -o custom-columns='NAME:.metadata.name,POD_CIDR:.spec.podCIDR,INTERNAL_IP:.status.addresses[?(@.type=="InternalIP")].address'

# 5. Calico Pod 상태
echo ""
echo "[3/7] Calico Pods"
kubectl get pods -n calico-system -o wide

# 6. Tigera Operator 상태
echo ""
echo "[4/7] Tigera Operator"
kubectl get pods -n tigera-operator

# 7. Calico Installation 설정
echo ""
echo "[5/7] Calico Installation"
kubectl get installation.operator.tigera.io default \
    -o jsonpath='{.spec.calicoNetwork}{"\n"}'

# 8. Calico IPPool 확인
echo ""
echo "[6/7] Calico IP Pools"
kubectl get ippools.crd.projectcalico.org \
    -o wide

# 9. BGP 피어 상태
echo ""
echo "[7/7] Calico BGP Status"

CALICO_POD=$(kubectl get pods -n calico-system \
    -l k8s-app=calico-node \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$CALICO_POD" ]; then
    echo "Calico Pod: $CALICO_POD"

    kubectl exec -n calico-system "$CALICO_POD" \
        -c calico-node -- calico-node -bird-ready 2>&1 \
        || echo "WARNING: BGP readiness 확인 실패"

    echo ""
    echo "참고: BGP 피어 상세 상태는 calicoctl 또는"
    echo "Calico 노드 진단 명령어로 추가 확인이 필요합니다."
else
    echo "WARNING: calico-node Pod를 찾지 못했습니다."
fi

echo ""
echo "===== 네트워크 점검 완료 ====="
