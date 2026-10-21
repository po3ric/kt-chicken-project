# Accordion 프로젝트 AWS 네트워크 설계서

> **프로젝트:** Terraform 기반 Kubernetes 웹서비스 자동 확장 및 통합 모니터링 시스템 구축  
> **담당:** A1 — AWS 네트워크 설계 및 검증  
> **문서 기준:** 2026-10-21 (공유된 최신 아키텍처 기준)

## 1. 프로젝트 개요

### 1.1 프로젝트 목표

Terraform으로 AWS 인프라를 구성하고, Private EC2 기반 Kubernetes 환경에서 웹서비스의 자동 확장과 통합 모니터링을 구현한다.

- VPC 및 Public/Private Subnet을 통한 네트워크 분리
- Master/Worker EC2의 Private Subnet 배치
- NAT Gateway를 통한 Private EC2 아웃바운드 통신
- AWS Systems Manager(SSM)를 통한 원격 관리
- HPA 기반 CPU 사용률에 따른 Pod 자동 확장/축소
- Prometheus와 Grafana를 통한 모니터링

### 1.2 주요 사용 기술

| 구분 | 기술 |
|---|---|
| 클라우드 | AWS (서울 리전) |
| 인프라 자동화 | Terraform |
| 운영체제 | Ubuntu 24.04 |
| 컨테이너 이미지 빌드 | Docker |
| 이미지 저장소 | Amazon ECR |
| 컨테이너 런타임 | containerd |
| 오케스트레이션 | Kubernetes (kubeadm) |
| CNI | Calico |
| 자동 확장 | HPA, Metrics Server |
| 모니터링 | Prometheus, Grafana |
| 원격 관리 | AWS Systems Manager Session Manager |

---

## 2. AWS 네트워크 구성

### 2.1 VPC 설계

| 항목 | 설정 |
|---|---|
| VPC 이름 | `accordion-vpc` |
| AWS 리전 | `ap-northeast-2` (서울) |
| VPC CIDR | `10.0.0.0/16` |
| DNS Resolution | 활성화 (설계 기준) |
| DNS Hostnames | 활성화 (설계 기준) |

VPC는 AWS 리소스를 논리적으로 격리하고 Master와 Worker 간 내부 통신을 지원한다.

### 2.2 Subnet 설계

| Subnet | CIDR | 가용 영역 | 주요 리소스 |
|---|---|---|---|
| Public Subnet | `10.0.1.0/24` | `ap-northeast-2b` | NAT Gateway |
| Master Private Subnet | `10.0.101.0/24` | `ap-northeast-2b` | Master EC2 |
| Worker Private Subnet | `10.0.102.0/24` | `ap-northeast-2d` | Worker EC2 |

Master와 Worker에는 공인 IP를 할당하지 않아 인터넷에서 EC2로 직접 접근하는 경로를 제한한다.

> **참고:** 두 노드를 서로 다른 AZ에 배치했지만 Master와 Worker가 각각 1대이므로, 이 구성 자체가 Kubernetes 고가용성(HA)을 보장하지는 않는다.

### 2.3 논리 구성도

```text
Developer -> Docker Build -> Amazon ECR
                                  |
                              Image Pull
                                  v
AWS Cloud                     Worker EC2
|
+-- Systems Manager (SSM)
|      +-- Master EC2 원격 관리
|      +-- Worker EC2 원격 관리 / Port Forwarding
|
+-- VPC 10.0.0.0/16
       |
       +-- Internet Gateway
       |
       +-- Public Subnet (2b) 10.0.1.0/24
       |      +-- NAT Gateway
       |
       +-- Master Private Subnet (2b) 10.0.101.0/24
       |      +-- Master EC2 (Control Plane)
       |
       +-- Worker Private Subnet (2d) 10.0.102.0/24
              +-- Worker EC2
                     +-- Web Pods
                     +-- Metrics Server
                     +-- Prometheus / Grafana
```

> 이 구성도는 논리적인 배치 및 접근 관계를 요약한 것으로, 실제 패킷 흐름이나 Kubernetes 리소스의 물리적 위치를 모두 표현하지 않는다.

---

