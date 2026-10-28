# KT Chicken Team — A3 Kubernetes 구축 및 운영 가이드

> **대상:** AWS EC2(Ubuntu 24.04) 기반 자체 관리형 Kubernetes 클러스터  
> **관리 위치:** `infra/scripts/README.md`  
> **기준:** 2026-10-19 / Kubernetes v1.36.5 / Calico v3.31.4  
> **중요:** 이 문서는 **신규 EC2 구축용**입니다. 운영 중인 클러스터에 초기화·설치 스크립트를 재실행하지 마세요.

## 1. 목적과 작업 범위

A3는 A1/A2가 준비한 AWS 네트워크 및 EC2 위에 Kubernetes Master(Control Plane) 1대와 Worker 1대를 구성합니다. `containerd`, `kubeadm`, Calico CNI, 노드 간 통신, kubelet serving TLS를 구축·점검합니다. Metrics Server, HPA, 애플리케이션 및 모니터링은 담당 팀과 협의하여 후속 배포합니다.

### 실제 구축 환경(2026-10-19 확인)

| 항목 | Master | Worker |
|---|---|---|
| 호스트명 | `ip-10-0-101-93` | `ip-10-0-102-83` |
| 사설 IP | `10.0.101.93` | `10.0.102.83` |
| 서브넷 | `10.0.101.0/24` | `10.0.102.0/24` |
| OS | Ubuntu 24.04 계열 | Ubuntu 24.04 계열 |
| Kubernetes | v1.36.5 | v1.36.5 |
| Container runtime | containerd 2.2.1 | containerd 2.2.1 |

**주의:** 위 IP는 **지난 구축 사례**입니다. EC2 재생성 시 바뀔 수 있으므로 그대로 입력하지 마세요. 현재 클러스터는 노드 Ready, Calico 정상, 양방향 Pod 통신 성공, 양쪽 kubelet serving 인증서 발급까지 확인했습니다. 수정된 Calico 설치 스크립트를 새 클러스터에서 다시 실행해 검증한 것은 아닙니다.

## 2. 구축 전 체크리스트

- [ ] Master / Worker EC2 생성 완료, SSM으로 각각 접속 가능
- [ ] 두 EC2가 필요한 APT 저장소·GitHub·컨테이너 이미지 레지스트리에 접근 가능
- [ ] Master ↔ Worker 간 Kubernetes API(6443), kubelet(10250), Calico 통신이 가능한 보안 그룹·라우팅 구성
- [ ] `git` 설치 및 프로젝트 저장소 접근 가능
- [ ] **Master/Worker를 구분하여** SSM 터미널 열기
- [ ] 기존 Kubernetes 클러스터가 없는 **신규 서버**인지 확인

> 보안 그룹을 인터넷 전체에 개방하지 마세요. Calico의 VXLAN 사용 시 노드 간 UDP 4789 허용 여부를 점검하고, BGP 사용 시 TCP 179 요구사항도 실제 구성에 맞춰 확인하세요. 사설 서브넷의 외부 다운로드 경로는 A1/A2 구성에 따릅니다.

## 3. 저장소 받기 — Master와 Worker 각각

SSM 터미널에서 실행합니다.

```bash
cd ~
git clone -b feature/infra-setup https://github.com/po3ric/kt-chicken-project.git
cd ~/kt-chicken-project
git branch --show-current
ls infra/scripts/k8s-*.sh
```

이미 clone한 경우 **재클론하지 않고** 다음을 사용합니다.

```bash
cd ~/kt-chicken-project
git status --short
git pull --ff-only origin feature/infra-setup
```

`git status --short`에 수정 파일이 있으면 덮어쓰지 말고 먼저 확인합니다. 추후 기본 브랜치에 병합되면 브랜치 이름을 변경해야 합니다.

## 4. 실행 순서 한눈에 보기

