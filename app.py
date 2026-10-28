from flask import Flask, jsonify, request
import hashlib
import os
import time
import threading

app = Flask(__name__)
INSTANCE_ID = os.getenv("HOSTNAME", "local")

# cgroup v2 metrics are available in most modern Docker/Kubernetes Linux environments.
# CPU percentage is calculated as CPU time consumed during the polling interval.
_metrics_lock = threading.Lock()
_previous_cpu = None
_load_lock = threading.Lock()
_load_thread = None
_load_stop_event = threading.Event()
_load_active = False
_load_iterations = 0
_LOAD_MAX_SECONDS = max(1, min(int(os.getenv("LOAD_MAX_SECONDS", "15")), 30))
_load_started_at = None
_load_deadline = None


def _continuous_cpu_worker(deadline):
    """Run CPU work only until stopped or the mandatory deadline is reached."""
    global _load_iterations, _load_active, _load_started_at, _load_deadline
    value = b"chicken-app-bounded-load"
    counter = 0
    try:
        while not _load_stop_event.is_set() and time.monotonic() < deadline:
            value = hashlib.sha256(value + str(counter).encode()).digest()
            counter += 1
            if counter % 1000 == 0:
                with _load_lock:
                    _load_iterations += 1000
    finally:
        with _load_lock:
            _load_iterations += counter % 1000
            _load_active = False
            _load_started_at = None
            _load_deadline = None

def read_cgroup_metrics():
    global _previous_cpu
    now = time.monotonic()
    cpu_usage_usec = None
    memory_current = None
    memory_limit = None
    cpu_quota = None
    cpu_period = None

    try:
        with open("/sys/fs/cgroup/cpu.stat", "r", encoding="utf-8") as f:
            for line in f:
                parts = line.split()
                if len(parts) == 2 and parts[0] == "usage_usec":
                    cpu_usage_usec = int(parts[1])
                    break
    except (OSError, ValueError):
        pass

    try:
        with open("/sys/fs/cgroup/memory.current", "r", encoding="utf-8") as f:
            memory_current = int(f.read().strip())
    except (OSError, ValueError):
        pass

    try:
        with open("/sys/fs/cgroup/memory.max", "r", encoding="utf-8") as f:
            raw_limit = f.read().strip()
            if raw_limit != "max":
                memory_limit = int(raw_limit)
    except (OSError, ValueError):
        pass

    try:
        with open("/sys/fs/cgroup/cpu.max", "r", encoding="utf-8") as f:
            parts = f.read().strip().split()
            if len(parts) == 2 and parts[0] != "max":
                cpu_quota, cpu_period = int(parts[0]), int(parts[1])
    except (OSError, ValueError):
        pass

    cpu_percent = None
    if cpu_usage_usec is not None:
        with _metrics_lock:
            if _previous_cpu is not None:
                old_usage, old_time = _previous_cpu
                elapsed = now - old_time
                if elapsed > 0:
                    # 100% means one logical CPU fully used. Similar in spirit to docker stats;
                    # values can exceed 100% when the container can use multiple CPUs.
                    cpu_percent = max(0.0, (cpu_usage_usec - old_usage) / (elapsed * 1_000_000) * 100)
            _previous_cpu = (cpu_usage_usec, now)

    cpu_limit_cores = None
    if cpu_quota is not None and cpu_period:
        cpu_limit_cores = cpu_quota / cpu_period

    return {
        "cpu_percent": round(cpu_percent, 1) if cpu_percent is not None else None,
        "cpu_percent_note": "CPU 1개를 100%로 계산한 컨테이너 CPU 사용률 추정치입니다. 첫 조회는 기준값 수집으로 N/A가 표시됩니다.",
        "cpu_limit_cores": round(cpu_limit_cores, 2) if cpu_limit_cores is not None else None,
        "memory_used_bytes": memory_current,
        "memory_limit_bytes": memory_limit,
        "instance": INSTANCE_ID,
        "source": "container cgroup"
    }