## 3. Internet Gateway 및 NAT Gateway

### 3.1 Internet Gateway

Internet Gateway(IGW)는 VPC와 인터넷 간 통신을 지원한다. Public Route Table의 기본 경로(`0.0.0.0/0`)가 IGW를 향하도록 설계한다.

### 3.2 NAT Gateway

NAT Gateway는 Public Subnet에 배치하고 Private Subnet의 기본 경로 대상으로 사용한다.

주요 사용 목적:

- 운영체제 패키지 설치 및 업데이트
- Kubernetes 관련 패키지 다운로드
- 외부 컨테이너 이미지 다운로드
- AWS 서비스 HTTPS 통신(별도 VPC Endpoint가 없는 경우)

NAT Gateway는 Private EC2로 향하는 외부의 직접적인 신규 인바운드 연결을 허용하지 않는다.

---

## 4. Route Table 설계

### 4.1 Public Route Table

| Destination | Target |
|---|---|
| `10.0.0.0/16` | `local` |
| `0.0.0.0/0` | Internet Gateway |

**연결 대상:** Public Subnet

### 4.2 Private Route Table

| Destination | Target |
|---|---|
| `10.0.0.0/16` | `local` |
| `0.0.0.0/0` | NAT Gateway |

**연결 대상:** Master Private Subnet, Worker Private Subnet

Master와 Worker 사이의 VPC 내부 통신은 `local` 경로를 사용하고 외부 인터넷 통신은 NAT Gateway를 경유한다.

---

## 5. Security Group 및 접근 보안

### 5.1 설계 원칙

- 최소 권한 원칙 적용
- Private EC2에 Public IP 미할당
- 인터넷에 SSH 포트 직접 공개하지 않음
- Kubernetes 및 CNI에 필요한 통신만 허용
- IAM 권한을 통해 AWS 리소스 및 SSM 접근 통제

### 5.2 주요 통신 포트

| 프로토콜 | 포트 | 용도 |
|---|---|---|
| TCP | `6443` | Kubernetes API Server |
| TCP | `10250` | Kubelet API |
| UDP | `4789` | Calico VXLAN 사용 시 |
| TCP | `443` | AWS 서비스 및 외부 HTTPS 통신(주로 아웃바운드) |

> 위 표는 주요 통신 요구사항이다. 실제 Security Group 규칙의 Source/Destination 및 Calico 관련 추가 포트는 적용된 설정을 기준으로 확인해야 한다. TCP 443을 인터넷에 인바운드로 개방한다는 뜻은 아니다.

---

## 6. EC2 구성 및 관리

### 6.1 EC2 배치

| 항목 | Master EC2 | Worker EC2 |
|---|---|---|
| 인스턴스 수 | 1대 | 1대 |
| Subnet | Master Private | Worker Private |
| AZ | `ap-northeast-2b` | `ap-northeast-2d` |
| 내부 IP (공유된 화면 기준) | `10.0.101.93` | `10.0.102.83` |
| Public IP | 없음 | 없음 |
| OS | Ubuntu 24.04 | Ubuntu 24.04 |
| 역할 | Kubernetes Control Plane | 애플리케이션 및 모니터링 워크로드 |

> 내부 IP는 공유된 실행 화면 기준이며 인스턴스 재생성 시 달라질 수 있다. 인스턴스 타입과 스토리지 용량은 최종 Terraform 설정에서 확인한다.

### 6.2 AWS Systems Manager (SSM)

Private EC2 관리는 AWS Systems Manager Session Manager를 이용한다.

- Master 및 Worker EC2 원격 관리
- SSH 포트의 외부 직접 공개 없이 세션 접속
- 포트 포워딩을 통한 내부 웹서비스 및 Grafana 접근

SSM을 사용하려면 EC2 인스턴스 프로파일/IAM 권한, SSM Agent 및 AWS SSM 서비스에 대한 네트워크 연결이 필요하다. 네트워크 연결은 NAT Gateway 또는 관련 VPC Endpoint를 통해 제공할 수 있다.

---

## 7. Docker 및 Amazon ECR

### 7.1 컨테이너 이미지 흐름

