# Telegram Alert Bot — Technical Documentation

## Architecture Overview

The News Straddle Telegram Alert Bot is a Node.js application that sends automated market event reminders to registered Telegram users. It runs as a systemd service on the VPS.

### Components

```
/opt/newsbot/
├── .env                    # Environment variables (token, paths)
├── package.json            # Node.js dependencies
├── app/
│   ├── bot.js              # Main bot — Telegram polling + command handlers
│   ├── config.js           # Config loader (env vars + alert offsets)
│   ├── db.js               # SQLite database init + schema
│   ├── utils.js            # Helpers: timezone conversion, `at` job scheduling
│   └── send_alert.js       # Standalone alert sender (invoked by `at` jobs)
├── scripts/
│   ├── import_events.js    # Import CSV calendar → SQLite events table
│   ├── schedule_jobs.js    # Create scheduled_jobs + `at` cron entries
│   ├── reschedule_event.js # Reschedule a single event (cancel old, create new)
│   ├── rescue_failed.js    # Retry failed/partial deliveries
│   └── test_send.js        # Verify bot token works
├── data/
│   ├── newsbot.db          # SQLite database (WAL mode)
│   └── market_news_calendar_mar_dec_2026.csv  # Source calendar
└── logs/
    ├── bot.log             # Bot polling log
    └── alerts.log          # Alert delivery log
```

## Technology Stack

- **Runtime:** Node.js (v22+)
- **Database:** SQLite via `better-sqlite3` (WAL mode, foreign keys ON)
- **Telegram SDK:** `node-telegram-bot-api` (polling mode)
- **Scheduling:** Linux `at` command for one-shot timed alerts
- **Process manager:** systemd (`newsbot.service`)
- **Timezone:** All times internally in UTC; displayed in `America/New_York`

## Database Schema

### Tables

| Table | Purpose |
|---|---|
| `events` | Market events from the CSV calendar |
| `alert_templates` | Alert timing offsets (24h, 4h, 3h, 2h, 1h, 30m before) |
| `scheduled_jobs` | One row per event×template pair — tracks `at` job status |
| `users` | Registered Telegram users |
| `job_deliveries` | Per-user delivery tracking for each scheduled job |

### Key Indexes

- `idx_events_active`, `idx_events_time` — fast event lookups
- `idx_scheduled_jobs_status`, `idx_scheduled_jobs_trigger` — pending job queries
- `idx_users_active` — active user queries

### Job Status Flow

```
pending → scheduled → processing → sent
                                 → partial (some deliveries failed)
                                 → failed
                    → cancelled (event rescheduled)
```

## Alert Flow

1. **Import:** `npm run import` parses the CSV and inserts events into SQLite
2. **Schedule:** `npm run schedule` creates `scheduled_jobs` rows and registers Linux `at` jobs
3. **Fire:** When `at` triggers, it runs `node send_alert.js --job-id <id>`
4. **Deliver:** `send_alert.js` loads the job, builds the message, sends to all active users with retries (3 attempts, exponential backoff)
5. **Track:** Each user delivery is recorded in `job_deliveries` with status

## Bot Commands

| Command | Handler | Description |
|---|---|---|
| `/start` | `handleStart` | Register user, upsert into `users` table |
| `/help` | `handleHelp` | Show available commands |
| `/status` | `handleStatus` | Check if user is active + receiving alerts |
| `/today` | `handleToday` | Show all events for today (NY timezone) |
| `/next` | `handleNext` | Show all upcoming events on the next event day |

### `/next` Behavior (Updated 2026-03-26)

Previously returned only `LIMIT 1` (single event). Now:
1. Finds the first future event
2. Gets its NY date
3. Queries ALL active events on that same NY date
4. If 1 event → compact single-event format
5. If multiple → numbered list with individual countdowns

This fixes the bug where days with multiple events (e.g., 2026-03-30 has Tokyo CPI + China PMI) only showed one.

## Systemd Service

```bash
# Check status
systemctl status newsbot

# Restart after code changes
sudo systemctl restart newsbot

# View logs
tail -f /opt/newsbot/logs/bot.log
journalctl -u newsbot -f
```

## Scripts

```bash
# Import events from CSV
npm run import

# Schedule all pending alert jobs
npm run schedule

# Retry failed deliveries
npm run rescue

# Verify bot token
npm run test-send

# Reschedule a specific event
node scripts/reschedule_event.js --event-id 5 --new-time "2026-04-04T08:30:00-04:00"
```

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `TELEGRAM_BOT_TOKEN` | ✅ | — | Bot token from BotFather |
| `TZ` | No | `America/New_York` | System timezone |
| `DATABASE_PATH` | No | `/opt/newsbot/data/newsbot.db` | SQLite DB path |
| `LOG_PATH` | No | `/opt/newsbot/logs` | Log directory |
| `NODE_ENV` | No | — | `production` on VPS |

## Alert Offsets

Configured in `config.js`:

| Name | Minutes Before | Label |
|---|---|---|
| `24h_before` | 1440 | 24 hours |
| `4h_before` | 240 | 4 hours |
| `3h_before` | 180 | 3 hours |
| `2h_before` | 120 | 2 hours |
| `1h_before` | 60 | 1 hour |
| `30m_before` | 30 | 30 minutes |

## Deployment Location

- **Server:** VPS at `srv1374967`
- **Install path:** `/opt/newsbot/`
- **Service file:** `/etc/systemd/system/newsbot.service`
- **Database:** `/opt/newsbot/data/newsbot.db`
- **Logs:** `/opt/newsbot/logs/`
- **Bot username:** `@news_straddle_alerts_bot`
