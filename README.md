# KT Chicken Team

## Kubernetes 사용 가이드 (B조)

### 1. Kubernetes 접속 방법

1. AWS 팀 계정으로 로그인합니다.
2. EC2 콘솔에서 `accordion-master`를 선택합니다.
3. **연결 → Session Manager → 연결**을 클릭합니다.
4. SSM 터미널에서 Kubernetes 명령어를 실행합니다.

클러스터 상태 확인:

```bash
kubectl get nodes
```
Master와 Worker가 모두 `Ready`이면 정상입니다.

### 2. B조 작업 공간 (Namespace)

B조 애플리케이션은 **`chicken-app` Namespace**에서 관리합니다.

A3가 Namespace를 생성했고, `Active` 상태를 확인했습니다.

```bash
kubectl get namespace chicken-app
```

Namespace는 Kubernetes 리소스를 용도별로 구분하는 논리적 작업 공간입니다.

### 3. B조 기본 명령어

| 명령어 | 설명 |
|---|---|
| `kubectl get pods -n chicken-app` | Pod 목록 확인 |
| `kubectl get deploy -n chicken-app` | Deployment 확인 |
| `kubectl get svc -n chicken-app` | Service 확인 |
| `kubectl get hpa -n chicken-app` | HPA 확인 |
| `kubectl get pods -n chicken-app -o wide` | Pod IP 및 실행 노드 확인 |

애플리케이션 배포:

```bash
kubectl apply -f deployment.yaml -n chicken-app
```

`deployment.yaml`은 실제 YAML 파일명으로 변경합니다. YAML에 다른 Namespace가 지정되어 있거나 클러스터 범위 리소스가 포함되어 있다면 A3에게 확인합니다.

### 4. 작업 시 주의사항

- B조 애플리케이션은 `chicken-app`에서 작업합니다.
- `kubectl` 명령어에 `-n chicken-app`을 명시합니다.
- `kube-system`, `calico-system`, `tigera-operator`는 임의로 수정하지 않습니다.
- Node, Calico, Kubernetes 클러스터 설정 변경은 A3와 협의합니다.
- B3 모니터링 구성은 별도 Namespace와 권한을 협의합니다.

**참고:** 현재는 공동 관리자 계정을 사용하므로 Namespace 분리가 실제 관리자 권한을 차단하는 것은 아닙니다.

### 5. 장애 발생 시 확인 방법

**① Pod 상태 확인**

```bash
kubectl get pods -n chicken-app
```

**② Pod 상세 정보 및 이벤트 확인**

```bash
kubectl describe pod <POD_NAME> -n chicken-app
```

**③ Pod 로그 확인**

```bash
kubectl logs <POD_NAME> -n chicken-app
```

`<POD_NAME>`은 실제 Pod 이름으로 바꿔 입력합니다
