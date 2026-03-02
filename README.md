# ops_guardian

Minimal Mac Mini server monitor with Discord alerts.

## What it does

- Checks Docker containers by name
- Checks HTTP health endpoints
- Checks TCP ports
- Sends Discord alerts immediately on new failures
- Sends a healthy heartbeat every `HEARTBEAT_INTERVAL` seconds (default 10800, 3 hours)
- Prevents alert spam by tracking state transitions in `state.json`

## Files

The project is intentionally minimal:

- `monitor.sh`
- `state.json`
- `.env`
- `.env.example`
- `.gitignore`
- `README.md`

## Setup

1. Copy env template:

```bash
cp .env.example .env
```

2. Edit `.env` and set your webhook/checks.

3. Make script executable:

```bash
chmod +x monitor.sh
```

4. Run in foreground to verify (Ctrl+C to stop):

```bash
./monitor.sh
```

## `.env` format

```env
DISCORD_WEBHOOK_URL=
CHECK_DOCKER_1=srv_n8n
CHECK_DOCKER_2=srv_postgres
CHECK_HTTP_1=http://127.0.0.1:5678/healthz
CHECK_TCP_1=127.0.0.1:5432
HEARTBEAT_INTERVAL=10800   # 3 hours in seconds
```

## Behavior

- Failure detected:
  - If previous state was not failed: send `Server Failure` alert
  - Set status to `failed`
- Healthy detected:
  - If previous state was `failed`: send `Recovered` alert and reset heartbeat timer
  - If heartbeat interval elapsed: send `Server OK` heartbeat
  - Set status to `healthy`

## Launch Mode

### launchd (recommended)

Create `~/Library/LaunchAgents/com.local.ops-guardian.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.local.ops-guardian</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/your-user/path/to/ops_guardian/monitor.sh</string>
  </array>

  <key>WorkingDirectory</key>
  <string>/Users/your-user/path/to/ops_guardian</string>

  <key>KeepAlive</key>
  <true/>

  <key>RunAtLoad</key>
  <true/>

  <key>StandardOutPath</key>
  <string>/Users/your-user/path/to/ops_guardian/logs/monitor.out.log</string>

  <key>StandardErrorPath</key>
  <string>/Users/your-user/path/to/ops_guardian/logs/monitor.err.log</string>
</dict>
</plist>
```

Before loading, create log directory:

```bash
mkdir -p logs
```

Load and start:

```bash
launchctl unload ~/Library/LaunchAgents/com.local.ops-guardian.plist 2>/dev/null
launchctl load ~/Library/LaunchAgents/com.local.ops-guardian.plist
launchctl start com.local.ops-guardian
```

Check status:

```bash
launchctl list | grep ops-guardian
```

The script already runs its own internal loop (`sleep 60`), so launchd should start a single long-running process.

## Dependencies

Only these commands are required:

- `curl`
- `docker`
- `nc`

## Notes

- Script is Bash only (no Python/jq required).
- Keep `.env` private and never commit real webhook secrets.