| 순서 | 실행 서버 | 스크립트 | 목적 |
|---:|---|---|---|
| 1 | Master + Worker | `k8s-precheck.sh` | 서버 사전 점검 |
| 2 | Master + Worker | `k8s-init.sh` | swap, 커널 네트워크, containerd 설정 |
| 3 | Master + Worker | `k8s-install.sh` | kubeadm/kubelet/kubectl 설치 |
| 4 | **Master만** | `k8s-master.sh` | `kubeadm init`, kubeconfig 구성 |
| 5 | **Master만** | `k8s-calico.sh` | Tigera Operator / Calico 설치 |
| 6 | **Worker만** | `k8s-worker.sh` | `kubeadm join` |
| 7 | **Master만** | `k8s-network-check.sh` | 노드·Calico 네트워크 점검 |
| 8 | Master + Worker | `k8s-kubelet-tls.sh` | kubelet serving TLS 활성화 |
| 9 | **Master만** | CSR 요청 검증 및 수동 승인 | 각 노드 serving 인증서 발급 |
| 10 | **Master만** | `k8s-healthcheck.sh` | 최종 상태 점검(후속 구성 배포 후) |

**명령어 실행 위치:** 각 EC2의 `~/kt-chicken-project` 디렉터리. **SSM 접속 계정:** `ssm-user`. 스크립트 내부의 `sudo` 사용 여부는 실제 파일을 확인하세요. 아래는 현재까지의 실습 실행 패턴입니다.

## 5. STEP 1 — 공통 준비(Master, Worker 각각)

```bash
cd ~/kt-chicken-project
bash infra/scripts/k8s-precheck.sh
sudo bash infra/scripts/k8s-init.sh
sudo bash infra/scripts/k8s-install.sh
```

기본 검증:

```bash
swapon --show                       # 출력 없어야 함
systemctl is-active containerd     # active
sysctl net.ipv4.ip_forward         # = 1
kubeadm version -o short           # v1.36.5
kubectl version --client
```

`kubeadm init/join` 전에는 kubelet이 재시작되거나 정상 기동되지 않을 수 있습니다. Master와 Worker 모두 공통 단계가 끝난 후 다음 단계로 이동합니다.

## 6. STEP 2 — Master 클러스터 생성

**Master SSM에서만** 실행:

```bash
cd ~/kt-chicken-project
bash infra/scripts/k8s-master.sh
```

이 스크립트는 Master의 AWS 사설 IP를 확인하고, Pod CIDR `192.168.0.0/16`을 기준으로 초기화하도록 작성되었습니다. 실제 코드의 설정값과 AWS IP가 일치하는지 실행 전 확인하세요.

완료 후 **Master SSM**에서:

```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system
```

Calico 설치 전에는 노드가 `NotReady`일 수 있습니다. **`kubeadm init`을 반복 실행하지 마세요.** 실패 시 먼저 출력과 로그를 기록합니다.

## 7. STEP 3 — Calico CNI 설치

**Master SSM에서만**, 신규 클러스터에서 **한 번만** 실행:

```bash
cd ~/kt-chicken-project
bash infra/scripts/k8s-calico.sh
```

기준 구성:

```yaml
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    bgp: Enabled
    ipPools:
      - cidr: 192.168.0.0/16
        encapsulation: VXLANCrossSubnet
        natOutgoing: Enabled
        nodeSelector: all()
```

**중요:** `bgp: Enabled`와 `encapsulation: VXLANCrossSubnet`을 **함께** 사용합니다. 'BGP를 끈 구성'이 아닙니다. 설정은 노드별로 따로 적용하는 것이 아니라 Calico 클러스터 구성입니다.

설치 후 **Master SSM**에서:

```bash
kubectl get installation.operator.tigera.io default -o yaml
kubectl get pods -n tigera-operator
kubectl get pods -n calico-system -o wide
kubectl get ippool.crd.projectcalico.org
```

`calico-system` Pod가 모두 Running이 되는 데 시간이 걸릴 수 있습니다. 설치 스크립트가 실패했더라도 **바로 재실행하지 말고** 현재 Operator/Installation/DaemonSet 상태를 확인하세요.

