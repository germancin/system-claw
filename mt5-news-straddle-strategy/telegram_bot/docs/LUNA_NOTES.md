# 🌙 Luna's Notes — Telegram News Straddle Bot

_My personal memory file for this bot. Read this when German asks about the telegram bot._

## What Is It

- A Telegram bot that sends automatic alerts before market news events
- Part of the MT5 News Straddle Strategy system
- Bot username: **@news_straddle_alerts_bot**
- It does NOT trade — it's a notification/preparation layer

## Where It Lives

- **Code:** `/opt/newsbot/` on the VPS (srv1374967)
- **Service:** `newsbot.service` (systemd) — `sudo systemctl restart newsbot`
- **Database:** `/opt/newsbot/data/newsbot.db` (SQLite, WAL mode)
- **Logs:** `/opt/newsbot/logs/bot.log` and `alerts.log`
- **Repo:** `system-claw/mt5-news-straddle-strategy/telegram_bot/`

## Key Commands

- `systemctl status newsbot` — check if running
- `sudo systemctl restart newsbot` — restart after code changes
- `npm run import` — re-import CSV calendar
- `npm run schedule` — schedule all `at` jobs for alerts
- `npm run rescue` — retry failed deliveries

## Bot Commands (Telegram)

- `/start` — register user
- `/today` — events today
- `/next` — events on the next event day (ALL events that day, not just one)
- `/status` — check registration
- `/help` — help

## Bug Fixes History

### 2026-03-26: `/next` only showing one event per day
- **Problem:** `getNextEventStmt` had `LIMIT 1`, so when multiple events fell on the same day it only showed the first one
- **Fix:** Added `getNextDayEventsStmt` that queries by NY date; `/next` handler now finds the next event's date, then fetches ALL events on that day
- **Affected dates examples:** 2026-03-30 (Tokyo CPI + China PMI), 2026-03-31 (France CPI + Germany CPI + Eurozone Flash CPI), 2026-04-30 (4 events!)

## Architecture Notes

- Alerts are scheduled using Linux `at` command (one-shot jobs)
- Each alert fires `send_alert.js --job-id <id>` which sends to all active users
- Retry logic: 3 attempts with exponential backoff (2s, 4s)
- Alert offsets: 24h, 4h, 3h, 2h, 1h, 30m before each event
- All times stored in UTC internally, displayed in Eastern Time

## Calendar

- CSV source: `data/market_news_calendar_mar_dec_2026.csv`
- Covers March–December 2026
- 9 instruments: XAUUSD, NAS100, WTI, FT100, DAX40, CAC40, EUSTX50, NK225, CHINA50
- Events: NFP, Core PCE, OPEC MOMR, UK CPI, Germany CPI, France CPI, Eurozone Flash CPI, Tokyo CPI, China PMI

## Things To Watch Out For

- The `.env` file has the real bot token — NEVER commit it (only `.env.example` goes to repo)
- The CSV has timezone offsets baked in (e.g., `-05:00` for EST, `-04:00` for EDT)
- `at` jobs run as root — they need the env vars to be available
- If the bot stops responding, check `systemctl status newsbot` first
