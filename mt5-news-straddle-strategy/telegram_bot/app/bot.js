process.env.TZ = 'America/New_York';

const TelegramBot = require('node-telegram-bot-api');
const { initDb } = require('/opt/newsbot/app/db');
const config = require('/opt/newsbot/app/config');

const db = initDb();

if (!config.TELEGRAM_BOT_TOKEN) {
  throw new Error('Missing TELEGRAM_BOT_TOKEN in environment');
}

const bot = new TelegramBot(config.TELEGRAM_BOT_TOKEN, { polling: true });

const HTML_OPTS = {
  parse_mode: 'HTML',
  disable_web_page_preview: true,
};

const NY_TZ = 'America/New_York';

const upsertUserStmt = db.prepare(`
  INSERT OR IGNORE INTO users (telegram_user_id, chat_id, username, first_name, active, subscribed_all)
  VALUES (@telegram_user_id, @chat_id, @username, @first_name, 1, 1)
`);

const touchUserStmt = db.prepare(`
  UPDATE users
  SET chat_id = @chat_id,
      username = @username,
      first_name = @first_name,
      updated_at = datetime('now')
  WHERE telegram_user_id = @telegram_user_id
`);

const getUserStmt = db.prepare(`
  SELECT *
  FROM users
  WHERE telegram_user_id = ?
  LIMIT 1
`);

const getTodayEventsStmt = db.prepare(`
  SELECT id, instrument, market, event_name, reference_month, event_time_ny, event_time_utc, notes
  FROM events
  WHERE active = 1
    AND date(event_time_utc, '-4 hours') = date('now', '-4 hours')
  ORDER BY datetime(event_time_utc) ASC
`);

const getNextEventStmt = db.prepare(`
  SELECT id, instrument, market, event_name, reference_month, event_time_ny, event_time_utc, notes
  FROM events
  WHERE active = 1
    AND datetime(event_time_utc) > datetime('now')
  ORDER BY datetime(event_time_utc) ASC
  LIMIT 1
`);

const getNextDayEventsStmt = db.prepare(`
  SELECT id, instrument, market, event_name, reference_month, event_time_ny, event_time_utc, notes
  FROM events
  WHERE active = 1
    AND substr(event_time_ny, 1, 10) = ?
  ORDER BY datetime(event_time_utc) ASC
`);

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function getDisplayName(msg) {
  return msg.from?.first_name || msg.from?.username || 'friend';
}

