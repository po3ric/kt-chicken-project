# Accordion 프로젝트 AWS 네트워크 설계서

## 1. 프로젝트 개요

### 1.1 프로젝트명
Terraform 기반 Kubernetes 웹서비스 자동 확장 및 통합 모니터링 시스템 구축

### 1.2 네트워크 설계 목적

본 프로젝트는 Terraform을 활용하여 AWS 네트워크 및 EC2 인프라를 자동 구축하고, Kubernetes 기반 웹서비스의 안정적인 운영 환경을 구성하는 것을 목표로 한다.

웹서비스는 Kubernetes HPA(Horizontal Pod Autoscaler)를 이용하여 CPU 사용률에 따라 Pod 수를 자동으로 조절하며, Prometheus와 Grafana를 통해 시스템 상태를 모니터링한다.

### 1.3 주요 사용 기술

| 구분 | 기술 |
|---|---|
| 클라우드 | AWS |
| 인프라 자동화 | Terraform |
| 컨테이너 | Docker |
| 컨테이너 오케스트레이션 | Kubernetes |
| 클러스터 구성 | kubeadm |
| CNI | Calico |
| 이미지 저장소 | Amazon ECR |
| 자동 확장 | HPA |
| 모니터링 | Prometheus, Grafana |
| 부하 테스트 | k6 |

---

## 2. AWS 네트워크 구성

### 2.1 VPC 설계

| 항목 | 설정 |
|---|---|
| VPC 이름 | accordion-vpc |
| AWS 리전 | ap-northeast-2 (서울) |
| VPC CIDR | 10.0.0.0/16 |
| DNS Resolution | 활성화 |
| DNS Hostnames | 활성화 |

VPC는 프로젝트에서 사용하는 AWS 리소스를 논리적으로 격리하며, Kubernetes 클러스터를 구성하는 Master와 Worker EC2 간 내부 통신을 지원한다.

### 2.2 Subnet 설계

| Subnet | CIDR | 가용 영역 | 주요 리소스 |
|---|---|---|---|
| Public Subnet A | 10.0.1.0/24 | ap-northeast-2a | NAT Gateway |
| Private Subnet A | 10.0.101.0/24 | ap-northeast-2a | Master EC2 |
| Private Subnet C | 10.0.102.0/24 | ap-northeast-2c | Worker EC2 |

Master와 Worker는 각각 Private Subnet에 배치하며, 공인 IP를 할당하지 않는다.

이를 통해 외부 인터넷에서 EC2 인스턴스로 직접 접근하는 것을 제한한다.

### 2.3 네트워크 구성도

```text
                    Internet
                       |
                Internet Gateway
                       |
              VPC 10.0.0.0/16
                       |
              Public Subnet A
                10.0.1.0/24
                       |
                  NAT Gateway
                       |
              Private Route Table
                       |
          +------------+------------+
          |                         |
   Private Subnet A          Private Subnet C
    10.0.101.0/24             10.0.102.0/24
      AZ: 2a                    AZ: 2c
          |                         |
      Master EC2                Worker EC2
          |                         |
          +------ Kubernetes -------+
                       |
                 Web Service
                       |
                 HPA (CPU 50%)
                 Pod 1 ~ 3
                       |
              Prometheus/Grafana
```

※ 위 구성도는 논리적인 네트워크 및 서비스 구조를 표현한 것이다. NAT Gateway는 Private Route Table의 기본 경로로 사용된다.

---

## 3. Internet Gateway 및 NAT Gateway

### 3.1 Internet Gateway

Internet Gateway는 VPC와 인터넷 간 통신을 지원한다.

Public Subnet의 Route Table에 기본 경로를 설정하여 인터넷 연결을 제공한다.

### 3.2 NAT Gateway

NAT Gateway는 Public Subnet A에 배치한다.

Private Subnet의 Master 및 Worker EC2는 NAT Gateway를 통해 외부 인터넷으로 아웃바운드 통신을 수행한다.

주요 사용 목적은 다음과 같다.

