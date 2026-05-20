# [Bug] CPU Latency - CPU_MAX_OCCUPY 과도 설정 시 CpuWorker 임계 위반

## 1. Description (현상 설명)
- `CPU_MAX_OCCUPY=100`으로 실행하면 `CpuWorker` 부하가 점진적으로 상승하다가 53.58%에서 임계 위반 로그를 남기고 종료된다.
- `CPU_MAX_OCCUPY=10`으로 낮추면 부하가 5~10% 범위에서 쿨다운되며 종료 없이 안정적으로 유지된다.

## 2. Evidence & Logs (증거 자료)
- 장애 조건: `MEMORY_LIMIT=512 CPU_MAX_OCCUPY=100 MULTI_THREAD_ENABLE=false`
- 프로그램 로그: `artifacts/cpu-after.app.log`

```text
2026-05-20 10:51:47,701 [INFO] [CpuWorker] Started. Maximum CPU Limit: 100%
2026-05-20 10:52:12,558 [INFO] [CpuWorker] Current Load: 20.09%
2026-05-20 10:52:28,088 [INFO] [CpuWorker] Current Load: 40.55%
2026-05-20 10:52:37,406 [INFO] [CpuWorker] Current Load: 53.58%
2026-05-20 10:52:37,511 [CRITICAL] [CpuWorker] CPU Threshold Violated! (53.58%).
```

- `monitor.sh`/`ps` 기반 관제: `artifacts/cpu-after.monitor.log`

```text
[2026-05-20 10:52:31] PROCESS:agent-app-leak PID:5373 ... CPU:0.8% RSS:21.2MB ...
[2026-05-20 10:52:36] PROCESS:agent-app-leak PID:5373 ... CPU:0.8% RSS:13.1MB ...
```

> 참고: 이 바이너리는 내부 `CpuWorker` 로그의 부하 지표를 기준으로 임계 위반을 판단한다. Docker/프로세스 관제의 `%CPU`는 낮게 보였지만, 앱 로그상 보호 정책은 53.58%에서 발동했다.

## 3. Root Cause Analysis (원인 분석)
- `CPU_MAX_OCCUPY=100`은 권장값 50% 이하를 넘는 위험 설정이다.
- 앱은 내부 워커 부하가 일정 수준을 넘으면 시스템 지연을 막기 위해 `CPU Threshold Violated` 경로로 종료한다.
- CPU 과점유는 런큐 대기 증가, 컨텍스트 스위칭 증가, 다른 요청 처리 지연으로 이어질 수 있으므로 보호 정책이 정상적으로 작동한 것으로 판단된다.

## 4. Workaround & Verification (조치 및 검증)
- 조치: `CPU_MAX_OCCUPY=100`에서 `CPU_MAX_OCCUPY=10`으로 낮춤.
- Before: 100% 설정에서 약 52초 후 53.58% 임계 위반으로 종료.
- After: 10% 설정에서 Peak 도달 후 쿨다운이 반복되고 종료 없이 유지.

```text
artifacts/cpu-before.app.log
2026-05-20 10:49:32,393 [INFO] [CpuWorker] Started. Maximum CPU Limit: 10%
2026-05-20 10:49:34,496 [INFO] [CpuWorker] Peak reached (10.00%). Starting cooldown...
2026-05-20 10:49:40,707 [INFO] [CpuWorker] Cooldown complete (5.00%). Resuming load increase...
```

- 근본적으로는 CPU 집약 작업을 제한하거나, 작업 큐/백프레셔/레이트 리밋을 적용해야 한다.
