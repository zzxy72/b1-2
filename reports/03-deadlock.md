# [Bug] Deadlock - 멀티스레드 자원 순환 대기로 프로세스 무응답

## 1. Description (현상 설명)
- `MULTI_THREAD_ENABLE=true`로 실행하면 프로세스 PID는 살아 있으나 CPU/RSS 변화가 멈추고 로그가 `WAITING ... BLOCKED` 이후 더 진행되지 않는다.
- `MULTI_THREAD_ENABLE=false`로 바꾸면 스케줄러 작업이 끝까지 완료되어 데드락이 회피된다.

## 2. Evidence & Logs (증거 자료)
- 장애 조건: `MEMORY_LIMIT=512 CPU_MAX_OCCUPY=10 MULTI_THREAD_ENABLE=true`
- 마지막 앱 로그: `artifacts/deadlock-live.app.log`

```text
2026-05-20 10:54:31,632 [INFO] [AgentWorker][Worker-Thread-1] LOCK ACQUIRED: [Shared_Memory_A]. (Holding...)
2026-05-20 10:54:31,633 [INFO] [AgentWorker][Worker-Thread-2] LOCK ACQUIRED: [Socket_Pool_B]. (Holding...)
2026-05-20 10:54:33,635 [INFO] [AgentWorker][Worker-Thread-2] WAITING for [Shared_Memory_A]... (Status: BLOCKED)
2026-05-20 10:54:33,635 [INFO] [AgentWorker][Worker-Thread-1] WAITING for [Socket_Pool_B]... (Status: BLOCKED)
```

- PID/스레드 존재 증거: `artifacts/deadlock-live.ps-top.txt`

```text
agent-a+    9912    9905  0 10:54 ? 00:00:00 /home/agent-admin/agent-app/agent-app-leak
agent-a+    9949    9912  0 10:54 ? 00:00:00 /home/agent-admin/agent-app/agent-app-leak
   9949   10172    9912  0.0  0.1 21524 SNl 00:16 agent-app-leak
   9949   10173    9912  0.0  0.1 21524 SNl 00:16 agent-app-leak
```

- 관제 로그: `artifacts/deadlock-live.monitor.log`

```text
[2026-05-20 10:54:44] PROCESS:agent-app-leak PID:9949 ... NLWP:3 CPU:0.3% RSS:21.0MB ...
[2026-05-20 10:54:48] PROCESS:agent-app-leak PID:9949 ... NLWP:3 CPU:0.2% RSS:21.0MB ...
[2026-05-20 10:54:51] PROCESS:agent-app-leak PID:9949 ... NLWP:3 CPU:0.2% RSS:21.0MB ...
```

## 3. Root Cause Analysis (원인 분석)
- Thread-1은 `Shared_Memory_A`를 점유한 상태로 `Socket_Pool_B`를 기다린다.
- Thread-2는 `Socket_Pool_B`를 점유한 상태로 `Shared_Memory_A`를 기다린다.
- 상호 배제, 점유 대기, 비선점, 순환 대기 조건이 동시에 만족되어 교착상태가 발생했다.

## 4. Workaround & Verification (조치 및 검증)
- 조치: `MULTI_THREAD_ENABLE=true`에서 `MULTI_THREAD_ENABLE=false`로 변경.
- Before: PID와 3개 스레드는 존재하지만 CPU/RSS가 정체되고 마지막 로그가 `BLOCKED`에서 멈춤.
- After: 단일/순차 실행 경로에서 `Scheduler All tasks completed`가 출력됨.

```text
artifacts/deadlock-after.app.log
2026-05-20 10:55:03,924 [INFO] [Scheduler] Starting task execution...
2026-05-20 10:55:04,693 [INFO] [Scheduler] All tasks completed.
```

- 근본 해결은 모든 스레드가 동일한 락 획득 순서를 따르도록 고정하거나, 타임아웃 기반 락 획득 실패 처리와 롤백을 추가하는 것이다.
