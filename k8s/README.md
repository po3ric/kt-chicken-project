
# B2 — Kubernetes Deployment, Service 및 HPA 자동 확장

**KT Cloud Infrastructure Bootcamp | ACCORDION (치킨팀)**

**담당 영역:** B2 — Kubernetes 웹서비스 배포, 서비스 연결, 리소스 관리 및 HPA 자동 확장

**프로젝트명:** Terraform 기반 Kubernetes 웹서비스 자동 확장 및 통합 모니터링 시스템 구축

**최종 검증일:** 2026-10-28

---

## 1. 담당 업무 개요

B2는 B1 담당자가 개발하고 Amazon ECR에 업로드한 Docker 웹 애플리케이션 이미지를 Kubernetes 클러스터에 배포하고, Service와 Horizontal Pod Autoscaler(HPA)를 구성하는 역할을 담당하였다.

CPU 사용률에 따라 Pod 수가 자동으로 확장 및 축소되는 기능과 Pod 삭제 시 자동으로 복구되는 Self-Healing 기능을 검증하였다.

### 주요 담당 업무

- Kubernetes Deployment YAML 작성 및 관리
- Amazon ECR 이미지와 Kubernetes Deployment 연동
- NodePort Service 구성 및 웹서비스 연결
- CPU 및 Memory Requests/Limits 설정
- Metrics Server 연동 및 CPU 메트릭 검증
- HPA 기반 Pod 자동 확장·축소 구현
- CPU 부하 테스트 및 HPA 동작 확인
- Pod 삭제를 통한 Self-Healing 테스트
- 테스트 결과 및 Kubernetes 이벤트 기록
- B1 웹서비스 및 B3 모니터링 담당자와 연동 검증

---

## 2. 개발 및 실행 환경

| 항목 | 최종 환경 |
| --- | --- |
| Cloud | AWS |
| Region | ap-northeast-2 (Seoul) |
| Operating System | Ubuntu Server 24.04 LTS |
| Kubernetes | v1.36.5 |
| Cluster | Master 1대 / Worker 1대 |
| Container Runtime | containerd |
| CNI | Calico |
| Container Image Registry | Amazon ECR |
| Application Image | accordion-team:v1.4 |
| Namespace | chicken-app |
| Deployment | chicken-app |
| Service Type | NodePort |
| Autoscaler | Kubernetes HPA |
| CPU Metrics | Metrics Server |
| Monitoring | Prometheus / Grafana |
| EC2 Access | AWS Systems Manager Session Manager |

### AWS 네트워크 구성

| 구분 | CIDR | Availability Zone |
| --- | --- | --- |
| VPC | 10.0.0.0/16 | Seoul |
| Public Subnet | 10.0.1.0/24 | ap-northeast-2b |
| Private Subnet (Master) | 10.0.101.0/24 | ap-northeast-2b |
| Private Subnet (Worker) | 10.0.102.0/24 | ap-northeast-2d |

위 Subnet의 AZ는 AWS CLI 조회 결과를 기준으로 확인하였다.

---

## 3. B2 소스코드 구성

최종 AWS Kubernetes 배포용 Manifest는 다음과 같다.

```text
k8s/
├── README.md
├── deployment.yaml
├── service.yaml
└── hpa.yaml
```

| 파일 | 역할 |
| --- | --- |
| deployment.yaml | 애플리케이션 Pod 생성 및 리소스 관리 |
| service.yaml | NodePort 기반 서비스 접근 |
| hpa.yaml | CPU 사용률 기반 Pod 자동 확장·축소 |

**최종 배포 기준은 `k8s/` 디렉터리의 B2 Manifest이다.**

B1의 로컬 테스트용 Kubernetes YAML과 구분하여 관리한다.

---

## 4. 웹 애플리케이션 배포 흐름

B1 담당자가 웹 애플리케이션을 개발하고 Docker 이미지를 빌드한 후 Amazon ECR에 Push하였다.