function formatDateKeyInTimeZone(date, timeZone) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);

  const map = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${map.year}-${map.month}-${map.day}`;
}

function formatEventTime(dateInput) {
  const date = new Date(dateInput);
  return new Intl.DateTimeFormat('en-US', {
    timeZone: NY_TZ,
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  }).format(date);
}

function formatTimeRemaining(targetDateInput) {
  const targetMs = new Date(targetDateInput).getTime();
  let diff = Math.max(0, targetMs - Date.now());

  const dayMs = 24 * 60 * 60 * 1000;
  const hourMs = 60 * 60 * 1000;
  const minuteMs = 60 * 1000;

  const days = Math.floor(diff / dayMs);
  diff -= days * dayMs;
  const hours = Math.floor(diff / hourMs);
  diff -= hours * hourMs;
  const minutes = Math.floor(diff / minuteMs);

  const parts = [];
  if (days > 0) parts.push(`${days} day${days === 1 ? '' : 's'}`);
  if (hours > 0) parts.push(`${hours} hour${hours === 1 ? '' : 's'}`);
  if (minutes > 0 || parts.length === 0) parts.push(`${minutes} minute${minutes === 1 ? '' : 's'}`);

  return parts.join(', ');
}

function eventMatchesTodayNy(eventTimeUtc) {
  const todayNy = formatDateKeyInTimeZone(new Date(), NY_TZ);
  const eventNy = formatDateKeyInTimeZone(new Date(eventTimeUtc), NY_TZ);
  return todayNy === eventNy;
}

function formatEventLine(event, index) {
  const bits = [];
  bits.push(`<b>${index}. ${escapeHtml(event.event_name)}</b>`);
  bits.push(`🕒 ${escapeHtml(formatEventTime(event.event_time_utc))} (${escapeHtml(config.TZ || NY_TZ)})`);
  bits.push(`📈 ${escapeHtml(event.instrument)} • ${escapeHtml(event.market)}`);

  if (event.reference_month) {
    bits.push(`🗓️ Ref: ${escapeHtml(event.reference_month)}`);
  }

  if (event.notes) {
    bits.push(`📝 ${escapeHtml(event.notes)}`);
  }

  return bits.join('\n');
}

async function sendHtml(chatId, text) {
  return bot.sendMessage(chatId, text, HTML_OPTS);
}

async function handleStart(msg) {
  try {
    const payload = {
      telegram_user_id: msg.from.id,
      chat_id: msg.chat.id,
      username: msg.from.username || null,
      first_name: msg.from.first_name || null,
    };

    upsertUserStmt.run(payload);
    touchUserStmt.run(payload);

    const name = escapeHtml(getDisplayName(msg));
    await sendHtml(
      msg.chat.id,
      [
        `👋 <b>Welcome, ${name}!</b>`,
        '',
        'You are now registered para recibir market news alerts automáticamente.',
        'Este bot te mandará avisos sobre eventos del mercado y próximas publicaciones importantes.',
        '',
        'Use <code>/help</code> to see commands disponibles.',
      ].join('\n')
    );
  } catch (error) {
    console.error('Error handling /start:', error);
    await sendHtml(msg.chat.id, '⚠️ Sorry — hubo un error registrándote. Please try again in a moment.');
  }
}

async function handleHelp(msg) {
  try {
    await sendHtml(
      msg.chat.id,
      [
        '📘 <b>Help / Ayuda</b>',
        '',
        'This bot sends market news alerts automatically y también te deja consultar eventos rápidos.',
        '',
        '<b>Available commands:</b>',
        '• <code>/start</code> — Register / registrarte para recibir alertas',
        '• <code>/help</code> — Show this help message',
        '• <code>/status</code> — Check if your alerts are active',
        '• <code>/today</code> — Show today\'s market events',
        '• <code>/next</code> — Show the next upcoming event',
      ].join('\n')
    );
  } catch (error) {
    console.error('Error handling /help:', error);
    await sendHtml(msg.chat.id, '⚠️ Error mostrando ayuda. Try again in a moment.');
  }
}

async function handleStatus(msg) {
  try {
    const user = getUserStmt.get(msg.from.id);

    if (!user) {
      await sendHtml(
        msg.chat.id,
        'ℹ️ You are not registered yet. Usa <code>/start</code> primero para activar tus alertas.'
      );
      return;
    }

    const isActive = Number(user.active) === 1;
    const subscribedAll = Number(user.subscribed_all) === 1;

    await sendHtml(
      msg.chat.id,
      [
        '📡 <b>Your alert status</b>',
        '',
        `👤 User: <b>${escapeHtml(user.first_name || user.username || String(user.telegram_user_id))}</b>`,
        `✅ Active: <b>${isActive ? 'Yes / Sí' : 'No'}</b>`,
        `🔔 Receiving alerts: <b>${isActive && subscribedAll ? 'Yes / Sí' : 'Limited or No'}</b>`,
        `🆔 Chat ID: <code>${escapeHtml(String(user.chat_id))}</code>`,
      ].join('\n')
    );
  } catch (error) {
    console.error('Error handling /status:', error);
    await sendHtml(msg.chat.id, '⚠️ Could not fetch your status ahora mismo.');
  }
}

async function handleToday(msg) {
  try {
    const rows = getTodayEventsStmt.all().filter((event) => eventMatchesTodayNy(event.event_time_utc));

    if (!rows.length) {
      await sendHtml(msg.chat.id, 'No hay eventos hoy.');
      return;
    }

    const message = [
      '🗓️ <b>Eventos de hoy / Today\'s events</b>',
      '',
      ...rows.map((event, index) => formatEventLine(event, index + 1)).flatMap((line) => [line, '']),
    ];

    if (message[message.length - 1] === '') {
      message.pop();
    }

    await sendHtml(msg.chat.id, message.join('\n'));
  } catch (error) {
    console.error('Error handling /today:', error);
    await sendHtml(msg.chat.id, '⚠️ Error loading today\'s events. Intenta otra vez luego.');
  }
}

async function handleNext(msg) {
  try {
    const firstEvent = getNextEventStmt.get();

    if (!firstEvent) {
      await sendHtml(msg.chat.id, '📭 No upcoming events right now. No hay próximos eventos por ahora.');
      return;
    }

    // Get the NY date of the next event, then pull ALL events on that same day
    const nextDateNy = firstEvent.event_time_ny
      ? firstEvent.event_time_ny.slice(0, 10)
      : formatDateKeyInTimeZone(new Date(firstEvent.event_time_utc), NY_TZ);

    const dayEvents = getNextDayEventsStmt.all(nextDateNy);

    // Filter to only future events on that day
    const now = Date.now();
    const events = dayEvents.filter((e) => new Date(e.event_time_utc).getTime() > now);

    if (events.length === 0) {
      // Fallback: shouldn't happen, but just show the single event
      events.push(firstEvent);
    }

    if (events.length === 1) {
      // Single event — keep the original compact format
      const event = events[0];
      const remaining = formatTimeRemaining(event.event_time_utc);
      const text = [
        '⏭️ <b>Next upcoming event</b>',
        '',
        `<b>${escapeHtml(event.event_name)}</b>`,
        `📈 ${escapeHtml(event.instrument)} • ${escapeHtml(event.market)}`,
        `🕒 ${escapeHtml(formatEventTime(event.event_time_utc))} (${escapeHtml(config.TZ || NY_TZ)})`,
        `⏳ Time remaining: <b>${escapeHtml(remaining)}</b>`,
      ];

      if (event.reference_month) {
        text.push(`🗓️ Ref: ${escapeHtml(event.reference_month)}`);
      }

      if (event.notes) {
        text.push(`📝 ${escapeHtml(event.notes)}`);
      }

      await sendHtml(msg.chat.id, text.join('\n'));
    } else {
      // Multiple events on the same day
      const text = [
        `⏭️ <b>Next events — ${escapeHtml(formatEventTime(events[0].event_time_utc).split(',')[0].trim())}, ${escapeHtml(nextDateNy)}</b>`,
        `📅 <b>${events.length} events this day</b>`,
        '',
      ];

      events.forEach((event, index) => {
        const remaining = formatTimeRemaining(event.event_time_utc);
        text.push(formatEventLine(event, index + 1));
        text.push(`⏳ In: <b>${escapeHtml(remaining)}</b>`);
        text.push('');
      });

      if (text[text.length - 1] === '') {
        text.pop();
      }

      await sendHtml(msg.chat.id, text.join('\n'));
    }
  } catch (error) {
    console.error('Error handling /next:', error);
    await sendHtml(msg.chat.id, '⚠️ Could not load the next event. Intenta luego, por favor.');
  }
}

bot.onText(/^\/start(?:\s|$)/, (msg) => {
  void handleStart(msg);
});

bot.onText(/^\/help(?:\s|$)/, (msg) => {
  void handleHelp(msg);
});

bot.onText(/^\/status(?:\s|$)/, (msg) => {
  void handleStatus(msg);
});

bot.onText(/^\/today(?:\s|$)/, (msg) => {
  void handleToday(msg);
});

bot.onText(/^\/next(?:\s|$)/, (msg) => {
  void handleNext(msg);
});

bot.on('polling_error', (error) => {
  console.error('Telegram polling error:', error);
});

bot.on('message', (msg) => {
  if (!msg.text || !msg.text.startsWith('/')) {
    return;
  }

  const knownCommands = ['/start', '/help', '/status', '/today', '/next'];
  const command = msg.text.split(/\s+/)[0].split('@')[0];

  if (!knownCommands.includes(command)) {
    void sendHtml(
      msg.chat.id,
      '🤖 Command not recognized. Usa <code>/help</code> para ver los comandos disponibles.'
    ).catch((error) => {
      console.error('Error sending unknown command message:', error);
    });
  }
});

console.log(`Telegram bot started in polling mode. TZ=${config.TZ || NY_TZ}`);

module.exports = bot;
