#!/usr/bin/env bash

set -euo pipefail

CASE_NAME="${1:-manual}"
AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
APP_BIN="${AGENT_HOME}/agent-app-leak"
APP_LOG="${AGENT_LOG_DIR}/${CASE_NAME}.app.log"
MONITOR_LOG="${AGENT_LOG_DIR}/${CASE_NAME}.monitor.log"
PID_FILE="${AGENT_LOG_DIR}/${CASE_NAME}.pid"

export AGENT_HOME
export AGENT_PORT="${AGENT_PORT:-15034}"
export AGENT_UPLOAD_DIR="${AGENT_UPLOAD_DIR:-${AGENT_HOME}/upload_files}"
export AGENT_KEY_PATH="${AGENT_KEY_PATH:-${AGENT_HOME}/api_keys}"
export AGENT_LOG_DIR
export MEMORY_LIMIT="${MEMORY_LIMIT:-128}"
export CPU_MAX_OCCUPY="${CPU_MAX_OCCUPY:-80}"
export MULTI_THREAD_ENABLE="${MULTI_THREAD_ENABLE:-true}"

rm -f "$APP_LOG" "$MONITOR_LOG" "$PID_FILE"

printf '[case] %s\n' "$CASE_NAME" | tee -a "$APP_LOG"
printf '[env] AGENT_HOME=%s AGENT_PORT=%s AGENT_UPLOAD_DIR=%s AGENT_KEY_PATH=%s AGENT_LOG_DIR=%s MEMORY_LIMIT=%s CPU_MAX_OCCUPY=%s MULTI_THREAD_ENABLE=%s\n' \
  "$AGENT_HOME" "$AGENT_PORT" "$AGENT_UPLOAD_DIR" "$AGENT_KEY_PATH" "$AGENT_LOG_DIR" \
  "$MEMORY_LIMIT" "$CPU_MAX_OCCUPY" "$MULTI_THREAD_ENABLE" | tee -a "$APP_LOG"

"$APP_BIN" >> "$APP_LOG" 2>&1 &
app_pid="$!"
printf '%s\n' "$app_pid" > "$PID_FILE"
printf '[started] pid=%s app_log=%s monitor_log=%s\n' "$app_pid" "$APP_LOG" "$MONITOR_LOG"

for _ in $(seq 1 180); do
  if ! kill -0 "$app_pid" 2>/dev/null; then
    break
  fi

  LOG_FILE="$MONITOR_LOG" "$AGENT_HOME/bin/monitor.sh" >> "$MONITOR_LOG.out" 2>&1 || true
  sleep "${MONITOR_INTERVAL_SECONDS:-2}"
done

wait "$app_pid" || true
printf '[finished] pid=%s exit_observed_at=%s\n' "$app_pid" "$(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$APP_LOG"
printf '[artifacts] %s %s %s\n' "$APP_LOG" "$MONITOR_LOG" "$MONITOR_LOG.out"