이후 B2는 ECR에 저장된 이미지를 Kubernetes Deployment에서 참조하고, Service 및 HPA를 구성하였다.

```text
B1: Web Application 개발
          |
          v
B1: Docker Image Build
          |
          v
B1: Amazon ECR Push
          |
          v
B2: Kubernetes Deployment
          |
          v
Worker Node에서 ECR Image Pull
          |
          v
chicken-app Pod 실행
          |
          v
B2: NodePort Service 연결
          |
          v
B2: Metrics Server + HPA 연동
          |
          v
CPU 부하에 따른 Pod 자동 확장·축소
          |
          v
B3: Prometheus / Grafana 모니터링
```

### 최종 컨테이너 이미지

```text
916207038064.dkr.ecr.ap-northeast-2.amazonaws.com/accordion-team:v1.4
```

최종 Deployment에서는 웹 애플리케이션 이미지 v1.4를 사용하였다.

---

## 5. Deployment 구성

**파일:** `k8s/deployment.yaml`

Deployment는 웹 애플리케이션 Pod의 실행 상태와 원하는 Replica 수를 관리한다.

### 주요 설정

| 항목 | 설정값 |
| --- | --- |
| Deployment Name | chicken-app |
| Initial Replicas | 1 |
| Container Image | accordion-team:v1.4 |
| Container Port | 8080 |
| CPU Request | 100m |
| CPU Limit | 500m |
| Memory Request | 64Mi |
| Memory Limit | 128Mi |
| Readiness Probe | /api/health |
| Liveness Probe | /api/health |

### 리소스 설정

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "64Mi"
  limits:
    cpu: "500m"
    memory: "128Mi"
```

CPU Request 100m은 0.1 CPU에 해당하며 Kubernetes Scheduler가 Pod 배치를 결정할 때 활용한다.

CPU Limit 500m은 0.5 CPU에 해당하며, CPU 사용량이 이를 초과하려 할 경우 Throttling이 발생할 수 있다.

Memory Request 64Mi는 스케줄링 시 고려하는 메모리 요청량이며, Memory Limit 128Mi는 컨테이너 메모리 사용 제한이다.

### Health Check

Readiness Probe와 Liveness Probe에 `/api/health` 경로를 적용하였다.

- Readiness Probe: 초기 지연 3초, 검사 주기 5초
- Liveness Probe: 초기 지연 10초, 검사 주기 10초

Readiness Probe는 Pod가 요청을 처리할 준비가 되었는지 확인한다.

Liveness Probe는 애플리케이션의 정상 동작 여부를 확인하고, 반복적인 실패 시 컨테이너 재시작을 유도한다.

---

## 6. Service 구성

**파일:** `k8s/service.yaml`

Kubernetes Service를 통해 Pod에 안정적으로 접근할 수 있도록 구성하였다.

### 주요 설정

```yaml
type: NodePort
selector:
  app: chicken-app
ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
    nodePort: 30080
```

### 트래픽 처리 흐름

```text
Client
  |
  v
NodePort :30080
  |
  v
Kubernetes Service :80
  |
  v
Application Pod :8080
```

- NodePort 30080: 노드에서 Service 접근에 사용하는 포트
- Port 80: Kubernetes Service 포트
- TargetPort 8080: 애플리케이션 컨테이너가 요청을 수신하는 포트

Service의 Selector `app: chicken-app`과 Deployment의 Pod Label을 일치시켰다.

Pod가 삭제되거나 재생성되어 IP 주소가 변경되더라도 Service를 통해 새로운 Pod로 요청을 전달할 수 있다.

### 서비스 접근 방식

최종 AWS 환경에서는 Private EC2에 직접 Public IP를 할당하지 않았으며, AWS SSM Session Manager를 통해 접근하였다.

SSM 포트포워딩과 Kubernetes NodePort를 활용하여 웹 애플리케이션 연결을 검증하였다.

Cloudflare Tunnel은 최종 서비스 구성에서 제외하였다.

---

## 7. Metrics Server 및 HPA 구성

**파일:** `k8s/hpa.yaml`

### 7.1 Metrics Server

HPA는 CPU 사용률을 기준으로 Replica 수를 조절하므로 Metrics Server를 통해 유효한 CPU 메트릭을 수집해야 한다.

Metrics Server는 Kubernetes Metrics API를 통해 Node 및 Pod의 CPU·메모리 사용량을 제공한다.

구성 과정에서 kubelet 인증서와 TLS 통신 관련 문제를 확인하였으며, A3 담당자와 협업하여 필요한 설정을 점검하고 Metrics Server 연동을 완료하였다.

정상 동작 여부는 다음 명령어로 확인하였다.

```bash
kubectl top nodes
kubectl top pods -n chicken-app
```

### 7.2 HPA 설정

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: chicken-app
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: chicken-app
  minReplicas: 1
  maxReplicas: 3
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
```