```text
Developer
   |
   v
Docker Build
   |
   | Image Push
   v
Amazon ECR
   |
   | Image Pull
   v
Worker EC2 (kubelet / containerd)
   |
   v
Web Pod
```

| 구성 요소 | 역할 |
|---|---|
| Docker | 웹 애플리케이션 컨테이너 이미지 빌드 |
| Amazon ECR | 컨테이너 이미지 저장 |
| containerd | Worker에서 컨테이너 실행 |
| Web Pod | 웹 애플리케이션 실행 |

> **검증 필요:** 실제 Web Pod가 ECR 이미지를 사용하는지 아래 명령으로 확인해야 한다. 이미지 주소가 다른 저장소를 가리킨다면 본 배포 흐름을 수정한다.

```bash
kubectl get pods -n chicken-app \
  -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}'
```

---

## 8. Kubernetes 및 웹서비스 구성

### 8.1 클러스터

| 항목 | 구성 |
|---|---|
| 구축 도구 | kubeadm |
| Kubernetes 버전 | v1.36.5 (공유된 환경 기준) |
| Master | 1대 |
| Worker | 1대 |
| 컨테이너 런타임 | containerd |
| CNI | Calico |

### 8.2 웹서비스 리소스

| 리소스 | 역할 |
|---|---|
| Web Deployment | Web Pod 생성 및 유지 관리 |
| Web Service | 실행 중인 Web Pod로 트래픽 전달 |
| Web Pods | 웹 애플리케이션 실행 |
| HPA | CPU 사용률에 따라 Deployment의 복제본 수 조절 |

```text
User
  |
  v
SSM Port Forwarding
  |
  v
Worker EC2
  |
  v
Web Service
  |
  +-- Web Pod 1
  +-- Web Pod 2
  +-- Web Pod 3
```

> SSM을 통한 웹서비스 접근은 프로젝트에서 사용한 포트 포워딩 방식의 개념도이다. 실제 포워딩 대상 포트와 Kubernetes Service 연결 방식은 배포 설정에 따라 달라진다.

---

## 9. HPA 자동 확장

### 9.1 설정

| 항목 | 값 |
|---|---|
| CPU 목표 사용률 | 50% |
| 최소 Pod 수 | 1 |
| 최대 Pod 수 | 3 |
| 메트릭 제공 | Metrics Server |
| 확장 대상 | Web Deployment |

### 9.2 동작 과정

1. 웹 애플리케이션에서 CPU 부하 발생
2. Metrics Server가 Pod의 CPU 사용률 제공
3. HPA가 CPU 사용률을 기준으로 필요한 복제본 수 계산
4. HPA가 Deployment의 복제본 수 조정
5. Deployment가 Web Pod를 추가하거나 축소

HPA의 CPU 사용률은 컨테이너에 설정된 CPU `requests`를 기준으로 계산한다.

---

## 10. Prometheus 및 Grafana

| 구성 요소 | 역할 |
|---|---|
| Metrics Server | HPA용 리소스 메트릭 제공 |
| Prometheus | 운영 메트릭 수집 및 저장 |
| Grafana | 모니터링 데이터 대시보드 시각화 |

주요 모니터링 항목:

- CPU 및 메모리 사용량
- Pod 개수 및 상태
- HPA 상태와 복제본 수
- 부하 테스트 전후 변화

Prometheus/Grafana는 Kubernetes 환경에서 운영하며, 내부 Grafana 서비스는 SSM 포트 포워딩으로 접근할 수 있다.

---

## 11. 네트워크 및 서비스 검증

| 번호 | 검증 항목 | 기대 결과 |
|---|---|---|
| 1 | VPC CIDR | `10.0.0.0/16` |
| 2 | Public Subnet | `10.0.1.0/24` |
| 3 | Master Private Subnet | `10.0.101.0/24` |
| 4 | Worker Private Subnet | `10.0.102.0/24` |
| 5 | Internet Gateway | VPC에 연결 |
| 6 | NAT Gateway | `Available` |
| 7 | Public Route Table | 기본 경로가 IGW |
| 8 | Private Route Table | 기본 경로가 NAT |
| 9 | EC2 배치 | Master/Worker 각각 Private Subnet |
| 10 | EC2 Public IP | 없음 |
| 11 | Private EC2 외부 통신 | 정상 |
| 12 | Master-Worker 통신 | 정상 |
| 13 | SSM 접속 | 정상 |
| 14 | Kubernetes Node | `Ready` |
| 15 | Web Pod | `Running` |
| 16 | HPA | 부하에 따른 복제본 수 변화 |
| 17 | Grafana | 메트릭 표시 |

