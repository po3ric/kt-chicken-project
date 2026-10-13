# Accordion 프로젝트 — AWS 네트워크 설계서 (A1)

## 1. 네트워크 설계 개요

### 프로젝트 정보

| 항목 | 내용 |
|---|---|
| 프로젝트명 | Accordion (아코디언) |
| 프로젝트 주제 | Terraform 기반 AWS 인프라 자동 구축 및 Kubernetes 2단계 오토스케일링 |
| 담당 | A1 — AWS 네트워크 설계 및 검증 |
| 클라우드 | AWS |
| 리전 | 서울 (`ap-northeast-2`) |
| 운영체제 | Ubuntu Server 24.04 LTS (x86_64) |
| IaC 도구 | Terraform |
| 컨테이너 오케스트레이션 | Kubernetes |

### 네트워크 설계 목표

- Terraform으로 AWS 네트워크 인프라를 자동 구축한다.
- Master와 Worker를 서로 다른 가용 영역(AZ)에 배치한다.
- Kubernetes 클러스터 내부 통신을 지원한다.
- Security Group을 통해 필요한 포트만 허용한다.
- Worker EC2가 Auto Scaling Group을 통해 추가되더라도 네트워크에 정상 연결되도록 설계한다.

---

## 2. VPC 및 Subnet 설계

### 2.1 VPC 구성

| 항목 | 설정값 |
|---|---|
| VPC 이름 | `accordion-vpc` |
| VPC CIDR | `10.0.0.0/16` |
| 리전 | `ap-northeast-2` |
| DNS Resolution | 활성화 |
| DNS Hostnames | 활성화 |

VPC는 프로젝트에서 사용하는 AWS 리소스들의 논리적으로 격리된 네트워크이다.

### 2.2 Public Subnet 구성

| 항목 | Public Subnet A | Public Subnet C |
|---|---|---|
| 서브넷 이름 | `accordion-public-a` | `accordion-public-c` |
| 가용 영역 | `ap-northeast-2a` | `ap-northeast-2c` |
| CIDR | `10.0.1.0/24` | `10.0.2.0/24` |
| 유형 | Public | Public |
| 주요 리소스 | Master EC2 | Worker EC2 (ASG) |
| Public IPv4 자동 할당 | 활성화 | 활성화 |

**서브넷 명칭 규칙**

- Subnet A → AZ `2a`
- Subnet C → AZ `2c`
- 문서와 구성도에서는 A, C로 통일한다.
- Terraform의 AZ 설정에는 전체 이름인 `ap-northeast-2a`, `ap-northeast-2c`를 사용한다.

### 2.3 네트워크 구성도

```text
                       Internet
                          |
                          |
                 Internet Gateway
                   accordion-igw
                          |
                          |
          VPC: accordion-vpc (10.0.0.0/16)
                          |
              accordion-public-rt
                          |
           +--------------+--------------+
           |                             |
      AZ: 2a                         AZ: 2c
           |                             |
    Public Subnet A               Public Subnet C
     10.0.1.0/24                   10.0.2.0/24
           |                             |
       Master EC2                  Worker EC2
    Ubuntu 24.04 LTS              Ubuntu 24.04 LTS
           |                             |
    Kubernetes API                  AWS ASG
       TCP 6443                   min: 1 / max: 2
           |                             |
           +------ Kubernetes Cluster ---+
                        |
                 Calico Pod Network
                   172.20.0.0/16
```

※ Master 및 Worker는 각각 Public IP를 사용한다. Kubernetes 내부 통신에는 사설 IP를 사용한다.

※ 현재 설계는 단일 Master 구조이므로 완전한 고가용성(HA) 구성은 아니다.

---

## 3. Internet Gateway 및 Route Table 설계

### 3.1 Internet Gateway

| 항목 | 설정값 |
|---|---|
| IGW 이름 | `accordion-igw` |
| 연결 VPC | `accordion-vpc` |
| 용도 | EC2 인터넷 통신 |

Internet Gateway는 VPC의 인터넷 연결을 담당한다.

### 3.2 Route Table

| 항목 | 설정값 |
|---|---|
| Route Table 이름 | `accordion-public-rt` |
| 연결 VPC | `accordion-vpc` |
| 연결 서브넷 | Public Subnet A, Public Subnet C |

**라우팅 규칙**