- 운영체제 패키지 설치 및 업데이트
- Kubernetes 관련 패키지 다운로드
- 컨테이너 이미지 다운로드
- AWS 서비스와의 HTTPS 통신

NAT Gateway는 Private EC2로 향하는 외부의 직접적인 인바운드 접속을 허용하는 수단이 아니다.

---

## 4. Route Table 설계

### 4.1 Public Route Table

| Destination | Target |
|---|---|
| 10.0.0.0/16 | local |
| 0.0.0.0/0 | Internet Gateway |

연결 대상: Public Subnet A

### 4.2 Private Route Table

| Destination | Target |
|---|---|
| 10.0.0.0/16 | local |
| 0.0.0.0/0 | NAT Gateway |

연결 대상: Private Subnet A, Private Subnet C

Master와 Worker 간 통신은 VPC 내부 local 경로를 사용하며, 외부 인터넷 통신은 NAT Gateway를 경유한다.

---

## 5. Security Group 설계

### 5.1 설계 원칙

- 최소 권한 원칙 적용
- 불필요한 인바운드 포트 차단
- Master와 Worker 간 필요한 통신만 허용
- 외부 인터넷에 SSH 포트 직접 공개하지 않음
- Kubernetes 및 Calico 통신 방식에 따라 필요한 규칙 적용

### 5.2 주요 통신 포트

| 프로토콜 | 포트 | 용도 |
|---|---|---|
| TCP | 6443 | Kubernetes API Server |
| TCP | 10250 | Kubelet API |
| UDP | 4789 | Calico VXLAN 사용 시 |
| TCP | 443 | AWS 서비스 및 외부 HTTPS 통신 |

TCP 443은 주로 EC2의 아웃바운드 통신에 사용하며, 외부 인터넷에 인바운드로 개방하는 것을 의미하지 않는다.

실제 Security Group의 Source와 Destination, Calico 관련 포트는 Kubernetes 담당자(A3)와 협의하여 확정한다.

---

## 6. EC2 구성 및 관리

### 6.1 EC2 구성

| 구분 | Master EC2 | Worker EC2 |
|---|---|---|
| 인스턴스 수 | 1대 | 1대 |
| Subnet | Private Subnet A | Private Subnet C |
| 가용 영역 | ap-northeast-2a | ap-northeast-2c |
| Public IP | 없음 | 없음 |
| 역할 | Kubernetes Control Plane | 애플리케이션 및 모니터링 워크로드 |

EC2 인스턴스 타입, 운영체제 및 스토리지 용량은 Terraform 담당자(A2)와 Kubernetes 담당자(A3)가 협의하여 확정한다.

### 6.2 EC2 관리 접속

Private EC2의 관리 접속 방법으로 AWS Systems Manager Session Manager 사용을 우선 검토한다.

SSM 사용 시 필요한 IAM Role, SSM Agent 및 네트워크 연결 상태를 확인한다.

---

## 7. Kubernetes 및 HPA 구성

### 7.1 Kubernetes 클러스터

- Master Node: 1대
- Worker Node: 1대
- 클러스터 구축: kubeadm
- 컨테이너 런타임: containerd
- CNI: Calico

Pod CIDR, Service CIDR 및 Calico 통신 방식은 Kubernetes 담당자(A3)가 확정한다.

### 7.2 웹서비스 리소스 설정

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "64Mi"
  limits:
    cpu: "500m"
    memory: "128Mi"
