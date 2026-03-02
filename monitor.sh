#!/bin/bash

PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ENV_FILE=".env"
STATE_FILE="state.json"
CHECK_INTERVAL=60
PREV_STATUS="healthy"
LAST_HEARTBEAT=0
FAILURES=""
STOP_REQUESTED=0

CURL_BIN="/usr/bin/curl"
NC_BIN="/usr/bin/nc"
DOCKER_BIN=""

on_signal() {
  STOP_REQUESTED=1
}

now_epoch() {
  /bin/date +%s
}

add_failure() {
  FAILURES="${FAILURES}$1\n"
}

json_escape() {
  printf '%s' "$1" | /usr/bin/sed ':a;N;$!ba;s/\\/\\\\/g;s/"/\\"/g;s/\r/\\r/g;s/\n/\\n/g'
}

init_bins() {
  if [ -x "/usr/local/bin/docker" ]; then
    DOCKER_BIN="/usr/local/bin/docker"
  elif [ -x "/opt/homebrew/bin/docker" ]; then
    DOCKER_BIN="/opt/homebrew/bin/docker"
  else
    DOCKER_BIN="$(command -v docker 2>/dev/null || true)"
  fi
}

send_discord() {
  local message="$1"
  local payload escaped

  if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
    return 0
  fi

  escaped="$(json_escape "$message")"
  payload="{\"username\":\"MacMini Watchdog\",\"content\":\"$escaped\"}"

  "$CURL_BIN" -sS --connect-timeout 2 --max-time 5 -X POST \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$DISCORD_WEBHOOK_URL" >/dev/null 2>&1 || true
}

write_state() {
  local status="$1"
  local heartbeat="$2"
  local tmp_file

  tmp_file="${STATE_FILE}.tmp"
  /bin/cat > "$tmp_file" <<EOF
{
  "status": "$status",
  "last_heartbeat": $heartbeat
}
EOF
  /bin/mv "$tmp_file" "$STATE_FILE" 2>/dev/null || true
}

read_state() {
  PREV_STATUS="healthy"
  LAST_HEARTBEAT=0

  if [ ! -f "$STATE_FILE" ]; then
    write_state "healthy" 0
    return 0
  fi

  local compact hb
  compact="$(/usr/bin/tr -d '[:space:]' < "$STATE_FILE" 2>/dev/null || true)"

  case "$compact" in
    *'"status":"failed"'*) PREV_STATUS="failed" ;;
    *'"status":"healthy"'*) PREV_STATUS="healthy" ;;
    *) PREV_STATUS="healthy" ;;
  esac

  hb="$(printf '%s' "$compact" | /usr/bin/sed -n 's/.*"last_heartbeat":\([0-9][0-9]*\).*/\1/p')"
  case "$hb" in
    ''|*[!0-9]*) LAST_HEARTBEAT=0 ;;
    *) LAST_HEARTBEAT="$hb" ;;
  esac
}

check_docker() {
  local i var_name container running_names rc

  i=1
  var_name="CHECK_DOCKER_${i}"
  if [ -z "${!var_name:-}" ]; then
    return 0
  fi

  if [ -z "$DOCKER_BIN" ] || [ ! -x "$DOCKER_BIN" ]; then
    while :; do
      var_name="CHECK_DOCKER_${i}"
      container="${!var_name:-}"
      [ -z "$container" ] && break
      add_failure "Docker unavailable for ${container}"
      i=$((i + 1))
    done
    return 0
  fi

  running_names="$("$DOCKER_BIN" ps --format '{{.Names}}' 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    i=1
    while :; do
      var_name="CHECK_DOCKER_${i}"
      container="${!var_name:-}"
      [ -z "$container" ] && break
      add_failure "Docker unavailable for ${container}"
      i=$((i + 1))
    done
    return 0
  fi

  i=1
  while :; do
    var_name="CHECK_DOCKER_${i}"
    container="${!var_name:-}"
    [ -z "$container" ] && break

    if ! printf '%s\n' "$running_names" | /usr/bin/grep -Fxq "$container"; then
      add_failure "Docker container not running: ${container}"
    fi
    i=$((i + 1))
  done
}

check_http() {
  local i var_name url
  i=1

  while :; do
    var_name="CHECK_HTTP_${i}"
    url="${!var_name:-}"
    [ -z "$url" ] && break

    if ! "$CURL_BIN" -sf --connect-timeout 2 --max-time 5 "$url" >/dev/null 2>&1; then
      add_failure "HTTP check failed: ${url}"
    fi
    i=$((i + 1))
  done
}

check_tcp() {
  local i var_name hostport host port
  i=1

  while :; do
    var_name="CHECK_TCP_${i}"
    hostport="${!var_name:-}"
    [ -z "$hostport" ] && break

    host="${hostport%:*}"
    port="${hostport##*:}"

    if [ -z "$host" ] || [ -z "$port" ] || [ "$host" = "$port" ]; then
      add_failure "Invalid TCP target: ${hostport}"
    elif ! "$NC_BIN" -z -w 5 "$host" "$port" >/dev/null 2>&1; then
      add_failure "TCP check failed: ${host}:${port}"
    fi
    i=$((i + 1))
  done
}

run_once() {
  local now heartbeat_interval

  heartbeat_interval="${HEARTBEAT_INTERVAL:-10800}"
  case "$heartbeat_interval" in
    ''|*[!0-9]*) heartbeat_interval=10800 ;;
  esac

  read_state
  now="$(now_epoch)"
  FAILURES=""

  check_docker
  check_http
  check_tcp

  if [ -n "$FAILURES" ]; then
    if [ "$PREV_STATUS" != "failed" ]; then
      send_discord "🚨 Server Failure: ${FAILURES}"
    fi
    write_state "failed" "$LAST_HEARTBEAT"
    return 0
  fi

  if [ "$PREV_STATUS" = "failed" ]; then
    send_discord "✅ Recovered: all checks passing"
    LAST_HEARTBEAT="$now"
  fi

  if [ $((now - LAST_HEARTBEAT)) -ge "$heartbeat_interval" ]; then
    send_discord "✅ Server OK: all checks passing"
    LAST_HEARTBEAT="$now"
  fi

  write_state "healthy" "$LAST_HEARTBEAT"
}

main() {
  trap on_signal INT TERM

  if [ -f "$ENV_FILE" ]; then
    . "$ENV_FILE"
  fi

  init_bins

  while true; do
    run_once || true

    if [ "$STOP_REQUESTED" -eq 1 ]; then
      break
    fi

    /bin/sleep "$CHECK_INTERVAL" &
    wait $!

    if [ "$STOP_REQUESTED" -eq 1 ]; then
      break
    fi
  done
}

main "$@"