| Destination | Target | 용도 |
|---|---|---|
| `10.0.0.0/16` | local | VPC 내부 통신 |
| `0.0.0.0/0` | Internet Gateway | 인터넷 통신 |

**라우팅 동작**

- Master와 Worker의 사설 IP 통신은 VPC 내부 `local` 경로를 사용한다.
- 외부 인터넷으로 나가는 트래픽은 IGW를 사용한다.
- Public Subnet A와 C는 동일한 Public Route Table을 사용한다.

---

## 4. Security Group 설계

### 4.1 Master Security Group

**이름:** `accordion-master-sg`

| 프로토콜 | 포트 | Source | 용도 |
|---|---|---|---|
| TCP | 22 | 관리자 공인 IP `/32` | SSH 접속 |
| TCP | 6443 | `accordion-worker-sg` | Worker → Kubernetes API |
| TCP | 6443 | 관리자 공인 IP `/32` (필요 시) | 외부 kubectl 관리 |
| TCP | 10250 | `accordion-worker-sg` (필요 시) | Kubelet API 통신 |

### 4.2 Worker Security Group

**이름:** `accordion-worker-sg`

| 프로토콜 | 포트 | Source | 용도 |
|---|---|---|---|
| TCP | 22 | 관리자 공인 IP `/32` | SSH 접속 |
| TCP | 10250 | `accordion-master-sg` | Master → Worker Kubelet |
| TCP | 30080 | 관리자/테스트 공인 IP `/32` | 웹서비스 NodePort |
| UDP | 4789 | Master/Worker SG | Calico VXLAN 사용 시 |

### 4.3 추가 검토 사항

다음 사항은 A3의 Kubernetes 및 Calico 설정 방식에 따라 최종 확정한다.

- Calico VXLAN 또는 BGP 통신 방식
- 노드 간 Pod 트래픽에 필요한 포트
- Kubernetes API 및 Kubelet 접근 방향
- Cluster Autoscaler 및 ASG 연동 시 필요한 네트워크 설정
- B2의 NodePort 최종 번호

**보안 정책**

- SSH는 관리자 IP에서만 허용한다.
- Kubernetes 내부 통신은 가능한 한 Security Group 참조 방식으로 설정한다.
- 불필요한 인바운드 포트는 개방하지 않는다.
- Master/Worker의 아웃바운드는 초기 구축에 필요한 인터넷 접근을 허용하고, 이후 제한 가능성을 검토한다.

※ 위 SG 규칙은 초기 설계안이며, Kubernetes와 Calico 구성 방식에 따라 추가 규칙이 필요할 수 있다.

---

## 5. Kubernetes 네트워크 설계

| 항목 | CIDR / 설정값 |
|---|---|
| AWS VPC CIDR | `10.0.0.0/16` |
| Public Subnet A | `10.0.1.0/24` |
| Public Subnet C | `10.0.2.0/24` |
| Kubernetes Pod CIDR | `172.20.0.0/16` |
| Kubernetes Service CIDR | `10.96.0.0/12` |
| CNI | Calico |
| Kubernetes API Server | TCP 6443 |

### 네트워크 구분

- **VPC CIDR:** AWS EC2 및 AWS 리소스 간 통신에 사용
- **Pod CIDR:** Kubernetes Pod 간 통신에 사용
- **Service CIDR:** Kubernetes Service의 가상 IP에 사용

서로 다른 네트워크 대역을 사용하여 주소 충돌을 방지한다.

---

## 6. 담당자별 연동 사항

### A2 — Terraform 담당

Terraform으로 다음 리소스를 생성한다.

- VPC: `accordion-vpc`
- Public Subnet A: `accordion-public-a`
- Public Subnet C: `accordion-public-c`
- Internet Gateway: `accordion-igw`
- Public Route Table: `accordion-public-rt`
- Master/Worker Security Group
- Ubuntu Server 24.04 LTS 기반 EC2
- Worker Launch Template 및 Auto Scaling Group

**확인 사항**

- Master는 Subnet A에 배치
- Worker ASG는 Subnet C에 연결
- EC2 Public IP 할당 확인
- Worker 추가 시 동일한 SG 적용
- Terraform 변수 및 리소스 이름 통일

### A3 — Linux / Kubernetes 담당

- Ubuntu Server 24.04 LTS 기준 설치 스크립트 작성
- Master에서 `kubeadm init` 실행
- Worker에서 `kubeadm join` 실행
- Calico CNI 설치 및 네트워크 모드 결정
- Worker 자동 생성 시 클러스터 자동 참여 구성

