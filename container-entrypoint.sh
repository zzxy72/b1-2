#!/usr/bin/env bash

set -euo pipefail

AGENT_HOME=/home/agent-admin/agent-app
AGENT_LOG_DIR=/var/log/agent-app

setfacl -m g:agent-common:rwx "$AGENT_HOME/upload_files"
setfacl -m d:g:agent-common:rwx "$AGENT_HOME/upload_files"
setfacl -m g:agent-core:rwx "$AGENT_HOME/api_keys"
setfacl -m d:g:agent-core:rwx "$AGENT_HOME/api_keys"
setfacl -m g:agent-core:rwx "$AGENT_LOG_DIR"
setfacl -m d:g:agent-core:rwx "$AGENT_LOG_DIR"

ufw default deny incoming >/dev/null || true
ufw default allow outgoing >/dev/null || true
ufw allow 15034/tcp >/dev/null || true
ufw --force enable >/dev/null || true

printf 'B1-2 agent leak lab is ready.\n'
printf 'Enter with: docker compose exec agent-lab bash\n'
printf 'Run a case as agent-admin, e.g.:\n'
printf '  su - agent-admin -c "MEMORY_LIMIT=64 CPU_MAX_OCCUPY=100 MULTI_THREAD_ENABLE=false ~/agent-app/bin/run-agent-case.sh oom-before"\n'

tail -f /dev/null
