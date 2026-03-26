require('dotenv').config({ path: '/opt/newsbot/.env' });

module.exports = {
  TELEGRAM_BOT_TOKEN: process.env.TELEGRAM_BOT_TOKEN,
  DATABASE_PATH: process.env.DATABASE_PATH || '/opt/newsbot/data/newsbot.db',
  LOG_PATH: process.env.LOG_PATH || '/opt/newsbot/logs',
  TZ: process.env.TZ || 'America/New_York',
  ALERT_OFFSETS: [
    { name: '24h_before', minutes: 1440, label: '24 hours' },
    { name: '4h_before',  minutes: 240,  label: '4 hours' },
    { name: '3h_before',  minutes: 180,  label: '3 hours' },
    { name: '2h_before',  minutes: 120,  label: '2 hours' },
    { name: '1h_before',  minutes: 60,   label: '1 hour' },
    { name: '30m_before', minutes: 30,   label: '30 minutes' },
  ],
};
