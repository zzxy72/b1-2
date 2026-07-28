#!/usr/bin/env bash

set -u
set -o pipefail

APP_PROCESS_NAME="${APP_PROCESS_NAME:-agent-app-leak}"
APP_PROCESS_PATTERN="${APP_PROCESS_PATTERN:-${APP_PROCESS_NAME}}"
AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
LOG_FILE="${LOG_FILE:-${AGENT_LOG_DIR}/monitor.log}"
MAX_LOG_SIZE_BYTES="${MAX_LOG_SIZE_BYTES:-10485760}"
MAX_LOG_BACKUPS="${MAX_LOG_BACKUPS:-10}"

CPU_THRESHOLD="${CPU_THRESHOLD:-20}"
MEM_RSS_THRESHOLD_MB="${MEM_RSS_THRESHOLD_MB:-128}"
DISK_THRESHOLD="${DISK_THRESHOLD:-80}"

# 로그 항목에 사용할 타임스탬프 문자열을 반환합니다.
timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

# 성공 메시지를 출력하며 추가 정보를 함께 표시합니다.
print_ok() {
  printf '%s\n' "$1 [OK]${2:+ $2}"
}

# 경고 메시지를 stdout으로 출력합니다.
print_warning() {
  printf '[WARNING] %s\n' "$1"
}

# 오류 메시지를 stderr로 출력합니다.
print_error() {
  printf '[ERROR] %s\n' "$1" >&2
}

# 로그 디렉터리가 존재하고 쓰기 가능한지 확인합니다.
ensure_log_dir() {
  if [[ ! -d "$AGENT_LOG_DIR" ]]; then
    print_error "Log directory does not exist: $AGENT_LOG_DIR"
    exit 1
  fi

  if [[ ! -w "$AGENT_LOG_DIR" ]]; then
    print_error "Log directory is not writable: $AGENT_LOG_DIR"
    exit 1
  fi
}

# 로그 파일이 최대 크기를 초과하면 회전시킵니다.
rotate_log_if_needed() {
  [[ -f "$LOG_FILE" ]] || return 0

  local size
  size="$(stat -c '%s' "$LOG_FILE" 2>/dev/null || echo 0)"
  [[ "$size" =~ ^[0-9]+$ ]] || size=0

  if (( size < MAX_LOG_SIZE_BYTES )); then
    return 0
  fi

  local i
  for (( i = MAX_LOG_BACKUPS - 1; i >= 1; i-- )); do
    if [[ -f "${LOG_FILE}.${i}" ]]; then
      mv "${LOG_FILE}.${i}" "${LOG_FILE}.$((i + 1))"
    fi
  done

  mv "$LOG_FILE" "${LOG_FILE}.1"
  : > "$LOG_FILE"
  rm -f "${LOG_FILE}.$((MAX_LOG_BACKUPS + 1))"
}

# 모니터링 대상 애플리케이션 프로세스의 PID를 찾습니다 (RSS 기준 가장 높은 것 선택).
find_app_pid() {
  ps -u "$(id -u)" -o pid=,rss=,args= \
    | awk -v pattern="$APP_PROCESS_PATTERN" '$0 ~ pattern { print $1, $2 }' \
    | sort -k2,2nr \
    | awk 'NR == 1 { print $1 }'
}

# 지정한 PID의 프로세스 리소스 메트릭을 수집합니다.
collect_process_metrics() {
  local pid="$1"
  ps -p "$pid" -o pid=,ppid=,nlwp=,pcpu=,pmem=,rss=,stat=,etime=,comm= \
    | awk '{$1=$1; print}'
}

# 루트 파일 시스템의 디스크 사용량을 수집합니다.
collect_disk_usage() {
  df -P / | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }'
}