@app.get("/")
def home():
    return """
    <!doctype html>
    <html lang="ko">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Chicken App - 모니터링</title>
      <style>
        :root { color-scheme: light; }
        body { font-family: system-ui, sans-serif; max-width: 900px; margin: 32px auto; padding: 0 18px; line-height: 1.55; background: #f7f8fa; color: #20242b; }
        h1 { margin-bottom: 4px; }
        .muted { color: #626b78; font-size: .92rem; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(210px, 1fr)); gap: 14px; margin: 18px 0; }
        .card { background: white; border: 1px solid #e0e4e9; border-radius: 14px; padding: 18px; box-shadow: 0 2px 8px #15223808; }
        .metric { font-size: 2rem; font-weight: 700; margin: 8px 0; }
        .bar { height: 10px; background: #e9edf2; border-radius: 99px; overflow: hidden; }
        .bar > div { height: 100%; width: 0; background: #3478f6; transition: width .25s ease; }
        button { border: 0; border-radius: 9px; padding: 11px 15px; cursor: pointer; background: #225fe5; color: white; font-weight: 600; }
        button:disabled { opacity: .6; cursor: wait; }
        code { background: #eef1f5; padding: 2px 5px; border-radius: 4px; overflow-wrap: anywhere; }
        .status { display: inline-block; padding: 3px 8px; border-radius: 20px; background: #e8f7ed; color: #16723b; font-size: .85rem; }
        pre { white-space: pre-wrap; overflow-wrap: anywhere; }
      </style>
    </head>
    <body>
      <h1>🐔 Chicken App</h1>
      <p class="muted">Docker / Kubernetes 프로젝트용 CPU 부하 테스트 및 컨테이너 리소스 모니터링</p>

      <div class="grid">
        <section class="card">
          <div class="muted">컨테이너 CPU 사용률</div>
          <div class="metric" id="cpu">측정 중...</div>
          <div class="bar"><div id="cpuBar"></div></div>
          <p class="muted" id="cpuNote">약 2초 간격으로 갱신합니다.</p>
        </section>
        <section class="card">
          <div class="muted">메모리 사용량</div>
          <div class="metric" id="memory">측정 중...</div>
          <div class="bar"><div id="memoryBar"></div></div>
          <p class="muted" id="memoryNote">사용량 / 제한량</p>
        </section>
        <section class="card">
          <div class="muted">인스턴스 / 상태</div>
          <p><span class="status" id="status">확인 중</span></p>
          <p>컨테이너/Pod: <code id="instance">-</code></p>
          <p>CPU 제한: <strong id="cpuLimit">확인 중</strong></p>
          <p class="muted">마지막 갱신: <span id="updated">-</span></p>
        </section>
      </div>

      <section class="card">
        <h2>CPU 부하 테스트</h2>
        <p>시작 버튼은 요청을 처리한 Pod에서만 CPU 부하를 실행합니다. 부하는 최대 <strong id="maxSeconds">15초</strong> 후 자동 종료됩니다. 중지는 해당 Pod에 전달되면 즉시 중단되며, 다른 Pod에 전달된 경우에도 자동 종료 시간은 넘지 않습니다.</p>
        <button id="loadButton" onclick="startCpuLoad()">CPU 부하 시작 (최대 15초)</button>
        <button id="stopButton" onclick="stopCpuLoad()" style="background:#c62828" disabled>CPU 부하 중지</button>
        <p id="result">부하 중지 상태</p>
      </section>

      <section class="card">
        <h2>안내</h2>
        <p class="muted">이 화면은 현재 웹앱 컨테이너의 cgroup 지표를 표시합니다. Ubuntu 전체 CPU 사용률이나 다른 컨테이너의 사용률은 표시하지 않습니다. CPU 100%는 논리 CPU 1개를 완전히 사용하는 수준이며, 환경에 따라 Docker CLI의 표시값과 차이가 날 수 있습니다.</p>
        <p><a href="/api/health">상태 확인 API</a> · <a href="/api/metrics">원본 지표 JSON</a></p>
      </section>

      <script>
        function fmtBytes(bytes) {
          if (bytes === null || bytes === undefined) return '확인 불가';
          const units = ['B', 'KB', 'MB', 'GB', 'TB'];
          let value = bytes, i = 0;
          while (value >= 1024 && i < units.length - 1) { value /= 1024; i++; }
          return value.toFixed(i === 0 ? 0 : 1) + ' ' + units[i];
        }

        async function refreshMetrics() {
          try {
            const response = await fetch('/api/metrics', {cache: 'no-store'});
            if (!response.ok) throw new Error('HTTP ' + response.status);
            const data = await response.json();
            document.getElementById('cpu').textContent = data.cpu_percent === null ? '측정 중...' : data.cpu_percent + '%';
            document.getElementById('cpuBar').style.width = Math.min(data.cpu_percent || 0, 100) + '%';
            document.getElementById('cpuNote').textContent = data.cpu_percent_note;
            document.getElementById('memory').textContent = fmtBytes(data.memory_used_bytes);
            const memLimit = data.memory_limit_bytes;
            document.getElementById('memoryNote').textContent = memLimit ? fmtBytes(data.memory_used_bytes) + ' / ' + fmtBytes(memLimit) : '메모리 제한 확인 불가';
            document.getElementById('memoryBar').style.width = memLimit && data.memory_used_bytes !== null ? Math.min(data.memory_used_bytes / memLimit * 100, 100) + '%' : '0%';
            document.getElementById('instance').textContent = data.instance || '-';
            document.getElementById('cpuLimit').textContent = data.cpu_limit_cores === null ? '확인 불가' : data.cpu_limit_cores + ' 코어';
            document.getElementById('status').textContent = '정상 응답';
            document.getElementById('updated').textContent = new Date().toLocaleTimeString();
          } catch (e) {
            document.getElementById('status').textContent = '측정 실패';
            document.getElementById('cpu').textContent = '오류';
            document.getElementById('cpuNote').textContent = String(e);
          }
        }

        async function refreshLoadStatus() {
          try {
            const response = await fetch('/api/load/status', {cache: 'no-store'});
            const data = await response.json();
            document.getElementById('maxSeconds').textContent = data.max_seconds + '초';
            document.getElementById('loadButton').disabled = data.active;
            document.getElementById('stopButton').disabled = !data.active;
            document.getElementById('result').textContent = data.active
              ? 'CPU 부하 실행 중 · Pod: ' + data.instance + ' · 자동 종료까지 약 ' + data.remaining_seconds + '초'
              : '부하 중지 상태 · 응답 Pod: ' + data.instance;
          } catch (e) {
            document.getElementById('result').textContent = '부하 상태 확인 실패: ' + e;
          }
        }

        async function loadAction(action) {
          const start = document.getElementById('loadButton');
          const stop = document.getElementById('stopButton');
          start.disabled = true; stop.disabled = true;
          try {
            const response = await fetch('/api/load/' + action, {method: 'POST', cache: 'no-store'});
            const data = await response.json();
            if (!response.ok) throw new Error(data.error || ('HTTP ' + response.status));
            document.getElementById('result').textContent = data.message + ' · Pod: ' + data.instance;
            await refreshLoadStatus();
          } catch (e) {
            document.getElementById('result').textContent = '요청 실패: ' + e;
          } finally {
            await refreshLoadStatus();
          }
        }
        async function startCpuLoad() { await loadAction('start'); }
        async function stopCpuLoad() { await loadAction('stop'); }

        refreshMetrics();
        refreshLoadStatus();
        setInterval(refreshMetrics, 2000);
        setInterval(refreshLoadStatus, 2000);
      </script>
    </body>
    </html>
    """

