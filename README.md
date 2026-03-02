# ops_guardian

Ops tools: watchdog + autopilot runner.

## Setup
- Create `.env.watchdog` (ignored by git)
- Run:
  - `./watchdog` (alerts only on failure if configured)
  - `./autopilot` (runs checks and writes logs)
