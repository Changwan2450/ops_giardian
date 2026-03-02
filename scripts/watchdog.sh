#!/usr/bin/env bash
set -euo pipefail

# Load env
ENV_FILE="${ENV_FILE:-.env.watchdog}"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

: "${DISCORD_WEBHOOK_URL:?DISCORD_WEBHOOK_URL is required}"

TS="$(date +'%Y-%m-%d %H:%M:%S')"
HOST="$(hostname)"
OK=0
FAIL=0
LINES=()

http_check () {
  local name="$1"
  local url="$2"
  if curl -fsS --max-time 5 "$url" >/dev/null; then
    LINES+=("✅ HTTP $name: $url")
    OK=$((OK+1))
  else
    LINES+=("❌ HTTP $name: $url")
    FAIL=$((FAIL+1))
  fi
}

tcp_check () {
  local name="$1"
  local hostport="$2"
  local host="${hostport%:*}"
  local port="${hostport##*:}"
  if nc -z -w 3 "$host" "$port" >/dev/null 2>&1; then
    LINES+=("✅ TCP  $name: $host:$port")
    OK=$((OK+1))
  else
    LINES+=("❌ TCP  $name: $host:$port")
    FAIL=$((FAIL+1))
  fi
}

# Collect checks from env vars
i=1
while true; do
  v="CHECK_HTTP_$i"
  [[ -z "${!v:-}" ]] && break
  http_check "$v" "${!v}"
  i=$((i+1))
done

i=1
while true; do
  v="CHECK_TCP_$i"
  [[ -z "${!v:-}" ]] && break
  tcp_check "$v" "${!v}"
  i=$((i+1))
done

# Only notify when FAIL>0 (recommended)
ONLY_ON_FAIL="${ONLY_ON_FAIL:-1}"

if [[ "$ONLY_ON_FAIL" == "1" && "$FAIL" -eq 0 ]]; then
  exit 0
fi

TITLE="Watchdog @ ${HOST} (${TS})"
STATUS="OK=$OK FAIL=$FAIL"
BODY="$(printf "%s\n" "${LINES[@]}")"

# Discord webhook (simple content)
payload=$(python3 - <<PY
import json
print(json.dumps({"content": f"**{TITLE}**\n{STATUS}\n\n{BODY}"}))
PY
)

curl -fsS -H "Content-Type: application/json" -d "$payload" "$DISCORD_WEBHOOK_URL" >/dev/null
