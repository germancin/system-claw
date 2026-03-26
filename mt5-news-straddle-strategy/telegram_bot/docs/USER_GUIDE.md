# 📱 Telegram Alert Bot — User Guide

## What Is This?

A Telegram bot that sends you **automatic reminders** before each market news event relevant to the News Straddle strategy.

You get alerts at **24h, 4h, 3h, 2h, 1h, and 30 minutes** before each event so you're always ready.

All times are displayed in **New York / Miami time (Eastern Time)**.

## Getting Started

### Step 1: Open the Bot

Search in Telegram or use this link:
👉 **https://t.me/news_straddle_alerts_bot**

### Step 2: Send `/start`

This registers you automatically. You'll start receiving all market alerts.

### Step 3: Done!

Alerts come to you automatically. No further setup needed.

## Available Commands

| Command | What It Does |
|---|---|
| `/start` | Register and activate all alerts |
| `/today` | Show all market events scheduled for today |
| `/next` | Show all upcoming events on the next event day |
| `/status` | Check if your alerts are active |
| `/help` | Show help and available commands |

### About `/next`

When you send `/next`, the bot shows you the **next day that has events** and lists **all events on that day** — not just one. If there are 3 events on March 31st, you'll see all 3 with their individual countdowns.

### About `/today`

Shows every event happening today with times and instruments.

## What Do The Alerts Look Like?

You'll receive messages like:

```
🔔 Market Event Alert

Instrument: XAUUSD
Market: Metales (Oro spot)
Event: Nonfarm Payrolls / Employment Situation
Time (New York): Fri, Mar 6, 8:30 AM

⏰ 1 hour before

Prepárate para abrir el bot y desplegar la estrategia.
```

## Recommended Workflow

1. Receive alert → check your phone
2. Review market spread and conditions
3. Open MT5
4. Load the News Straddle EA
5. Verify `InpNewsTime` matches the event time
6. Leave the setup ready before the news hits

## Important Notes

- ⚠️ The bot **does not trade for you**. It's a preparation tool.
- The decision to deploy the EA and enter a trade is always yours.
- All times are in **Eastern Time (New York/Miami)**.
- The calendar covers **March to December 2026**.

## Covered Events

The bot tracks these major market-moving events:

- **XAUUSD** — Nonfarm Payrolls (NFP)
- **NAS100** — Core PCE
- **WTI** — OPEC Monthly Report (MOMR)
- **FT100** — UK CPI
- **DAX40** — Germany Preliminary CPI
- **CAC40** — France Preliminary CPI
- **EUSTX50** — Eurozone Flash CPI
- **NK225** — Tokyo CPI
- **CHINA50** — China Manufacturing PMI

## Need Help?

If the bot isn't responding or you're not getting alerts, try:
1. Send `/status` to check your registration
2. Send `/start` again to re-register
3. Make sure you haven't blocked the bot
