#!/usr/bin/env node

require('/opt/newsbot/node_modules/dotenv').config({ path: '/opt/newsbot/.env' });

const TelegramBot = require('/opt/newsbot/node_modules/node-telegram-bot-api');
const { initDb } = require('/opt/newsbot/app/db');
const config = require('/opt/newsbot/app/config');
const { toNewYorkDisplay } = require('/opt/newsbot/app/utils');

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function buildTestMessage(job) {
  const formattedTime = toNewYorkDisplay(job.event_time_utc);

  return [
    '🧪 <b>TEST ALERT</b>',
    '',
    'Este es un mensaje de prueba para validar la hora mostrada.',
    '',
    '🔔 <b>Market Event Alert</b>',
    '',
    `<b>Instrument:</b> ${escapeHtml(job.instrument)}`,
    `<b>Market:</b> ${escapeHtml(job.market)}`,
    `<b>Event:</b> ${escapeHtml(job.event_name)}`,
    `<b>Time (New York):</b> ${escapeHtml(formattedTime)}`,
    '',
    '⏰ <b>4 hours before</b>',
    '',
    'Prepárate para abrir el bot y desplegar la estrategia.',
  ].join('\n');
}

async function main() {
  if (!config.TELEGRAM_BOT_TOKEN) {
    throw new Error('Missing TELEGRAM_BOT_TOKEN in config');
  }

  const db = initDb();
  const bot = new TelegramBot(config.TELEGRAM_BOT_TOKEN);

  const job = db.prepare(`
    SELECT
      e.instrument,
      e.market,
      e.event_name,
      e.event_time_utc
    FROM scheduled_jobs sj
    INNER JOIN events e ON e.id = sj.event_id
    WHERE sj.template_name = '4h_before'
      AND e.active = 1
    ORDER BY datetime(e.event_time_utc) DESC
    LIMIT 1
  `).get();

  if (!job) {
    throw new Error('No 4h_before job found to use as a test template');
  }

  const users = db.prepare(`
    SELECT id, chat_id
    FROM users
    WHERE active = 1 AND subscribed_all = 1
    ORDER BY id ASC
  `).all();

  if (!users.length) {
    throw new Error('No active subscribed users found');
  }

  const message = buildTestMessage(job);

  for (const user of users) {
    await bot.sendMessage(user.chat_id, message, { parse_mode: 'HTML' });
  }

  console.log(`Sent test alert preview to ${users.length} user(s).`);
}

main().catch((err) => {
  console.error('test_alert_preview failed:', err);
  process.exit(1);
});