## 8. STEP 4 — Worker 클러스터 참여

먼저 **Master SSM**에서 새 Join 명령을 확인합니다.

```bash
sudo kubeadm token create --print-join-command
```

출력 예시(가짜 값):

```text
kubeadm join <MASTER_PRIVATE_IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<64자리_HASH>
```

**Worker SSM에서만** 실행:

```bash
cd ~/kt-chicken-project
sudo bash infra/scripts/k8s-worker.sh
```

스크립트 안내에 따라 Master 사설 IP, 토큰, `sha256:`을 포함한 전체 CA 해시를 입력합니다. **토큰과 해시를 GitHub·문서·채팅에 그대로 게시하지 마세요.**

**Master SSM**에서 확인:

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
```

정상 목표: Master와 Worker가 모두 `Ready`.

## 9. STEP 5 — 네트워크 검증

**Master SSM**에서:

```bash
bash infra/scripts/k8s-network-check.sh
kubectl get nodes -o wide
kubectl get pods -n calico-system -o wide
kubectl get ippool.crd.projectcalico.org -o yaml
```

이 스크립트는 노드, Pod CIDR, Calico 및 BGP 관련 상태를 점검합니다. **단, 실제 서로 다른 노드에 배치된 Pod 간 통신 성공을 보장하는 것은 아닙니다.** 별도 테스트 Pod를 Master/Worker에 배치해 양방향 통신을 확인하는 것이 좋습니다. 이전 구축에서는 양방향 ICMP 통신이 0% 손실로 성공했습니다.

## 10. STEP 6 — kubelet TLS 인증서

Metrics Server가 kubelet 인증서를 안전하게 검증할 수 있도록, **Master와 Worker 각각의 SSM**에서 실행합니다.

```bash
cd ~/kt-chicken-project
sudo bash infra/scripts/k8s-kubelet-tls.sh
```

스크립트는 kubelet 설정에 `serverTLSBootstrap: true`를 적용하고 kubelet을 재시작합니다. **CSR 자동 승인은 하지 않습니다.**

이후 **Master SSM**에서:

```bash
kubectl get csr
```

승인 전 **각 CSR별로** 다음 사항을 반드시 확인합니다.

```bash
kubectl get csr <CSR_NAME> -o yaml
kubectl get csr <CSR_NAME> -o jsonpath='{.spec.request}' | base64 -d | openssl req -noout -text
```

- `signerName`: `kubernetes.io/kubelet-serving`
- `username`: `system:node:<실제_노드명>`
- 인증서 Subject의 조직: `system:nodes`
- DNS/IP SAN: 실제 해당 노드의 호스트명 및 사설 IP
- `usages`: 서버 인증 용도와 일치

**위 값이 모두 실제 노드와 일치하는 경우에만** Master에서 개별 승인:

```bash
kubectl certificate approve <검증한_CSR_NAME>
kubectl get csr
```

정상 목표: 해당 CSR이 `Approved,Issued`. Master와 Worker 양쪽의 kubelet serving CSR을 각각 확인합니다. Worker SSM에서 `kubectl get csr` 실행 시 `localhost:8080` 연결 오류가 나면, Worker의 `ssm-user`에 kubeconfig가 없기 때문일 수 있습니다. **CSR 조회와 승인은 Master SSM에서 수행**하세요.

> `--kubelet-insecure-tls`로 인증서 검증을 우회하는 대신 정상 serving 인증서 발급을 우선합니다. Metrics Server 자체 설치와 `kubectl top` 검증은 별도 단계입니다.

## 11. STEP 7 — 최종 점검

Metrics Server 등 후속 구성 요소가 설치된 **이후** Master SSM에서:

```bash
bash infra/scripts/k8s-healthcheck.sh
kubectl get nodes
kubectl get pods -A
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top nodes
kubectl top pods -A
```

Metrics Server가 아직 설치되지 않았다면 `k8s-healthcheck.sh`에서 관련 항목이 실패할 수 있습니다. 이것을 **기본 Kubernetes 구축 실패로 단정하지 마세요.** 현재까지 확인된 것은 클러스터, Calico, 양방향 Pod 네트워크, kubelet serving TLS까지입니다. Metrics Server/HPA 동작은 별도 검증이 필요합니다.

## 12. 자주 발생하는 이슈 / 원인 / 해결방안

| 이슈 | 가능한 원인 | 해결·확인 방법 |
|---|---|---|
| Calico Operator는 설치됐지만 `Installation/default` 없음 | Installation 리소스 생성 단계 누락 또는 실패 | `kubectl get installation.operator.tigera.io default` 확인. 신규 설치용 `k8s-calico.sh`에 명시적 생성·검증 반영(커밋 `f1dd752`). 기존 클러스터에는 스크립트 재실행 금지 |
| Worker `NotReady` | Calico 미준비, kubelet/containerd 문제, 네트워크 차단 | `kubectl describe node`, `kubectl get pods -n calico-system`, `journalctl -u kubelet` 순서로 점검 |
| BGP 상태 또는 Pod 통신 오류 | Calico IPPool/캡슐화 설정, SG·라우팅 문제 | `bgp: Enabled`, `VXLANCrossSubnet`, Pod CIDR 일치 여부와 UDP 4789/TCP 179 통신 정책 확인 |
| `kubeadm join` 실패 | Master IP/토큰/CA 해시 오류 또는 6443 차단 | Master에서 새 Join 명령 발급, SG 및 라우팅 확인 |
| kubelet serving CSR이 `Pending` | 보안상 수동 승인이 필요 | 요청자·서명자·SAN·용도 검증 후 해당 CSR만 승인 |
| Worker에서 `kubectl`이 `localhost:8080`에 연결 시도 | Worker `ssm-user`에 kubeconfig 없음 | 클러스터 관리 명령은 Master SSM에서 실행 |
| `kubectl top` 실패 | Metrics Server 미설치·미준비 또는 인증서 문제 | Metrics Server 배포 상태와 APIService, kubelet serving TLS 확인 |
| 스크립트 재실행 시 '이미 설치됨' 오류 | 기존 리소스 중복 실행 방지 | 정상적인 보호 동작일 수 있음. 재설치 대신 상태 확인 |

문제가 발생하면 아래 형식으로 작업일지에 남깁니다.

```text
[날짜/서버]
이슈:
증상/오류 메시지:
원인:
확인 명령어:
해결방안:
재검증 결과:
```

## 13. 팀원 인수인계 / 주의사항

1. **Master SSM과 Worker SSM을 반드시 구분**합니다. `kubectl` 명령은 기본적으로 Master에서 실행합니다.
2. 새 EC2를 만들 때마다 **사설 IP·노드명·토큰·CA 해시를 새로 확인**합니다.
3. `k8s-init.sh`, `k8s-master.sh`, `k8s-calico.sh`, `k8s-worker.sh`는 이미 구축된 환경에서 무작정 재실행하지 않습니다.
4. 인증서 CSR은 **요청 내용을 검증한 후 개별 수동 승인**합니다. 모든 Pending CSR을 일괄 승인하지 않습니다.
5. `k8s-healthcheck.sh`의 Metrics Server/HPA 관련 결과는 후속 담당 구성 배포 여부와 구분합니다.
6. Calico 수정 스크립트는 GitHub `feature/infra-setup`의 커밋 `f1dd752`에 반영되어 있습니다. 신규 환경에서의 완전 재현 검증은 별도 수행해야 합니다.

---

**완료 기준:** Master/Worker Ready → Calico 정상 → 노드 간 Pod 통신 성공 → kubelet serving 인증서 `Approved,Issued` → (후속 배포 후) Metrics Server 및 HPA 확인.