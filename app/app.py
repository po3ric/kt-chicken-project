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


def _continuous_cpu_worker():
    """Consume CPU until the UI/API asks the worker to stop."""
    global _load_iterations
    value = b"chicken-app-continuous-load"
    counter = 0
    while not _load_stop_event.is_set():
        value = hashlib.sha256(value + str(counter).encode()).digest()
        counter += 1
        if counter % 1000 == 0:
            with _load_lock:
                _load_iterations += 1000
    with _load_lock:
        _load_iterations += counter % 1000

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
        <p>버튼을 한 번 누르면 이 컨테이너에서 CPU 연산을 계속 수행합니다. 다시 누르면 부하가 중지됩니다. 테스트가 끝나면 반드시 중지 버튼을 눌러 주세요.</p>
        <button id="loadButton" onclick="toggleCpuLoad()">CPU 부하 시작</button>
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
            const button = document.getElementById('loadButton');
            button.textContent = data.active ? 'CPU 부하 중지' : 'CPU 부하 시작';
            button.style.background = data.active ? '#c62828' : '#225fe5';
            document.getElementById('result').textContent = data.active
              ? 'CPU 부하 실행 중 — 다시 버튼을 누르면 중지됩니다.'
              : '부하 중지 상태';
          } catch (e) {
            document.getElementById('result').textContent = '부하 상태 확인 실패: ' + e;
          }
        }

        async function toggleCpuLoad() {
          const button = document.getElementById('loadButton');
          button.disabled = true;
          try {
            const response = await fetch('/api/load/toggle', {method: 'POST'});
            const data = await response.json();
            if (!response.ok) throw new Error(data.error || ('HTTP ' + response.status));
            await refreshLoadStatus();
          } catch (e) {
            document.getElementById('result').textContent = '요청 실패: ' + e;
          } finally {
            button.disabled = false;
          }
        }

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
        return jsonify(active=_load_active, iterations=_load_iterations, instance=INSTANCE_ID)


@app.post("/api/load/toggle")
def toggle_load():
    """Toggle continuous CPU work on/off from the web UI."""
    global _load_thread, _load_active
    with _load_lock:
        if _load_active:
            _load_stop_event.set()
            _load_active = False
            thread = _load_thread
        else:
            _load_stop_event.clear()
            _load_active = True
            _load_thread = threading.Thread(target=_continuous_cpu_worker, daemon=True)
            _load_thread.start()
            thread = None

    if thread is not None and thread.is_alive():
        thread.join(timeout=2)

    with _load_lock:
        return jsonify(active=_load_active, iterations=_load_iterations, instance=INSTANCE_ID)


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