| 항목 | 값 |
| --- | --- |
| Scale Target | Deployment chicken-app |
| Minimum Replicas | 1 |
| Maximum Replicas | 3 |
| CPU Target | 50% |
| Metric Source | Metrics Server |

### 7.3 HPA 동작 원리

HPA는 CPU Limit이 아닌 CPU Request를 기준으로 CPU 사용률을 계산한다.

본 프로젝트의 CPU Request는 100m이며, 목표 CPU 사용률은 50%이다.

따라서 평균 CPU 사용량 약 50m을 목표로 Replica 수를 조절한다.

```text
CPU Request = 100m
HPA Target = 50%

목표 CPU 사용량 = 100m × 0.5 = 50m
```

CPU 사용률이 목표보다 높아지면 HPA는 필요한 Replica 수를 계산하여 Deployment에 반영한다.

CPU 사용률이 감소하면 안정화 과정을 거쳐 Replica 수를 축소한다.

HPA는 CPU Limit 500m에 도달해야만 확장하는 구조가 아니다.

---

## 8. HPA 자동 확장 및 축소 테스트

### 8.1 테스트 목적

웹 애플리케이션의 CPU 부하 증가와 감소에 따라 Kubernetes HPA가 Pod 수를 자동으로 조절하는지 확인하였다.

### 8.2 테스트 방식

B1이 구현한 웹 애플리케이션의 CPU 부하 생성 기능을 활용하였다.

브라우저가 아닌 실제 웹서버 Pod 내부에서 CPU 부하가 발생하도록 구성된 기능을 이용하였다.

### 8.3 Scale-Out 테스트

1. 초기 Pod 1개 실행 확인
2. 웹 애플리케이션 CPU 부하 생성
3. Pod CPU 사용률 상승 확인
4. Metrics Server의 CPU 메트릭 확인
5. HPA Replica 증가 확인
6. 최대 3개 Pod 실행 확인

**검증 결과: 성공**

CPU 부하 증가에 따라 HPA가 Replica 수를 증가시켰으며, Pod 수가 1개에서 최대 3개로 확장되는 것을 확인하였다.

### 8.4 Scale-In 테스트

1. CPU 부하 감소
2. CPU 사용률 하락 확인
3. HPA의 Replica 축소 동작 확인
4. 안정화 시간 경과
5. Pod 수 1개 복귀 확인

**검증 결과: 성공**

부하 감소 후 Pod 수가 다시 1개로 축소되는 동작을 확인하였다.

### 8.5 최종 테스트 버전

초기 테스트에서는 웹 애플리케이션 v1.3을 사용하였다.

이후 최종 웹 애플리케이션 v1.4를 적용하여 HPA 확장·축소 테스트를 진행하였으며 정상 동작을 확인하였다.

---

## 9. Self-Healing 테스트

### 9.1 테스트 목적

애플리케이션 Pod가 삭제되었을 때 Kubernetes가 원하는 Replica 수를 자동으로 유지하는지 검증하였다.

### 9.2 테스트 과정

