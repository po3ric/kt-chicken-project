# ACCORDION — Terraform 기반 Kubernetes 웹서비스 자동 확장 및 통합 모니터링

**KT Cloud Infrastructure Bootcamp | 치킨팀 (ACCORDION)**

## 1. 프로젝트 개요

Terraform을 활용하여 AWS 인프라를 구축하고, Docker 기반 웹 애플리케이션을 Kubernetes에 배포하여 CPU 사용률에 따라 Pod 수를 자동 확장·축소하는 시스템을 구현한 프로젝트입니다.

Metrics Server와 HPA를 통한 자동 확장, Kubernetes의 Self-Healing, Prometheus/Grafana를 이용한 통합 모니터링을 구현하고 검증했습니다.

## 2. 주요 기술 스택

| 영역 | 기술 |
|---|---|
| Cloud | AWS EC2, VPC, ECR, SSM |
| IaC | Terraform |
| OS | Ubuntu Server 24.04 LTS |
| Container | Docker, containerd |
| Orchestration | Kubernetes v1.36.5, kubeadm |
| Network | Calico, NodePort |
| Auto Scaling | Metrics Server, HPA |
| Monitoring | Prometheus, Grafana |
| Collaboration | Git, GitHub |

## 3. AWS 네트워크 아키텍처

**Region:** ap-northeast-2 (Seoul)

| 리소스 | CIDR | AZ |
|---|---|---|
| VPC | 10.0.0.0/16 | - |
| Public Subnet (NAT) | 10.0.1.0/24 | ap-northeast-2b |
| Private Subnet (Master) | 10.0.101.0/24 | ap-northeast-2b |
| Private Subnet (Worker) | 10.0.102.0/24 | ap-northeast-2d |

서브넷의 Availability Zone은 AWS CLI를 통해 확인한 실제 배포값입니다.

**[A1 네트워크 설계서](docs/network-design.md)**

## 4. 서비스 구성 및 처리 흐름

B1 웹앱 개발 → Docker 이미지 빌드 → Amazon ECR Push → B2 Kubernetes Deployment 배포 → NodePort Service 연동 → Metrics Server/HPA 자동 확장 → Prometheus/Grafana 모니터링

최종 서비스 접근은 AWS Systems Manager Session Manager와 Kubernetes NodePort를 활용합니다.

## 5. 최종 구현 결과

| 기능 | 결과 |
|---|---|
| Terraform AWS 인프라 구축 | 완료 |
| Kubernetes Master/Worker 클러스터 | 완료 |
| ECR v1.4 웹 애플리케이션 배포 | 완료 |
| NodePort Service | 완료 |
| HPA Scale-Out (1 → 최대 3 Pods) | 성공 |
| HPA Scale-In (최소 1 Pod 복귀) | 성공 |
| Pod Self-Healing | 성공 |
| Prometheus/Grafana 통합 모니터링 | 완료 |

**B2 최종 배포 설정**

- CPU Request / Limit: 100m / 500m
- Memory Request / Limit: 64Mi / 128Mi
- HPA CPU Target: 50%
- Min / Max Replicas: 1 / 3
- NodePort: 30080 → Service 80 → Pod 8080

## 6. 담당자별 소스코드 및 문서

| 담당 | 구현 영역 | 상세 자료 |
|---|---|---|
| A1 | AWS 네트워크 설계 | [Network Design](docs/network-design.md) |
| A2 | Terraform 인프라 자동화 | [Terraform Guide](infra/terraform/READMD.md) |
| A3 | Kubernetes 클러스터 구축 | [K8S Setup Guide](K8S_SETUP_GUIDE.md) |
| B1 | 웹 애플리케이션, Docker, ECR | [Web App Source](app.py) |
| B2 | Deployment, Service, HPA, Self-Healing | [B2 README](k8s/README.md) |
| B3 | Prometheus, Grafana | [Monitoring README](monitoring/README.md) |

### Kubernetes 배포 기준

최종 AWS 환경에 적용한 Kubernetes Manifest는 다음 파일을 기준으로 합니다.

- `k8s/deployment.yaml`
- `k8s/service.yaml`
- `k8s/hpa.yaml`

저장소 최상위의 별도 YAML과 혼동하지 않도록 주의합니다.

## 7. 테스트 및 모니터링 자료

- [B2 HPA 검증 자료](evidence/2026-10-16-b2-hpa/)
- [Grafana Dashboard](monitoring/images/Grafana%20Dashboard.png)
- [Monitoring 설정 및 패널](monitoring/)
- [Kubernetes 팀 연동 가이드](K8S_TEAM_B_GUIDE.md)

## 8. 프로젝트 한계 및 개선 방향

본 프로젝트는 고정된 EC2 Master/Worker 환경에서 Kubernetes Pod의 자동 확장을 검증했습니다.

EC2 Auto Scaling Group 및 ALB는 핵심 구현 범위에 포함하지 않았습니다. 실제 사용자 트래픽 기반 성능 테스트, Node Auto Scaling, 외부 HTTPS 진입점 및 모니터링 알림 고도화는 향후 개선 과제입니다.

---

**KT Cloud Infrastructure Bootcamp — ACCORDION (치킨팀)**

*Terraform 기반 Kubernetes 웹서비스 자동 확장 및 통합 모니터링 시스템 구축*
