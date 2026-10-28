[README.md](https://github.com/user-attachments/files/34056150/README.md)
# Chicken App v1.4 — Pod 단위 명시적 CPU 부하 제어

## 변경 사항
- `/api/load/toggle`은 더 이상 상태를 무조건 반전시키지 않습니다. `action=start` 또는 `action=stop`이 없으면 HTTP 400을 반환합니다.
- 새 API `POST /api/load/start`, `POST /api/load/stop`을 제공합니다. 중복 시작 요청은 이미 실행 중인 상태를 유지하며 부하를 새로 중첩하지 않습니다.
- CPU 부하는 요청을 처리한 Pod 안에서만 실행되고, 기본 15초(환경변수 `LOAD_MAX_SECONDS`, 최대 30초) 뒤 자동 종료됩니다.
- UI는 요청 응답의 Pod 이름을 표시하고 부하 시작/중지 버튼을 분리했습니다.
- `GET /api/load/status`는 응답 Pod, 남은 시간, 제어 범위(`this-pod-only`)를 반환합니다.
- `/api/load?seconds=5`는 0.1~10초로 제한된 단발 CPU 연산 API로 유지됩니다.

## 중요한 다중 Pod 동작
Kubernetes Service/NodePort는 각 HTTP 요청을 서로 다른 Pod로 전달할 수 있습니다. 이 앱은 외부 공유 상태 저장소를 사용하지 않으므로 시작과 중지는 **각 요청을 처리한 Pod에만 적용**됩니다. 따라서 중지 요청이 시작 요청과 다른 Pod에 도달하면 원래 Pod의 부하는 즉시 중단되지 않을 수 있지만, 최대 15초 후 자동 종료됩니다. 이는 무한 부하를 막고 다른 Pod에서 의도치 않은 부하가 시작되는 것을 방지합니다. 모든 Pod를 즉시 중앙 제어해야 한다면 Redis/DB 또는 Kubernetes API 기반의 공유 제어 상태가 추가로 필요합니다.

## Docker 이미지 빌드 및 푸시
프로젝트 루트(`Dockerfile`이 있는 폴더)에서 실행:

```bash
docker build -t chicken-app:v1.4 .
docker tag chicken-app:v1.4 916207038064.dkr.ecr.ap-northeast-2.amazonaws.com/accordion-team:v1.4
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin 916207038064.dkr.ecr.ap-northeast-2.amazonaws.com
docker push 916207038064.dkr.ecr.ap-northeast-2.amazonaws.com/accordion-team:v1.4
```

## Kubernetes 배포 참고
- 매니페스트는 사용자 요청에 맞춰 `chicken-app` Namespace, NodePort `30080`, HPA CPU `50%`, 최소 1 / 최대 3 replicas로 설정되어 있습니다.
- ECR 인증 Secret `ecr-secret`은 `chicken-app` Namespace 안에 만들어야 합니다. Secret은 Namespace 간 공유되지 않습니다. ECR 로그인 토큰은 약 12시간 유효하므로 재인증이 필요할 수 있습니다.
- 적용 순서 예시:

```bash
kubectl apply -f k8s/namespace.yaml
# ecr-secret을 chicken-app namespace에 생성한 다음
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/hpa.yaml
```

## API
- `GET /api/health`
- `GET /api/metrics`
- `GET /api/load/status`
- `POST /api/load/start`
- `POST /api/load/stop`
- `GET /api/load?seconds=5` (단발 부하, 최대 10초)
- `POST /api/load/toggle?action=start` 또는 `POST /api/load/toggle?action=stop` (호환 경로; action 필수)
