#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Autopilot Check v2
# - richer report (env, deps, disk, durations)
# - optional auto pull (AUTOPILOT_PULL=1)
# - optional fail-only output (AUTOPILOT_QUIET=1)
# - stable python/pip usage
# ─────────────────────────────────────────────────────────────

TS="$(date +'%Y%m%d-%H%M%S')"
LOG_DIR="logs"
LOG="$LOG_DIR/check-$TS.log"
REPORT="$LOG_DIR/report-$TS.md"

AUTOPILOT_PULL="${AUTOPILOT_PULL:-0}"     # 1 to git pull --ff-only before checks
AUTOPILOT_QUIET="${AUTOPILOT_QUIET:-0}"   # 1 to print less to stdout
TAIL_LINES="${TAIL_LINES:-220}"           # tail lines per section in report
PY="${PY:-python3}"

mkdir -p "$LOG_DIR"

say () {
  if [[ "$AUTOPILOT_QUIET" == "1" ]]; then
    return 0
  fi
  echo "$@"
}

# timing helpers (bash 3.2 compatible)
now_s () { date +%s; }

echo "[autopilot] start $TS" | tee "$LOG"
{
  echo "# Autopilot Report ($TS)"
  echo ""
  echo "- cwd: \`$(pwd)\`"
  echo "- branch: \`$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'N/A')\`"
  echo "- host: \`$(hostname)\`"
  echo ""
} > "$REPORT"

run () {
  local title="$1"
  local cmd="$2"
  local t0 t1 rc
  t0="$(now_s)"

  echo "" | tee -a "$LOG" >/dev/null
  say "## $title"

  {
    echo "## $title"
    echo ""
    echo '```'
  } >> "$REPORT"

  set +e
  # shellcheck disable=SC2091
  (eval "$cmd") 2>&1 | tee -a "$LOG" | tail -n "$TAIL_LINES" >> "$REPORT"
  rc="${PIPESTATUS[0]}"
  set -e

  t1="$(now_s)"
  {
    echo '```'
    echo ""
    echo "- exit: \`$rc\`"
    echo "- duration: \`$((t1 - t0))s\`"
    echo ""
  } >> "$REPORT"

  return "$rc"
}

# ── Preflight ────────────────────────────────────────────────
run "preflight: disk" "df -h ."
run "preflight: uname" "uname -a"
run "preflight: git remote" "git remote -v || true"

# ── Optional pull (safe) ─────────────────────────────────────
if [[ "$AUTOPILOT_PULL" == "1" ]]; then
  run "git fetch" "git fetch --all --prune"
  run "git pull --ff-only" "git pull --ff-only"
fi

# ── Git status (always) ─────────────────────────────────────
run "git status" "git status -sb"

# ── Python env ───────────────────────────────────────────────
run "python: version" "$PY --version"
run "python: which" "command -v $PY && command -v pip3 || true"
run "python: pip list (top)" "$PY -m pip --version && $PY -m pip list | head -n 60"

# ── Tests ────────────────────────────────────────────────────
# If you want stricter: add -ra to show extra summary, and --maxfail=1 to stop fast
TEST_CMD="$PY -m pytest -q"
run "pytest" "$TEST_CMD" || {
  echo "" >> "$REPORT"
  echo "## ❌ Failure Summary" >> "$REPORT"
  echo "" >> "$REPORT"
  echo "- command: \`$TEST_CMD\`" >> "$REPORT"
  echo "- tip: open the full log: \`$LOG\`" >> "$REPORT"
  echo "" >> "$REPORT"
  echo "### last 120 lines of log" >> "$REPORT"
  echo '```' >> "$REPORT"
  tail -n 120 "$LOG" >> "$REPORT"
  echo '```' >> "$REPORT"

  echo "[autopilot] FAILED. report=$REPORT log=$LOG" | tee -a "$LOG"
  exit 1
}

# ── Done ─────────────────────────────────────────────────────
echo "" >> "$REPORT"
echo "✅ Done. Full log: $LOG" >> "$REPORT"
echo "[autopilot] OK. report=$REPORT log=$LOG" | tee -a "$LOG"
say "[autopilot] OK. report=$REPORT"