# 설정된 에이전트 포트가 LISTEN 상태인지 확인합니다.
check_port() {
  if ss -ltn "( sport = :$AGENT_PORT )" 2>/dev/null | awk 'NR > 1 { found = 1 } END { exit !found }'; then
    print_ok "Checking port $AGENT_PORT..."
    return 0
  fi

  print_warning "TCP port $AGENT_PORT is not in LISTEN state."
}

# ufw가 설치된 경우 방화벽 상태를 확인합니다.
check_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    local ufw_status
    if [[ "$(id -u)" -eq 0 ]]; then
      ufw_status="$(ufw status 2>/dev/null || true)"
    elif command -v sudo >/dev/null 2>&1; then
      ufw_status="$(sudo -n ufw status 2>/dev/null || true)"
    else
      ufw_status=""
    fi

    if printf '%s\n' "$ufw_status" | grep -qi '^Status: active'; then
      print_ok "Checking UFW firewall status..."
    else
      print_warning "UFW firewall is not active."
    fi
    return 0
  fi

  print_warning "Neither ufw nor firewalld was found."
}

# 숫자형 메트릭이 임계값을 초과하면 경고를 출력합니다.
warn_if_exceeded() {
  local label="$1"
  local value="$2"
  local threshold="$3"
  local unit="$4"

  if awk -v value="$value" -v threshold="$threshold" 'BEGIN { exit !(value > threshold) }'; then
    print_warning "$label threshold exceeded (${value}${unit} > ${threshold}${unit})"
  fi
}

# 수집한 프로세스 및 디스크 메트릭을 모니터 로그에 추가합니다.
append_log() {
  local metrics="$1"
  local disk="$2"

  read -r pid ppid nlwp cpu mem rss_kb stat etime comm <<< "$metrics"
  local rss_mb
  rss_mb="$(awk -v kb="$rss_kb" 'BEGIN { printf "%.1f", kb / 1024 }')"

  printf '[%s] PROCESS:%s PID:%s PPID:%s NLWP:%s CPU:%s%% MEM:%s%% RSS:%sMB STAT:%s ELAPSED:%s DISK_USED:%s%%\n' \
    "$(timestamp)" "$comm" "$pid" "$ppid" "$nlwp" "$cpu" "$mem" "$rss_mb" "$stat" "$etime" "$disk" >> "$LOG_FILE"
}

# 모니터 실행의 메인 진입점입니다.
main() {
  local pid metrics disk rss_mb cpu

  ensure_log_dir
  rotate_log_if_needed

  printf '====== SYSTEM MONITOR RESULT ======\n\n'
  printf '[HEALTH CHECK]\n'

  pid="$(find_app_pid || true)"
  if [[ -z "$pid" ]]; then
    print_error "Process '$APP_PROCESS_NAME' is not running."
    exit 1
  fi
  print_ok "Checking process '$APP_PROCESS_NAME'..." "(PID: $pid)"
  check_port
  check_firewall

  metrics="$(collect_process_metrics "$pid")"
  disk="$(collect_disk_usage)"
  read -r _ _ _ cpu _ rss_kb _ _ _ <<< "$metrics"
  rss_mb="$(awk -v kb="$rss_kb" 'BEGIN { printf "%.1f", kb / 1024 }')"

  printf '\n[PROCESS RESOURCE MONITORING]\n'
  printf '%s\n' "PID PPID NLWP CPU% MEM% RSS_KB STAT ELAPSED COMMAND"
  printf '%s\n' "$metrics"
  printf 'RSS      : %sMB\n' "$rss_mb"
  printf 'DISK Used: %s%%\n\n' "$disk"

  warn_if_exceeded "CPU" "$cpu" "$CPU_THRESHOLD" "%"
  warn_if_exceeded "RSS" "$rss_mb" "$MEM_RSS_THRESHOLD_MB" "MB"
  warn_if_exceeded "DISK_USED" "$disk" "$DISK_THRESHOLD" "%"

  append_log "$metrics" "$disk"
  printf '\n[INFO] Log appended: %s\n' "$LOG_FILE"
}

main "$@"
