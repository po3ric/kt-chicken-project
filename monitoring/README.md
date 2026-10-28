## 1. 모니터링 구성

Kubernetes 클러스터와 웹서비스의 상태를 확인하기 위해 Helm 기반 `kube-prometheus-stack`으로 Prometheus와 Grafana를 구성하였다. 모니터링 구성요소는 `monitoring` 네임스페이스에 배포하였다.

Prometheus는 노드 및 컨테이너의 자원 사용량과 Kubernetes 리소스 상태를 수집하며, Grafana는 수집된 지표를 대시보드로 시각화한다.

| 구성요소 | 역할 |
|---|---|
| Node Exporter | 노드의 CPU·메모리·디스크 등 시스템 지표 제공 |
| kube-state-metrics | Deployment, Pod, HPA 등 Kubernetes 리소스의 상태 지표 제공 |
| kubelet/cAdvisor | 컨테이너 CPU·메모리 사용량 등 지표 제공 |
| Prometheus | 지표 수집 및 저장 |
| Grafana | 지표 조회 및 대시보드 시각화 |
| Metrics Server | HPA가 사용하는 CPU·메모리 자원 지표 제공 |

모니터링과 자동 확장은 다음 두 경로로 동작한다.

- **모니터링:** Node Exporter·kube-state-metrics·kubelet/cAdvisor → Prometheus → Grafana
- **자동 확장:** kubelet → Metrics Server → HPA → Deployment의 Pod 수 조정

### 설정 및 대시보드 관리

재현에 필요한 Helm 설정은 `monitoring/monitoring-values.yaml`로 관리한다. Grafana 대시보드는 JSON으로 내보내어 `monitoring/dashboards/`에 저장한다.

| 자료 | 저장 경로 |
|---|---|
| Helm 사용자 설정 | `monitoring/monitoring-values.yaml` |
| Grafana 대시보드 JSON | `monitoring/dashboards/` |
| 대시보드 캡처 | `docs/images/monitoring/` |

대시보드 JSON을 가져올 때는 해당 환경의 Prometheus 데이터 소스를 연결한다.

- 사용한 대시보드 이름: `[확인 필요]`
- 주요 패널 및 지표: `[실제 대시보드 기준으로 작성]`
- 최종 Helm 차트 버전 및 자원 설정: `[확인 필요]`

## 2. CPU 부하 테스트 방법

### 테스트 목적

웹서비스에 CPU 부하를 발생시킨 뒤 HPA의 Pod 확장·축소 동작과 Grafana의 지표 변화를 확인한다.

이 테스트는 CPU 기반 자동 확장의 동작을 검증하기 위한 것으로, 동시 접속자 수나 최대 처리량을 측정하는 성능 테스트와는 구분한다.

### 테스트 조건

아래 값은 구성 규격서의 기준이며, 최종 적용한 YAML과 비교하여 확정한다.

| 항목 | 규격서 기준 |
|---|---|
| 부하 발생 방법 | 웹사이트의 서버 측 CPU 부하 버튼 |
| 최소 Pod 수 | 1개 |
| 최대 Pod 수 | 3개 |
| HPA 목표 CPU 사용률 | CPU requests 대비 평균 50% |
| 컨테이너 CPU requests / limits | `100m` / `500m` |
| 부하 강도·지속 시간·실행 횟수 | `[확인 필요]` |

### 테스트 절차

1. 부하 실행 전 Pod 수와 CPU 사용량을 확인한다.
2. Grafana 대시보드와 HPA 상태 확인 화면을 준비한다.
3. 웹사이트에서 CPU 부하 버튼을 실행하고 시작 시각을 기록한다.
4. CPU 사용량과 HPA가 표시하는 사용률, Pod 수 변화를 관찰한다.
5. 추가 Pod가 생성되어 `Ready` 상태가 되는지 확인한다.
6. 부하 실행을 종료하거나 설정된 부하 시간이 끝날 때까지 기다린다.
7. CPU 사용량 감소와 안정화 이후 Pod 축소 여부를 확인한다.

