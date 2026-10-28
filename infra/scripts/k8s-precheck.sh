#!/usr/bin/env bash

# ============================================================
# KT Cloud Chicken Team - Kubernetes 사전 점검
# ============================================================
# 목적: Kubernetes 설치 전 서버 환경 확인
# 대상: Master EC2 / Worker EC2
# 실행: bash k8s-precheck.sh
# 주의: 조회 전용 (시스템 설정 변경 없음)
# ============================================================

set -u

echo "===== Kubernetes 사전 점검 ====="

# 1. 서버 이름
echo -e "\n[1] Hostname"
hostname

# 2. 운영체제
echo -e "\n[2] OS"
grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release

# 3. CPU
echo -e "\n[3] CPU"
nproc

# 4. 메모리
echo -e "\n[4] Memory"
free -h

# 5. 디스크
echo -e "\n[5] Disk"
df -h /

# 6. IP 주소
echo -e "\n[6] IP Address"
ip -br addr

# 7. 라우팅
echo -e "\n[7] Routing"
ip route

# 8. Swap 상태
echo -e "\n[8] Swap"
if [ -z "$(swapon --noheadings --show)" ]; then
    echo "OK: Swap disabled"
else
    echo "WARNING: Swap enabled"
    swapon --show
fi

# 9. containerd 설치 여부
echo -e "\n[9] containerd"
if command -v containerd >/dev/null 2>&1; then
    containerd --version
else
    echo "Not installed"
fi

# 10. kubeadm 설치 여부
echo -e "\n[10] kubeadm"
if command -v kubeadm >/dev/null 2>&1; then
    kubeadm version -o short
else
    echo "Not installed"
fi

# 11. 인터넷 연결
echo -e "\n[11] Internet"
if curl -fsSL --connect-timeout 5 --max-time 10 \
    -o /dev/null https://pkgs.k8s.io/; then
    echo "OK: HTTPS connected"
else
    echo "WARNING: HTTPS connection failed"
fi

echo -e "\n===== 점검 완료 ====="