1. 실행 중인 Pod 확인
2. 정상 상태의 Pod 하나 삭제
3. 기존 Pod가 Terminating 상태로 전환되는 과정 확인
4. ReplicaSet의 신규 Pod 생성 확인
5. 새로운 Pod가 Running 상태로 전환되는지 확인

### 9.3 테스트 결과

**검증 결과: 성공**

2026년 10월 21일 AWS Kubernetes 클러스터에서 정상 실행 중인 Pod를 삭제한 후 새로운 Pod가 자동으로 생성되는 것을 확인하였다.

신규 Pod가 Running 상태로 전환되었으며 Deployment가 원하는 Replica 수를 유지하는 것을 확인하였다.

### 9.4 기술적 의미

Kubernetes Deployment는 ReplicaSet을 통해 원하는 Pod 수를 유지한다.

Pod가 삭제되면 ReplicaSet Controller가 현재 Pod 수와 Desired Replica 수를 비교하여 부족한 Pod를 자동으로 생성한다.

본 테스트는 Pod 수준의 자동 복구 기능을 검증한 것으로, Worker Node 전체 장애에 대한 고가용성까지 검증한 것은 아니다.

---

## 10. 주요 검증 명령어

다음 명령어는 Kubernetes 클러스터에 연결된 관리 터미널에서 사용한다.

### Node 상태

```bash
kubectl get nodes -o wide
```

### Deployment 상태

```bash
kubectl get deployment chicken-app -n chicken-app
```

### Pod 상태

```bash
kubectl get pods -n chicken-app -o wide
```

### Service 상태

```bash
kubectl get service chicken-app -n chicken-app
```

### HPA 상태

```bash
kubectl get hpa chicken-app -n chicken-app
```

### HPA 상세 정보 및 이벤트

```bash
kubectl describe hpa chicken-app -n chicken-app
```

### Pod CPU 및 Memory 사용량

```bash
kubectl top pods -n chicken-app
```

### Kubernetes 이벤트

```bash
kubectl get events -n chicken-app --sort-by=.metadata.creationTimestamp
```

위 명령어들은 조회용이며 Kubernetes 리소스를 변경하지 않는다.

---

## 11. Kubernetes 배포 방법

### 사전 조건

- AWS EC2 및 Kubernetes 클러스터 구축 완료
- kubectl 연결 및 권한 설정 완료
- Metrics Server 설치 및 정상 동작
- Amazon ECR 이미지 접근 권한 확보
- Kubernetes Node 및 Pod 네트워크 정상 연결

### Namespace 생성

```bash
kubectl create namespace chicken-app
```

Namespace가 이미 존재하면 재생성하지 않는다.

### Deployment 적용

```bash
kubectl apply -n chicken-app -f k8s/deployment.yaml
```

### Service 적용

```bash
kubectl apply -n chicken-app -f k8s/service.yaml
```

### HPA 적용

```bash
kubectl apply -n chicken-app -f k8s/hpa.yaml
```

### 최종 상태 확인

```bash
kubectl get deployment,service,hpa,pods -n chicken-app
```

위 `apply` 명령어는 실제 클러스터 리소스를 생성하거나 변경하는 명령어이므로 배포 대상 환경을 확인한 후 실행한다.

---

## 12. 테스트 증빙 자료

B2의 HPA 및 Kubernetes 리소스 검증 과정에서 다음 자료를 수집하였다.

```text
evidence/2026-10-16-b2-hpa/
├── events.txt
├── final-cpu.txt
├── final-resources.txt
├── hpa-description.txt
└── hpa-scaling-events.txt
```

| 파일 | 내용 |
| --- | --- |
| events.txt | Kubernetes 이벤트 기록 |
| final-cpu.txt | CPU 사용량 확인 결과 |
| final-resources.txt | Kubernetes 리소스 상태 |
| hpa-description.txt | HPA 상세 설정 및 상태 |
| hpa-scaling-events.txt | HPA 확장·축소 관련 이벤트 |

자료는 테스트 시점의 상태를 기록한 것으로, 파일별 수집 시점과 최종 이미지 버전은 별도 확인이 필요하다.

