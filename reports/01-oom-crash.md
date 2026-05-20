# [Bug] OOM Crash - MemoryGuard 임계치 초과로 프로세스 자체 종료

## 1. Description (현상 설명)
- `agent-app-leak`를 `MEMORY_LIMIT=64`로 실행하면 약 8초 뒤 `MemoryGuard`가 임계치 초과를 감지하고 프로세스를 종료했다.
- 같은 조건에서 `MEMORY_LIMIT=128`로 올리면 종료 시점이 약 17초로 늦춰져, 메모리 한도가 생존 시간에 직접 영향을 주는 것을 확인했다.

## 2. Evidence & Logs (증거 자료)
- 실행 조건: `MEMORY_LIMIT=64 CPU_MAX_OCCUPY=100 MULTI_THREAD_ENABLE=false`
- 관제 로그: `artifacts/oom-before.monitor.log`

```text
[2026-05-20 10:48:50] PROCESS:agent-app-leak PID:215 ... RSS:21.0MB ...
[2026-05-20 10:48:51] PROCESS:agent-app-leak PID:215 ... RSS:46.0MB ...
[2026-05-20 10:48:54] PROCESS:agent-app-leak PID:215 ... RSS:71.0MB ...
```

- 프로그램 로그: `artifacts/oom-before.app.log`

```text
2026-05-20 10:48:51,148 [INFO] [MemoryWorker] Current Heap: 25MB
2026-05-20 10:48:54,155 [INFO] [MemoryWorker] Current Heap: 50MB
2026-05-20 10:48:57,180 [INFO] [MemoryWorker] Current Heap: 75MB
2026-05-20 10:48:57,180 [CRITICAL] [MemoryGuard] Memory limit exceeded (75MB >= 64MB)
2026-05-20 10:48:57,180 [CRITICAL] [MemoryGuard] Self-terminating process 215
```

## 3. Root Cause Analysis (원인 분석)
- `MemoryWorker`가 3초 간격으로 Heap을 25MB씩 증가시키며, 관제 RSS도 21MB -> 46MB -> 71MB로 상승했다.
- 힙에 적재된 객체가 해제되지 않아 프로세스의 상주 메모리(RSS)가 계속 증가했고, 앱 내부 보호 정책인 `MemoryGuard`가 `MEMORY_LIMIT` 초과 시 자체 종료를 수행했다.

## 4. Workaround & Verification (조치 및 검증)
- 조치: `MEMORY_LIMIT=64`에서 `MEMORY_LIMIT=128`로 상향.
- Before: 64MB 설정에서 75MB 도달 시 약 8초 만에 종료.
- After: 128MB 설정에서 150MB 도달 시 약 17초 만에 종료.

```text
artifacts/oom-after.app.log
2026-05-20 10:49:17,859 [INFO] [MemoryWorker] Current Heap: 125MB
2026-05-20 10:49:20,887 [CRITICAL] [MemoryGuard] Memory limit exceeded (150MB >= 128MB)
```

- 임시 조치로 생존 시간은 늘릴 수 있으나, 근본 해결은 누수 객체의 수명 관리와 주기적 해제 로직 보완이다.
