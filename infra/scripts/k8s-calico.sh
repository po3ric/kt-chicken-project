#!/usr/bin/env bash

# ============================================================
# KT Cloud Chicken Team - Calico CNI 설치
# ============================================================
# 대상: Kubernetes Master EC2
# 버전: Calico v3.31.4
# 설치 방식: Tigera Operator
#
# 목적:
#   Master와 Worker의 Pod가 서로 통신하도록
#   Kubernetes 네트워크(CNI)를 구성한다.
#
# 네트워크 설정:
#   Pod CIDR       : 192.168.0.0/16
#   BGP            : Enabled
#   VXLAN          : VXLANCrossSubnet
#   NAT Outgoing   : Enabled
#
# 사전 조건:
#   1. kubeadm init 완료
#   2. Master에서 kubectl 사용 가능
#   3. AWS 보안 그룹에서 노드 간 통신 허용
#
# 실행 위치: Master EC2
# 실행 방법:
#   bash infra/scripts/k8s-calico.sh
#
# 주의:
#   - 기존 Calico 설치 환경에서는 재실행하지 않는다.
#   - Pod CIDR은 k8s-master.sh와 동일해야 한다.
#   - 이 스크립트는 kubelet TLS 인증서를 설정하지 않는다.
# ============================================================

set -euo pipefail

CALICO_VERSION="v3.31.4"
POD_CIDR="192.168.0.0/16"

# 오류가 발생하면 실행 위치를 알려준다.
trap 'echo "[ERROR] Calico 설치 실패 (줄 번호: $LINENO)" >&2' ERR

echo "========================================"
echo " Calico CNI 설치 시작"
echo "========================================"

# ------------------------------------------------------------
# STEP 1. kubectl 설치 및 Kubernetes 연결 확인
# ------------------------------------------------------------
echo "[1/8] Kubernetes 연결 확인"

if ! command -v kubectl >/dev/null 2>&1; then
    echo "[ERROR] kubectl이 설치되지 않았습니다."
    exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "[ERROR] Kubernetes API Server에 연결할 수 없습니다."
    exit 1
fi

echo "[OK] Kubernetes 연결 정상"

# ------------------------------------------------------------
# STEP 2. 기존 Calico 설치 여부 확인
# ------------------------------------------------------------
echo "[2/8] 기존 Calico 설치 여부 확인"

if kubectl get namespace tigera-operator >/dev/null 2>&1 ||
   kubectl get namespace calico-system >/dev/null 2>&1 ||
   kubectl get installation.operator.tigera.io default >/dev/null 2>&1; then

    echo "[ERROR] 기존 Calico 설치가 감지되었습니다."
    echo "        운영 중인 클러스터에서는 재실행하지 마세요."
    exit 1
fi

echo "[OK] 기존 Calico 설치 없음"

# ------------------------------------------------------------
# STEP 3. Tigera Operator 설치
# ------------------------------------------------------------
echo "[3/8] Tigera Operator 설치"

kubectl create -f \
  "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"

echo "[OK] Tigera Operator 설치 요청 완료"

# ------------------------------------------------------------
# STEP 4. Installation CRD 등록 대기
# ------------------------------------------------------------
echo "[4/8] Calico Installation CRD 준비 대기"

kubectl wait \
  --for=condition=Established \
  crd/installations.operator.tigera.io \
  --timeout=180s

echo "[OK] Installation CRD 준비 완료"

# ------------------------------------------------------------
# STEP 5. Calico Installation 생성
# ------------------------------------------------------------
echo "[5/8] Calico Installation/default 생성"

# CRD가 등록된 후 실제 네트워크 설정을 생성한다.
# BGP는 Enabled로 유지하고, 서브넷 간 Pod 통신에
# VXLANCrossSubnet 캡슐화를 사용한다.

kubectl apply -f - <<EOF
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

# 생성 명령이 성공해도 실제 리소스 존재 여부를 확인한다.
if ! kubectl get installation.operator.tigera.io default \
    >/dev/null 2>&1; then

    echo "[ERROR] Installation/default가 생성되지 않았습니다."
    exit 1
