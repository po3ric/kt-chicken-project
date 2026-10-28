
#!/usr/bin/env bash

# ============================================================
# KT Cloud Chicken Team - kubelet TLS 인증서 설정
# ============================================================
# 목적: Metrics Server의 kubelet x509 인증서 오류 해결
# 대상: Master EC2 / Worker EC2 모두
#
# 기존 해결 방식:
#   1. kubelet serverTLSBootstrap 활성화
#   2. kubelet 재시작
#   3. Master에서 CSR 내용 검증 및 승인
#   4. Kubernetes CA 서명 인증서 발급
#   5. Metrics Server에서 TLS 검증 우회 없이 수집
#
# 사전 조건:
# - kubeadm init / join 완료
# - kubelet 서비스 실행 중
# - Master에서 CSR 승인 가능
#
# 실행: sudo bash k8s-kubelet-tls.sh
#
# 주의:
# - Master와 Worker 각각 실행
# - CSR 자동 승인하지 않음
# - 운영 중인 노드에서는 kubelet 재시작에 주의
# ============================================================

set -euo pipefail

CONFIG="/var/lib/kubelet/config.yaml"
BACKUP="/var/lib/kubelet/config.yaml.before-serving-tls"

echo "===== kubelet TLS 인증서 설정 ====="

# 1. root 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: sudo bash k8s-kubelet-tls.sh 로 실행하세요."
    exit 1
fi

# 2. kubelet 설정 확인
echo "[1/5] kubelet 설정 확인"

if [ ! -f "$CONFIG" ]; then
    echo "ERROR: kubelet 설정 파일이 없습니다."
    echo "먼저 kubeadm init 또는 join을 완료하세요."
    exit 1
fi

if ! systemctl is-active --quiet kubelet; then
    echo "ERROR: kubelet 서비스가 실행 중이지 않습니다."
    exit 1
fi

# 3. 기존 설정 백업
echo "[2/5] 기존 설정 백업"

if [ ! -f "$BACKUP" ]; then
    cp -p "$CONFIG" "$BACKUP"
    echo "백업 완료: $BACKUP"
else
    echo "기존 백업 보존: $BACKUP"
fi

# 4. serverTLSBootstrap 활성화
echo "[3/5] serverTLSBootstrap 설정"

if grep -Eq '^[[:space:]]*serverTLSBootstrap:' "$CONFIG"; then
    sed -i -E \
      's/^([[:space:]]*serverTLSBootstrap:).*/\1 true/' \
      "$CONFIG"
else
    printf '\nserverTLSBootstrap: true\n' >> "$CONFIG"
fi

# 5. kubelet 재시작
echo "[4/5] kubelet 재시작"

systemctl restart kubelet

if ! systemctl is-active --quiet kubelet; then
    echo "ERROR: kubelet 재시작 실패"
    echo "확인: sudo journalctl -u kubelet -n 50"
    exit 1
fi

# 6. 설정 확인
echo "[5/5] 설정 확인"

grep -E '^[[:space:]]*(rotateCertificates|serverTLSBootstrap):' \
    "$CONFIG" || true

echo ""
echo "===== 로컬 kubelet TLS 설정 완료 ====="
echo ""
echo "다음 작업은 Master에서 수행하세요."
echo ""
echo "1. CSR 목록 확인:"
echo "   kubectl get csr"
echo ""
echo "2. CSR 요청자, 서명 유형, SAN, 용도 검증"
echo "   kubectl describe csr <CSR_NAME>"
echo ""
echo "3. 검증한 CSR만 승인:"
echo "   kubectl certificate approve <CSR_NAME>"
echo ""
echo "4. 인증서 발급 확인:"
echo "   sudo ls -l /var/lib/kubelet/pki/kubelet-server-current.pem"
echo ""
echo "5. Metrics Server 수집 확인:"
echo "   kubectl top nodes"
echo "   kubectl top pods -A"