# Accordion 프로젝트 — AWS 네트워크 설계서 (A1)

**프로젝트 주제:** Terraform 기반 AWS 인프라 자동 구축 및 Kubernetes 2단계 오토스케일링 시스템

**담당:** A1 — AWS 네트워크 설계 및 연결 검증

**진행 상태:** 네트워크 설계 초안 (Terraform 구현 전)

---

## 1. 네트워크 구성 개요

AWS 서울 리전에 VPC를 구성하고, 2개의 Public Subnet에 Kubernetes Master 및 Worker EC2를 배치한다.

Terraform을 통해 네트워크와 EC2 인프라를 자동 생성하며, Worker EC2는 Auto Scaling Group(ASG)을 통해 관리한다.

### 네트워크 구성도

```text
                   [ Internet ]
                         |
                  Internet Gateway
                         |
          +--------------+--------------+
          |       AWS VPC               |
          |      10.0.0.0/16            |
          |                             |
          |  +-------------+            |
          |  | Public A    |            |
          |  | 10.0.1.0/24 |            |
          |  | AZ: 2a      |            |
          |  | Master EC2  |            |
          |  +-------------+            |
          |                             |
          |  +-------------+            |
          |  | Public B    |            |
          |  | 10.0.2.0/24 |            |
          |  | AZ: 2c      |            |
          |  | Worker ASG  |            |
          |  +-------------+            |
          |                             |
          |  Public Route Table         |
          |  10.0.0.0/16 -> local        |
          |  0.0.0.0/0   -> IGW          |
          +-----------------------------+
```

※ 구성도는 논리적 구조이며, Route Table은 패킷이 통과하는 별도 서버가 아니다.

## 2. VPC 및 Subnet 설계

| 항목              | 설정값                    |
| --------------- | ---------------------- |
| AWS Region      | ap-northeast-2 (서울)    |
| VPC 이름          | accordion-vpc          |
| VPC CIDR        | 10.0.0.0/16            |
| Public Subnet A | accordion-public-a     |
| Subnet A CIDR   | 10.0.1.0/24            |
| Subnet A AZ     | ap-northeast-2a        |
| Public Subnet B | accordion-public-b     |
| Subnet B CIDR   | 10.0.2.0/24            |
| Subnet B AZ     | ap-northeast-2c        |
| Master 배치       | Public Subnet A        |
| Worker ASG 배치   | Public Subnet B        |
| EC2 운영체제        | Rocky Linux 9 (x86_64) |

### 설계 참고사항

- VPC는 Master와 Worker가 통신하는 공통 네트워크이다.
- Master와 Worker는 서로 다른 Subnet에 배치하지만 사설 IP로 통신한다.
- Worker ASG는 현재 Subnet B를 사용하는 단순 구성이다.
- Worker의 사설 IP는 자동 생성 시 달라질 수 있으므로 고정 IP에 의존하지 않는다.
- 두 AZ를 사용하지만 Master가 단일 인스턴스이므로 고가용성 클러스터 구성은 아니다.

## 3. Internet Gateway 및 Route Table

### Internet Gateway

| 항목    | 설정값           |
| ----- | ------------- |
| 이름    | accordion-igw |
| 연결 대상 | accordion-vpc |

### Public Route Table

| 목적지         | 대상               | 설명        |
| ----------- | ---------------- | --------- |
| 10.0.0.0/16 | local            | VPC 내부 통신 |
| 0.0.0.0/0   | Internet Gateway | 인터넷 통신    |

**Route Table 이름:** accordion-public-rt

**연결 대상:** Public Subnet A, Public Subnet B

### 통신 경로

**Master → Worker**

```text
Master EC2
    |
    | 목적지: Worker 사설 IP
    v
Route Table: 10.0.0.0/16 -> local
    |
    v
Worker EC2
```

**EC2 → 인터넷**

```text
EC2
 |
 v
Security Group 아웃바운드 검사
 |
 v
Route Table: 0.0.0.0/0 -> IGW
 |
 v
Internet Gateway
 |
 v
Internet
```

EC2가 IGW를 통해 직접 인터넷 통신하려면 공인 IPv4 주소가 필요하다. Public Subnet의 공인 IP 자동 할당 설정 또는 EC2/Launch Template의 공인 IP 할당을 확인한다.

## 4. Security Group 설계 (초안)

외부 접근은 최소화하고, Kubernetes 클러스터 내부 통신은 SG 참조를 활용한다.

### 4-1. Master Security Group

**이름:** accordion-master-sg

| 프로토콜 | 포트    | 출발지            | 목적                |
| ---- | ----- | -------------- | ----------------- |
| TCP  | 22    | 관리자 공인 IP/32   | SSH 접속            |
| TCP  | 6443  | Worker SG      | Kubernetes API 접근 |
| TCP  | 6443  | 관리자 공인 IP/32   | 원격 kubectl 사용 시   |
| TCP  | 10250 | 필요한 클러스터 노드 SG | Kubelet API 통신    |

### 4-2. Worker Security Group

**이름:** accordion-worker-sg