fi

echo "[OK] Installation/default 생성 확인"

# ------------------------------------------------------------
# STEP 6. Tigera Operator 준비 대기
# ------------------------------------------------------------
echo "[6/8] Tigera Operator 준비 대기"

kubectl rollout status deployment/tigera-operator \
  -n tigera-operator \
  --timeout=300s

echo "[OK] Tigera Operator 정상 실행"

# ------------------------------------------------------------
# STEP 7. Calico 시스템 준비 대기
# ------------------------------------------------------------
echo "[7/8] Calico 시스템 준비 대기"

# Operator가 Calico 리소스를 생성할 시간을 기다린다.
# 무한 대기를 방지하기 위해 최대 300초만 확인한다.

CALICO_FOUND=false

for i in $(seq 1 60); do
    if kubectl get daemonset calico-node \
        -n calico-system >/dev/null 2>&1; then

        CALICO_FOUND=true
        break
    fi

    echo "Calico DaemonSet 생성 대기... (${i}/60)"
    sleep 5
done

if [ "$CALICO_FOUND" != "true" ]; then
    echo "[ERROR] Calico DaemonSet이 생성되지 않았습니다."
    exit 1
fi

# calico-node는 각 노드에서 실행되는 네트워크 구성 요소다.
kubectl rollout status daemonset/calico-node \
  -n calico-system \
  --timeout=300s

echo "[OK] Calico Node 준비 완료"

# ------------------------------------------------------------
# STEP 8. 네트워크 설정 검증
# ------------------------------------------------------------
echo "[8/8] Calico 네트워크 설정 검증"

ACTUAL_BGP=$(kubectl get installation.operator.tigera.io default \
  -o jsonpath='{.spec.calicoNetwork.bgp}')

ACTUAL_CIDR=$(kubectl get installation.operator.tigera.io default \
  -o jsonpath='{.spec.calicoNetwork.ipPools[0].cidr}')

ACTUAL_VXLAN=$(kubectl get installation.operator.tigera.io default \
  -o jsonpath='{.spec.calicoNetwork.ipPools[0].encapsulation}')

ACTUAL_NAT=$(kubectl get installation.operator.tigera.io default \
  -o jsonpath='{.spec.calicoNetwork.ipPools[0].natOutgoing}')

if [ "$ACTUAL_BGP" != "Enabled" ]; then
    echo "[ERROR] BGP 설정이 Enabled가 아닙니다."
    exit 1
fi

if [ "$ACTUAL_CIDR" != "$POD_CIDR" ]; then
    echo "[ERROR] Pod CIDR이 예상 설정과 다릅니다."
    exit 1
fi

if [ "$ACTUAL_VXLAN" != "VXLANCrossSubnet" ]; then
    echo "[ERROR] VXLAN 설정이 예상 설정과 다릅니다."
    exit 1
fi

if [ "$ACTUAL_NAT" != "Enabled" ]; then
    echo "[ERROR] NAT Outgoing 설정이 예상 설정과 다릅니다."
    exit 1
fi

# Calico IPPool 생성 확인
if ! kubectl get ippool.crd.projectcalico.org \
    default-ipv4-ippool >/dev/null 2>&1; then

    echo "[ERROR] Calico IPPool이 생성되지 않았습니다."
    exit 1
fi

echo "[OK] Calico 네트워크 설정 검증 완료"

echo ""
echo "========================================"
echo " Calico CNI 설치 완료"
echo "========================================"
echo "BGP          : $ACTUAL_BGP"
echo "Pod CIDR     : $ACTUAL_CIDR"
echo "VXLAN        : $ACTUAL_VXLAN"
echo "NAT Outgoing : $ACTUAL_NAT"
echo ""
echo "다음 명령어로 상태를 확인하세요."
echo ""
echo "kubectl get pods -n calico-system"
echo "kubectl get nodes -o wide"
echo ""
echo "Worker Join 이후에는 아래 스크립트를 실행하세요."
echo "bash infra/scripts/k8s-network-check.sh"