### 11.1 검증 명령어

**인터넷 통신**

```bash
curl -I https://aws.amazon.com
```

**Kubernetes API 연결**

```bash
nc -vz <MASTER_PRIVATE_IP> 6443
```

**노드 상태**

```bash
kubectl get nodes -o wide
```

**전체 Pod 상태**

```bash
kubectl get pods -A -o wide
```

**웹 Pod 상태**

```bash
kubectl get pods -n chicken-app -o wide
```

**HPA 상태**

```bash
kubectl get hpa -n chicken-app
```

> 위 표는 **검증 항목 및 기대 결과**다. 실제 테스트 실행 결과를 확인한 후 완료 여부와 캡처/로그를 별도로 기록한다.

---

## 12. 담당 업무 및 협업

### 12.1 역할 분담

| 담당 | 주요 업무 |
|---|---|
| **A1** | AWS 네트워크 설계 및 검증 |
| A2 | Terraform 기반 AWS 인프라 구축 |
| A3 | Kubernetes 클러스터 구축 |
| B1 | 웹서비스 개발 및 Docker/ECR 배포 |
| B2 | HPA 구성 및 부하 테스트 |
| B3 | Prometheus/Grafana 모니터링 |

### 12.2 A1 담당 업무

1. VPC 및 Subnet 설계
2. CIDR 및 가용 영역 구성
3. Internet Gateway / NAT Gateway 설계
4. Route Table 설계
5. Security Group 정책 검토
6. IAM 계정 및 권한 관련 협업
7. SSM 기반 Private EC2 관리 방식 검토
8. Terraform 구축 결과 확인
9. AWS 리소스 배치 및 네트워크 연결 검증
10. 네트워크 설계서 및 아키텍처 구성도 작성
11. Kubernetes 담당자에게 인프라 구성 정보 전달

### 12.3 협업 흐름

A1이 네트워크 설계 기준과 보안 요구사항을 정리하고, A2가 Terraform으로 AWS 리소스를 구성한다. A3는 해당 EC2 환경에 Kubernetes 클러스터를 구축하며, B팀이 웹서비스·오토스케일링·모니터링을 연동한다.

---

## 13. 최종 확인 사항

아래 항목은 **최신 공유 자료와 설계 기준으로 정리했으나**, AWS 콘솔 및 실제 배포 설정과의 최종 대조가 필요하다.

- [ ] 실제 AWS 가용 영역이 `2b / 2d`인지 확인
- [ ] EC2 현재 내부 IP 및 인스턴스 타입 확인
- [ ] NAT Gateway와 Private Route Table 연결 확인
- [ ] Security Group 실제 인바운드/아웃바운드 규칙 확인
- [ ] IAM Role 및 SSM 연결 설정 확인
- [ ] Web Pod의 ECR 이미지 사용 여부 확인
- [ ] 웹서비스/Grafana 포트 포워딩 설정 확인
- [ ] HPA 동작 및 Grafana 대시보드 결과 기록
- [ ] 부하 테스트 도구(k6 포함 여부) 최종 확인

---

## 14. 결론

Accordion 프로젝트는 AWS 네트워크와 EC2 인프라를 기반으로 Kubernetes 웹서비스의 자동 확장 및 통합 모니터링 환경을 구성한다.

A1은 VPC, Subnet, 라우팅, NAT Gateway 및 접근 보안에 대한 **네트워크 설계와 검증**을 담당하며, Terraform 및 Kubernetes 담당자와 협업하여 전체 시스템에 필요한 네트워크 기반을 제공한다.

> **문서 상태:** 최신 공유 아키텍처 반영본. 실제 AWS 콘솔·Terraform 코드·배포 로그의 최종 검증 결과는 별도 반영 필요.
