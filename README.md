# b1-2

`agent-app-leak` 장애 분석 실습 결과물입니다.

## 제출물
- [미션 목표 상세 설명서](미션_목표_상세설명서.md)
- [OOM Crash 리포트](reports/01-oom-crash.md)
- [CPU Latency 리포트](reports/02-cpu-latency.md)
- [Deadlock 리포트](reports/03-deadlock.md)
- [실행/재현 안내](reports/README.md)
- [증거 로그](artifacts/)

## Docker 실습 환경
```bash
docker compose build
docker compose up -d
docker compose exec agent-lab bash
```

컨테이너 내부에서는 일반 사용자 조건을 맞추기 위해 `agent-admin`으로 실행합니다.

```bash
su - agent-admin
MEMORY_LIMIT=64 CPU_MAX_OCCUPY=100 MULTI_THREAD_ENABLE=false ~/agent-app/bin/run-agent-case.sh oom-before
```
