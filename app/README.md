# Chicken App — 버튼으로 켜고 끄는 지속 CPU 부하

이 버전은 k6를 사용하지 않습니다. 웹 화면의 **CPU 부하 시작** 버튼을 누르면 웹앱 컨테이너 안에서 CPU 연산을 계속 수행하고, **CPU 부하 중지** 버튼을 다시 누르면 연산을 중단합니다. CPU와 메모리 지표는 약 2초 간격으로 갱신됩니다.

## Docker 단일 호스트에서 실행

프로젝트 폴더에서 새 이미지를 빌드합니다.

```bash
docker build -t chicken-app:v1.3 .
```

기존 컨테이너를 유지하고 싶으면 먼저 이름을 바꾸어 백업합니다. 현재 컨테이너가 실제 사용 중인지 확인하고 진행하세요.

```bash
docker ps -a
docker stop chicken-app
docker rename chicken-app chicken-app-v1.2-backup
```

새 컨테이너를 실행합니다.

```bash
docker run -d --name chicken-app -p 8080:8080 chicken-app:v1.3
```

웹브라우저에서 `http://192.168.120.151:8080`으로 접속합니다. Cloudflare Tunnel을 사용 중이라면 기존 터널이 가리키는 앱 포트가 8080인지 확인하세요.

## 사용 방법

1. 웹페이지에서 **CPU 부하 시작**을 누릅니다.
2. CPU 지표가 오르는지 확인합니다. 다른 터미널에서 `docker stats chicken-app`을 실행해도 됩니다.
3. 테스트를 끝내려면 **CPU 부하 중지**를 누릅니다.

부하는 버튼을 다시 눌러 끌 때까지 계속 실행됩니다. 불필요하게 오래 켜 두지 마세요. 이 기능은 해당 웹앱 컨테이너의 CPU만 부하시키며, k6나 다른 부하 테스트 도구는 필요하지 않습니다.

## API

- `GET /api/load/status`: 부하 실행 여부 조회
- `POST /api/load/toggle`: 부하 시작/중지 전환
- `GET /api/metrics`: 컨테이너 cgroup 리소스 지표
- `GET /api/health`: 상태 확인

## Kubernetes 참고

Kubernetes Deployment에서 이 이미지를 사용하면 부하 연산은 해당 Pod 안에서 발생합니다. HPA 검증 시에는 요청이 실제 Kubernetes Pod에 도달하도록 Service/Ingress를 통해 접근해야 합니다. 여러 Pod가 있다면 버튼을 누른 요청을 처리한 Pod만 부하를 받습니다.