| 프로토콜 | 포트    | 출발지              | 목적               |
| ---- | ----- | ---------------- | ---------------- |
| TCP  | 22    | 관리자 공인 IP/32     | SSH 접속           |
| TCP  | 10250 | Master SG        | Kubelet API 접근   |
| TCP  | 30080 | 관리자/부하 테스트 IP/32 | NodePort 웹서비스 접근 |

### 4-3. 클러스터 내부 통신

Master와 Worker 간 Kubernetes 및 Calico 통신을 허용해야 한다.

- Calico VXLAN 사용 시 UDP 4789를 노드 간 허용
- Kubernetes NodePort 사용 시 필요한 노드 간 TCP 통신 확인
- Master와 Worker 간 추가 포트는 A3의 실제 구성 기준으로 확정
- Worker 간 통신은 ASG로 추가되는 인스턴스까지 고려
- 필요 시 Master/Worker SG의 자기 참조 및 상호 참조 규칙 사용

### 4-4. 아웃바운드 정책

초기 구축 및 검증 단계에서는 다음 통신을 고려한다.

- Rocky Linux 패키지 다운로드
- Docker/ECR 이미지 다운로드
- DNS 질의
- Kubernetes API 통신
- Calico 및 Pod 네트워크 통신

초기 실습에서는 아웃바운드를 넓게 허용할 수 있으나, 인바운드 접근은 필요한 포트와 출발지로 제한한다.

**주의:** 위 SG 설정은 초안이며, A3의 kubeadm·Calico 구성 및 B2의 NodePort 설정에 따라 보완해야 한다.

## 5. Kubernetes 네트워크 대역

| 항목             | 설정값            |
| -------------- | -------------- |
| VPC CIDR       | 10.0.0.0/16    |
| Pod CIDR       | 172.20.0.0/16  |
| Service CIDR   | 10.96.0.0/12   |
| CNI            | Calico         |
| Kubernetes API | TCP 6443       |
| 웹서비스 NodePort  | TCP 30080 (예정) |

Pod CIDR 및 Service CIDR은 AWS VPC/Subnet CIDR과 겹치지 않도록 설정한다.

## 6. 담당자별 전달사항

### A2 — Terraform 담당

- VPC, Subnet, IGW, Route Table, SG 리소스 구현
- Master EC2를 Public Subnet A에 배치
- Worker ASG 및 Launch Template에 Worker SG 적용
- Master와 Worker의 공인 IPv4 할당 방식 확인
- Rocky Linux 9 AMI 사용
- Terraform Output으로 VPC ID, Subnet ID, SG ID, Master IP 제공
- 리소스 이름에 accordion 접두어 사용
- AWS 비용 및 리소스 삭제 계획 고려

### A3 — Linux/Kubernetes 담당

- Master API Server TCP 6443 확인
- Calico VXLAN 사용 여부 확인
- Master/Worker 간 추가 포트 확인
- 신규 Worker의 kubeadm join 자동화 방식 확인
- Rocky Linux 9의 firewalld 및 SELinux 설정 확인
- Pod CIDR 및 Service CIDR 적용값 확인

### B2 — Kubernetes 서비스/HPA 담당

- 웹서비스 NodePort 최종 포트 확인
- Pod 및 Service 통신 요구사항 공유
- HPA와 Cluster Autoscaler 연동 시 네트워크 요구사항 공유

## 7. 네트워크 검증 계획 (A1)

Terraform으로 AWS 인프라가 생성된 후 다음 항목을 검증한다.

| 검증 항목           | 확인 내용                           |
| --------------- | ------------------------------- |
| VPC/Subnet      | CIDR 및 AZ 설정 확인                 |
| Route Table     | 두 Public Subnet의 라우팅 연결 확인      |
| 인터넷 연결          | EC2에서 외부 저장소 접근 확인              |
| SSH             | 허용된 관리자 IP에서 접속 확인              |
| Master ↔ Worker | 사설 IP 기반 통신 확인                  |
| Kubernetes API  | Worker에서 Master TCP 6443 접근 확인  |
| Calico          | 노드 간 Pod 통신 확인                  |
| NodePort        | 지정한 외부 IP에서 웹서비스 접근 확인          |
| ASG             | 신규 Worker에 Subnet 및 SG 정상 적용 확인 |
| 보안              | 불필요한 외부 접근 차단 확인                |

## 8. 최종 확정이 필요한 항목

- [ ] A2: Terraform 네트워크 구현 방식 확인
- [ ] A3: Kubernetes 및 Calico 필수 포트 확정
- [ ] A3: Worker 자동 Join 방식 확정
- [ ] B2: NodePort 최종 포트 확정
- [ ] A1: Security Group 규칙 최종 확정
- [ ] A1: Terraform 구축 후 네트워크 검증

---

**현재 상태:** 네트워크 설계 초안 작성 완료. 실제 AWS 구축 및 통신 검증은 진행 전.

**다음 단계:** A2/A3와 설정값 협의 → SG 확정 → Terraform 구현 → 네트워크 연결 검증.
