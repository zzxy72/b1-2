# B1-2 장애 분석 산출물

## 구성
- `01-oom-crash.md`: OOM/MemoryGuard 분석 리포트
- `02-cpu-latency.md`: CPU 과점유/CpuWorker 임계 위반 분석 리포트
- `03-deadlock.md`: Deadlock 분석 리포트
- `../artifacts/`: 실행 로그, monitor 로그, ps/top 증거

## 실행 방법
```bash
docker compose build
docker compose up -d

docker compose exec agent-lab bash
su - agent-admin

MEMORY_LIMIT=64 CPU_MAX_OCCUPY=100 MULTI_THREAD_ENABLE=false ~/agent-app/bin/run-agent-case.sh oom-before
MEMORY_LIMIT=128 CPU_MAX_OCCUPY=100 MULTI_THREAD_ENABLE=false ~/agent-app/bin/run-agent-case.sh oom-after
MEMORY_LIMIT=512 CPU_MAX_OCCUPY=100 MULTI_THREAD_ENABLE=false ~/agent-app/bin/run-agent-case.sh cpu-after
MEMORY_LIMIT=512 CPU_MAX_OCCUPY=10 MULTI_THREAD_ENABLE=true ~/agent-app/bin/run-agent-case.sh deadlock-live
```

`monitor.sh`는 각 케이스 실행 중 자동 호출되며, 로그는 `/var/log/agent-app`에 저장된다.
