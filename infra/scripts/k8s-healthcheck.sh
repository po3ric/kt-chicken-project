
#!/usr/bin/env bash

# ============================================================
# KT Cloud Chicken Team - Kubernetes Health Check
# ============================================================
# 목적: Kubernetes 클러스터 구축 후 전체 상태 점검
# 대상: Master EC2
#
# 점검 항목:
#  1. Kubernetes API Server
#  2. Master / Worker Node
#  3. kube-system Pod
#  4. Calico CNI
#  5. Metrics Server
#  6. CPU / Memory Metrics
#  7. HPA
#
# 실행: bash k8s-healthcheck.sh
#
# 주의:
# - 조회 전용 (설정 변경 없음)
# - HPA는 배포 전이면 없어도 정상
# ============================================================

set -uo pipefail

PASS=0
WARN=0
FAIL=0

pass() {
    echo "[PASS] $1"
    PASS=$((PASS + 1))
}

warn() {
    echo "[WARN] $1"
    WARN=$((WARN + 1))
}

fail() {
    echo "[FAIL] $1"
    FAIL=$((FAIL + 1))
}

section() {
    echo ""
    echo "=================================================="
    echo "$1"
    echo "=================================================="
}

echo "===== Kubernetes Health Check ====="

# 1. kubectl 확인
section "[1/7] Kubernetes API Server"

if ! command -v kubectl >/dev/null 2>&1; then
    fail "kubectl이 설치되지 않았습니다."
    exit 1
fi

if kubectl --request-timeout=10s cluster-info >/dev/null 2>&1; then
    pass "API Server 연결 정상"
else
    fail "API Server 연결 실패"
    exit 1
fi

# 2. Node 상태
section "[2/7] Kubernetes Nodes"

kubectl get nodes -o wide

if kubectl wait --for=condition=Ready nodes --all \
    --timeout=10s >/dev/null 2>&1; then
    pass "모든 Node Ready"
else
    fail "Ready 상태가 아닌 Node 존재"
fi

# 3. kube-system
section "[3/7] kube-system Pods"

kubectl get pods -n kube-system -o wide

if kubectl get pods -n kube-system \
    --field-selector=status.phase!=Running,status.phase!=Succeeded \
    --no-headers 2>/dev/null | grep -q .; then
    warn "kube-system에 Running/Succeeded가 아닌 Pod 존재"
else
    pass "kube-system Pod 상태 1차 확인 완료"
fi

# 4. Calico
section "[4/7] Calico CNI"

if kubectl get namespace calico-system >/dev/null 2>&1; then
    kubectl get pods -n calico-system -o wide

    if kubectl rollout status daemonset/calico-node \
        -n calico-system --timeout=20s >/dev/null 2>&1; then
        pass "Calico Node DaemonSet 정상"
    else
        fail "Calico Node DaemonSet 점검 필요"
    fi
else
    fail "calico-system Namespace 없음"
fi

# 5. Metrics Server
section "[5/7] Metrics Server"

if kubectl get deployment metrics-server \
    -n kube-system >/dev/null 2>&1; then

    kubectl get deployment metrics-server -n kube-system

    if kubectl rollout status deployment/metrics-server \
        -n kube-system --timeout=20s >/dev/null 2>&1; then
        pass "Metrics Server Deployment 정상"
    else
        fail "Metrics Server Deployment 점검 필요"
    fi
else
    warn "Metrics Server가 아직 설치되지 않았습니다."
fi

# 6. CPU / Memory
section "[6/7] Resource Metrics"

if kubectl top nodes; then
    pass "Node CPU/Memory 수집 정상"
else
    fail "Node Metrics 수집 실패"
fi

if kubectl top pods -A; then
    pass "Pod CPU/Memory 수집 정상"
else
    fail "Pod Metrics 수집 실패"
fi

# 7. HPA
section "[7/7] Horizontal Pod Autoscaler"

if kubectl get hpa -A --no-headers 2>/dev/null | grep -q .; then
    kubectl get hpa -A
    pass "HPA 리소스 확인"
else
    warn "HPA 리소스 없음 (배포 전이면 정상)"
fi

# 결과 요약
section "Health Check 결과"

echo "PASS : $PASS"
echo "WARN : $WARN"
echo "FAIL : $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "점검 실패 항목이 있습니다."
    exit 1
fi

echo ""
echo "기본 점검 완료"
echo "추가 확인: Pod 간 통신, 실제 부하 테스트, HPA Scale-Out"