```

### 7.3 HPA 설정

| 항목 | 설정 |
|---|---|
| CPU 목표 사용률 | 50% |
| 최소 Pod | 1개 |
| 최대 Pod | 3개 |
| 메트릭 수집 | Metrics Server |
| 부하 테스트 | k6 |

CPU 사용률에 따라 웹서비스 Pod가 자동으로 확장 및 축소되도록 구성한다.

HPA의 CPU 사용률은 Pod의 CPU requests를 기준으로 계산한다.

---

## 8. 모니터링 구성

Prometheus와 Grafana를 활용하여 Kubernetes 클러스터 및 웹서비스 상태를 모니터링한다.

### 주요 모니터링 항목

- CPU 사용률
- 메모리 사용량
- Pod 개수
- HPA 상태
- 부하 테스트 전후 변화

Prometheus는 메트릭 수집을 담당하고 Grafana는 대시보드를 통해 수집된 정보를 시각화한다.

HPA에 필요한 CPU 메트릭은 Metrics Server에서 제공한다.

---

## 9. 네트워크 검증 계획

| 번호 | 검증 항목 | 기대 결과 |
|---|---|---|
| 1 | VPC CIDR 확인 | 10.0.0.0/16 |
| 2 | Public Subnet 확인 | 10.0.1.0/24 |
| 3 | Private Subnet A 확인 | 10.0.101.0/24 |
| 4 | Private Subnet C 확인 | 10.0.102.0/24 |
| 5 | Internet Gateway 연결 | 정상 연결 |
| 6 | NAT Gateway 상태 | Available |
| 7 | Public Route Table | 기본 경로가 IGW |
| 8 | Private Route Table | 기본 경로가 NAT |
| 9 | Master EC2 배치 | Private Subnet A |
| 10 | Worker EC2 배치 | Private Subnet C |
| 11 | Private EC2 인터넷 통신 | 정상 |
| 12 | Master-Worker 통신 | 정상 |
| 13 | Kubernetes Node 상태 | Ready |
| 14 | Security Group 설정 | 필요한 포트만 허용 |
| 15 | SSM 관리 접속 | 구성 완료 후 접속 정상 |

### 주요 테스트 명령어

**인터넷 통신 확인**

```bash
curl -I https://aws.amazon.com
```

**Kubernetes API 연결 확인**

```bash
nc -vz <MASTER_PRIVATE_IP> 6443
```

**Kubernetes Node 확인**

```bash
kubectl get nodes -o wide
```

**Pod 확인**

```bash
kubectl get pods -A -o wide
```

※ 위 명령어는 검증 계획이며, 실제 테스트 결과는 인프라 구축 후 기록한다.

---

## 10. 담당 업무 및 협업

| 담당 | 주요 업무 |
|---|---|
| A1 | AWS 네트워크 설계 및 검증 |
| A2 | Terraform 기반 AWS 인프라 구축 |
| A3 | Kubernetes 클러스터 구축 |
| B1 | 웹서비스 개발 및 Docker/ECR 배포 |
| B2 | HPA 구성 및 k6 부하 테스트 |
| B3 | Prometheus/Grafana 모니터링 구축 |

### A1 담당 업무

1. VPC 및 Subnet 네트워크 설계
2. CIDR 및 가용 영역 구성
3. Internet Gateway와 NAT Gateway 설계
4. Route Table 설계
5. Security Group 정책 검토
6. Private EC2 관리 접속 검토
7. Terraform 구축 결과 검증
8. 네트워크 연결 테스트 및 결과 문서화

---

## 11. 미확정 사항

다음 항목은 각 담당자가 협의하여 결정한 후 문서에 반영한다.

- EC2 인스턴스 타입 및 디스크 용량
- 운영체제 및 AMI
- Kubernetes Pod CIDR / Service CIDR
- Calico 통신 방식 및 세부 Security Group 규칙
- 웹서비스와 Grafana의 발표용 접속 방식
- 모니터링 워크로드의 실제 리소스 요구량

---

## 12. 결론

본 프로젝트는 Terraform을 활용하여 AWS VPC, Subnet, Internet Gateway, NAT Gateway, Route Table, Security Group 및 EC2 인프라를 구성한다.

Master와 Worker EC2는 Private Subnet에 배치하여 외부 직접 접근을 제한하고, NAT Gateway를 통해 필요한 아웃바운드 통신을 제공한다.

구축된 AWS 인프라 위에 Kubernetes 클러스터를 구성하고, HPA를 이용한 웹서비스 Pod 자동 확장 및 Prometheus/Grafana 기반 통합 모니터링을 구현한다.

A1 담당자는 AWS 네트워크 설계와 Terraform 구축 결과 검증을 수행하며, 실제 테스트 결과를 최종 문서에 반영한다.