@app.get("/api/health")
def health():
    return jsonify(status="ok", instance=INSTANCE_ID)

@app.get("/api/metrics")
def metrics():
    return jsonify(read_cgroup_metrics())

@app.get("/api/load/status")
def load_status():
    with _load_lock:
        remaining = max(0, int((_load_deadline or time.monotonic()) - time.monotonic())) if _load_active else 0
        return jsonify(
            active=_load_active,
            iterations=_load_iterations,
            instance=INSTANCE_ID,
            max_seconds=_LOAD_MAX_SECONDS,
            remaining_seconds=remaining,
            control_scope="this-pod-only"
        )


@app.post("/api/load/start")
def start_load():
    """Idempotently start a bounded load on this Pod only."""
    global _load_thread, _load_active, _load_started_at, _load_deadline
    with _load_lock:
        if _load_active:
            remaining = max(0, int((_load_deadline or time.monotonic()) - time.monotonic()))
            return jsonify(active=True, instance=INSTANCE_ID, max_seconds=_LOAD_MAX_SECONDS,
                           remaining_seconds=remaining, message="이 Pod에서 이미 부하 실행 중입니다.")
        _load_stop_event.clear()
        _load_active = True
        _load_started_at = time.monotonic()
        _load_deadline = _load_started_at + _LOAD_MAX_SECONDS
        deadline = _load_deadline
        _load_thread = threading.Thread(target=_continuous_cpu_worker, args=(deadline,), daemon=True)
        _load_thread.start()
    return jsonify(active=True, instance=INSTANCE_ID, max_seconds=_LOAD_MAX_SECONDS,
                   remaining_seconds=_LOAD_MAX_SECONDS, message="CPU 부하를 시작했습니다. 자동 종료 시간이 설정되었습니다.")


@app.post("/api/load/stop")
def stop_load():
    """Idempotently stop load on this Pod; never toggles or starts load."""
    global _load_active
    with _load_lock:
        was_active = _load_active
        if was_active:
            _load_stop_event.set()
            _load_active = False
        thread = _load_thread
    if thread is not None and thread.is_alive():
        thread.join(timeout=2)
    return jsonify(active=False, instance=INSTANCE_ID, max_seconds=_LOAD_MAX_SECONDS,
                   remaining_seconds=0, message="이 Pod의 CPU 부하 중지 요청을 처리했습니다." if was_active else "이 Pod에서는 실행 중인 부하가 없습니다.",
                   stopped_on_this_pod=was_active)


# Backward-compatible endpoint: require an explicit action; never invert state.
@app.post("/api/load/toggle")
def toggle_load():
    action = request.args.get("action") or (request.get_json(silent=True) or {}).get("action")
    if action == "start":
        return start_load()
    if action == "stop":
        return stop_load()
    return jsonify(error="toggle endpoint no longer inverts state; send action=start or action=stop, or use /api/load/start and /api/load/stop", instance=INSTANCE_ID), 400


@app.get("/api/load")
def load():
    try:
        seconds = float(request.args.get("seconds", "5"))
    except ValueError:
        return jsonify(error="seconds must be a number"), 400

    seconds = max(0.1, min(seconds, 10.0))
    deadline = time.monotonic() + seconds
    counter = 0
    value = b"chicken-app"

    while time.monotonic() < deadline:
        value = hashlib.sha256(value + str(counter).encode()).digest()
        counter += 1

    return jsonify(
        status="completed",
        instance=INSTANCE_ID,
        requested_seconds=seconds,
        iterations=counter
    )

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, threaded=True)