HPA의 CPU 사용률은 **노드 전체 CPU가 아닌, 대상 Pod의 CPU requests를 기준으로 계산한 값**이다. 목표값을 초과하더라도 즉시 최대 Pod 수까지 확장되는 것은 아니다.

## 3. 테스트 결과 및 증거

테스트 과정은 부하 발생 전부터 종료 후 축소까지 단계별로 기록한다. Grafana 캡처에는 시간 범위가 보이도록 하고, 같은 시간대의 HPA 및 Pod 상태를 함께 남긴다.

| 단계 | 기록할 내용 |
|---|---|
| 부하 전 | 초기 Pod 수, CPU 사용량, HPA 상태 |
| 부하 중 | 부하 시작 시각, CPU 사용률 변화 |
| Pod 확장 | 확장 전후 Pod 수, 추가 Pod의 Ready 상태, 소요 시간 |
| 부하 종료 | 종료 시각, CPU 사용량 변화 |
| Pod 축소 | 최종 Pod 수, 축소까지 소요 시간 |

![alt text](/monitoring/images/Grafana%20Dashboard.png)


### 결과 해석

부하 종료 후 Pod 수가 1개로 줄어드는 동작을 확인하였다. 확장 시점의 Pod 수와 CPU 사용률, 확장·축소 소요 시간은 테스트 캡처를 기준으로 추가 기록한다.

또한 Pod 확장 후 CPU 사용률이 감소했는지는 별도로 확인한다. 부하 버튼이 특정 Pod 내부에서 작업을 수행하는 방식이라면, 새 Pod가 생성되어도 기존 작업이 자동으로 분산된다고 단정할 수 없다.

## 4. 트러블슈팅

### 4.1 Worker 노드 디스크 부족 및 모니터링 Pod 퇴거

**발생 증상**

Worker 노드에서 `no space left on device` 오류와 `DiskPressure` 상태가 발생하였다. 같은 시점에 Grafana 및 Prometheus Pod의 `Evicted` 상태를 확인하였다.

**원인 분석**

Worker 노드의 가용 디스크 공간이 부족한 상태에서 모니터링 구성요소를 운영하면서 디스크 압박이 발생하였다. Kubernetes는 노드의 자원 압박에 대응하여 Pod를 퇴거시킬 수 있다.

**해결 방향**

디스크 사용량과 이미지·로그·모니터링 데이터의 점유 공간을 확인하고, 불필요한 데이터를 정리하거나 디스크 용량을 확보한다. Prometheus의 데이터 보관 설정도 함께 검토한다.

**실제 적용 조치 및 결과**

- 적용한 조치: `[실제 수행한 정리·용량 확보·설정 변경 내용 입력]`
- 조치 후 디스크 사용량: `[확인 필요]`
- `DiskPressure` 해소 및 모니터링 Pod 정상 실행 여부: `[확인 필요]`

### 4.2 Grafana 메모리 부족으로 인한 종료

**발생 증상**

Grafana 컨테이너에서 `OOMKilled` 상태와 종료 코드 `137`을 확인하였다.

**원인 분석**

Grafana에 설정된 메모리 제한이 실행 중 필요한 사용량을 수용하지 못한 것으로 판단하였다.

**해결 방향**

Grafana의 실제 메모리 사용량과 노드의 가용 메모리를 확인하고, Helm values의 메모리 requests 및 limits 조정을 검토하였다. 당시 검토한 값은 requests `512Mi`, limits `1Gi`이며, 최종 적용 여부는 별도로 확인한다.

**실제 적용 조치 및 결과**

- 최종 메모리 requests / limits: `[확인 필요]`
- 조치 후 재시작 및 `OOMKilled` 재발 여부: `[확인 필요]`

두 장애를 통해 모니터링 도구 자체에도 CPU·메모리·디스크 자원이 필요하며, 애플리케이션과 함께 노드의 전체 자원 사용량을 고려해야 함을 확인하였다.