---

## 13. 주요 문제 및 해결 과정

### 13.1 Metrics Server 및 TLS 문제

**문제:** HPA가 정상 동작하려면 Metrics Server가 kubelet으로부터 CPU 메트릭을 수집해야 했으며 인증서 및 TLS 관련 설정 확인이 필요하였다.

**해결:** A3 담당자와 협업하여 TLS 통신 및 Metrics Server 설정을 점검하였다.

**결과:** Pod CPU 메트릭 조회와 HPA 동작을 확인하였다.

### 13.2 ECR 이미지 및 Kubernetes 배포

**문제:** Amazon ECR에 업로드된 Docker 이미지를 Kubernetes 클러스터에서 정상적으로 가져와 실행해야 했다.

**해결:** B1이 업로드한 이미지를 Deployment에 지정하고 이미지 접근 및 Pod 실행 상태를 확인하였다.

**결과:** 웹 애플리케이션 v1.4를 Kubernetes에 배포하고 Service와 연동하였다.

### 13.3 HPA 자동 확장 테스트

**문제:** CPU 부하 발생 시점과 Metrics Server의 수집 주기, HPA 평가 간격에 따라 즉시 Replica 수가 증가하지 않을 수 있었다.

**해결:** 웹앱 CPU 부하 기능과 `kubectl top`, `kubectl get hpa`, `kubectl describe hpa`를 함께 사용하여 CPU 변화 및 HPA 이벤트를 검증하였다.

**결과:** HPA의 Scale-Out 및 Scale-In 동작을 확인하였다.

---

## 14. 구현 결과 및 한계

### 구현 결과

- AWS ECR 기반 웹 애플리케이션 Kubernetes 배포
- NodePort Service를 통한 네트워크 연결
- CPU 및 Memory Requests/Limits 적용
- Metrics Server를 통한 CPU 메트릭 수집
- HPA를 통한 Pod 자동 확장·축소 검증
- Deployment 기반 Self-Healing 검증
- B3 Prometheus/Grafana와 통합 모니터링 연계

### 프로젝트 한계

**인프라 확장성 제한**

현재 Master 1대와 Worker 1대로 구성되어 있어 Pod 자동 확장은 가능하지만 EC2 Node 자체의 자동 확장은 적용하지 않았다.

**실제 사용자 트래픽 검증 부족**

웹 애플리케이션 자체 CPU 부하 생성 기능을 이용하여 HPA를 검증하였다. 대규모 실제 사용자 트래픽에 대한 응답 시간 및 처리량 검증은 진행하지 않았다.

### 향후 개선 방향

- EC2 Auto Scaling 및 Kubernetes Node Auto Scaling 검토
- k6 기반 부하 테스트와 성능 지표 분석
- 외부 서비스 공개를 위한 HTTPS/TLS 적용 검토
- HPA 동작 및 자원 사용량 기반 운영 최적화
- 모니터링 알림 및 장애 대응 체계 고도화

---

## 15. 결론

B2 담당 영역에서는 B1이 Amazon ECR에 업로드한 Docker 웹 애플리케이션 이미지를 Kubernetes Deployment에 연동하여 배포하고, NodePort Service를 구성하였다.

Metrics Server와 HPA를 활용하여 CPU 목표 사용률 50%를 기준으로 Pod 수를 최소 1개에서 최대 3개까지 자동으로 조정하는 기능을 구현하였다.

최종 웹 애플리케이션 v1.4를 활용한 CPU 부하 테스트에서 자동 확장·축소를 검증했으며, Pod 삭제 후 새로운 Pod가 자동 생성되는 Self-Healing 기능도 확인하였다.

이를 통해 Kubernetes 기반 컨테이너 서비스 배포, 리소스 관리, 자동 확장 및 자동 복구 기능을 실제 AWS 환경에서 구현하고 검증하였다.

---

**ACCORDION (치킨팀)**  
**B2 — Kubernetes Deployment / Service / HPA**
