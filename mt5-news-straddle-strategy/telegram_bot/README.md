# Telegram Alert Bot — News Straddle Strategy

Automated Telegram bot that sends market event reminders before major economic releases.

## Quick Start

```bash
# 1. Install dependencies
cd telegram_bot
npm install

# 2. Copy and configure environment
cp .env.example .env
# Edit .env with your Telegram bot token

# 3. Import the event calendar
npm run import

# 4. Schedule alert jobs
npm run schedule

# 5. Start the bot
npm run bot
```

## Production Deployment

```bash
# Copy service file
sudo cp newsbot.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable newsbot
sudo systemctl start newsbot
```

## Documentation

- **[User Guide](docs/USER_GUIDE.md)** — How to use the bot (for end users)
- **[Technical Docs](docs/TECHNICAL.md)** — Architecture, database schema, deployment details

## Bot: @news_straddle_alerts_bot

Link: https://t.me/news_straddle_alerts_bot