**A1 확인 필요 사항**

- Master/Worker 통신 포트
- Calico 통신 방식
- 신규 Worker 자동 연결에 필요한 네트워크 조건

### B2 — Kubernetes 서비스 담당

- Deployment 및 Service 구성
- NodePort 서비스 포트 확정
- HPA 설정

**A1 확인 필요 사항**

- 외부에서 접근할 NodePort 번호
- 서비스 접근 대상 노드 및 접속 방식

---

## 7. 네트워크 검증 계획

Terraform 및 Kubernetes 구축이 완료되면 다음 항목을 검증한다.

| 번호 | 검증 항목 | 확인 내용 | 예상 결과 |
|---|---|---|---|
| 1 | VPC 생성 | CIDR 및 이름 확인 | `10.0.0.0/16` |
| 2 | Subnet A 생성 | AZ, CIDR 확인 | `2a`, `10.0.1.0/24` |
| 3 | Subnet C 생성 | AZ, CIDR 확인 | `2c`, `10.0.2.0/24` |
| 4 | IGW 연결 | VPC 연결 상태 확인 | 정상 연결 |
| 5 | Route Table | 두 서브넷의 연결 및 인터넷 경로 확인 | 정상 설정 |
| 6 | SSH 접속 | 허용된 관리자 IP에서 접속 | 성공 |
| 7 | 내부 통신 | Master↔Worker 사설 IP 연결 확인 | 정상 |
| 8 | Kubernetes API | Worker→Master TCP 6443 확인 | 성공 |
| 9 | 인터넷 통신 | EC2 외부 HTTPS 연결 | 성공 |
| 10 | Pod 통신 | 서로 다른 노드의 Pod 간 통신 | 성공 |
| 11 | NodePort | 외부에서 서비스 접속 | 정상 응답 |
| 12 | ASG 확장 | 신규 Worker의 서브넷 및 SG 확인 | 정상 적용 |
| 13 | 보안 정책 | 허용되지 않은 IP의 접근 확인 | 차단 |

### 테스트 명령어 예시

**Kubernetes API 연결**

```bash
nc -vz <MASTER_PRIVATE_IP> 6443
```

**인터넷 연결**

```bash
curl -I https://www.google.com
```

**클러스터 노드 확인**

```bash
kubectl get nodes -o wide
```

**Pod 배치 확인**

```bash
kubectl get pods -A -o wide
```

**NodePort 접속**

```bash
curl http://<WORKER_PUBLIC_IP>:30080
```

※ NodePort 30080은 임시 설정값이며 B2 담당자와 협의 후 확정한다.

---

## 8. 최종 확인 및 미결정 사항

### 확정된 사항

- AWS 서울 리전 사용
- VPC `10.0.0.0/16`
- Public Subnet A → `ap-northeast-2a`
- Public Subnet C → `ap-northeast-2c`
- Master는 Subnet A에 배치
- Worker ASG는 Subnet C에 배치
- Ubuntu Server 24.04 LTS 사용
- Terraform 기반 네트워크 구축
- Kubernetes Pod CIDR `172.20.0.0/16`
- Kubernetes Service CIDR `10.96.0.0/12`

### 추가 협의 사항

- [ ] A2: Terraform 네트워크 구성값 반영 확인
- [ ] A3: Calico 통신 모드 및 SG 포트 확정
- [ ] A3: Worker 자동 참여 방식 확정
- [ ] B2: NodePort 번호 확정
- [ ] A1: AWS 네트워크 구축 결과 검증
- [ ] A1: Kubernetes 통신 및 보안 검증
- [ ] A1: 최종 테스트 결과 문서화

---

## 9. 담당 범위 정리

**A1 — AWS 네트워크 설계 및 검증**

1. VPC, Subnet, CIDR 및 AZ 설계
2. Internet Gateway 및 Route Table 설계
3. Security Group 통신 정책 수립
4. Terraform 네트워크 구현 결과 확인
5. Master/Worker 및 Kubernetes 네트워크 연결 검증
6. 네트워크 테스트 결과 및 최종 문서 정리

본 문서는 초기 네트워크 설계서이며, 실제 Terraform 및 Kubernetes 구축 과정에서 확인된 사항을 반영하여 최종본으로 갱신한다.
