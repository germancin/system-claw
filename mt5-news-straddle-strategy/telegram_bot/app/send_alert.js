const TelegramBot = require('node-telegram-bot-api');
const { initDb } = require('./db');
const config = require('./config');
const { toNewYorkDisplay, sleep } = require('./utils');

function parseJobId(argv) {
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--job-id') {
      return Number(argv[i + 1]);
    }
    if (arg.startsWith('--job-id=')) {
      return Number(arg.split('=')[1]);
    }
  }
  return null;
}

function getTemplateLabel(templateName) {
  const match = config.ALERT_OFFSETS.find((item) => item.name === templateName);
  return match ? match.label : templateName;
}

function buildMessage(job) {
  const formattedTime = toNewYorkDisplay(job.event_time_ny || job.event_time_utc);
  const label = getTemplateLabel(job.template_name);

  return [
    '🔔 <b>Market Event Alert</b>',
    '',
    `<b>Instrument:</b> ${escapeHtml(job.instrument)}`,
    `<b>Market:</b> ${escapeHtml(job.market)}`,
    `<b>Event:</b> ${escapeHtml(job.event_name)}`,
    `<b>Time (New York):</b> ${escapeHtml(formattedTime)}`,
    '',
    `⏰ <b>${escapeHtml(label)} before</b>`,
    '',
    'Prepárate para abrir el bot y desplegar la estrategia.',
  ].join('\n');
}

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

async function sendWithRetry(bot, chatId, message) {
  const backoffs = [2000, 4000];
  let lastError = null;

  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const response = await bot.sendMessage(chatId, message, { parse_mode: 'HTML' });
      return { success: true, attempt, response };
    } catch (err) {
      lastError = err;
      console.error(`Send attempt ${attempt} failed for chat_id=${chatId}:`, err.message);
      if (attempt < 3) {
        const waitMs = backoffs[attempt - 1];
        console.log(`Retrying chat_id=${chatId} in ${waitMs}ms...`);
        await sleep(waitMs);
      }
    }
  }

  return { success: false, attempt: 3, error: lastError };
}

async function main() {
  const jobId = parseJobId(process.argv.slice(2));

  if (!Number.isInteger(jobId) || jobId <= 0) {
    console.error('Missing or invalid --job-id');
    process.exitCode = 1;
    return;
  }

  if (!config.TELEGRAM_BOT_TOKEN) {
    console.error('TELEGRAM_BOT_TOKEN is not configured');
    process.exitCode = 1;
    return;
  }

  const db = initDb();
  const failJob = db.prepare(`
    UPDATE scheduled_jobs
    SET status = 'failed', last_error = ?, updated_at = datetime('now')
    WHERE id = ?
  `);

  const loadJob = db.prepare(`
    SELECT
      sj.id,
      sj.event_id,
      sj.template_name,
      sj.trigger_time_utc,
      sj.trigger_time_ny,
      sj.status,
      sj.retry_count,
      sj.last_error,
      e.instrument,
      e.market,
      e.event_name,
      e.event_time_ny,
      e.event_time_utc
    FROM scheduled_jobs sj
    INNER JOIN events e ON e.id = sj.event_id
    WHERE sj.id = ?
  `);

  const job = loadJob.get(jobId);

  if (!job) {
    console.error(`Scheduled job not found: ${jobId}`);
    process.exitCode = 1;
    return;
  }

  if (job.status === 'sent' || job.status === 'cancelled') {
    return;
  }

  console.log(`Starting alert job ${jobId} with current status=${job.status}`);

  try {
    const markProcessing = db.prepare(`
      UPDATE scheduled_jobs
      SET status = 'processing', last_error = NULL, updated_at = datetime('now')
      WHERE id = ?
    `);

    markProcessing.run(jobId);

    const message = buildMessage(job);
    const bot = new TelegramBot(config.TELEGRAM_BOT_TOKEN);

    const users = db.prepare(`
      SELECT id, telegram_user_id, chat_id, username, first_name
      FROM users
      WHERE active = 1 AND subscribed_all = 1
      ORDER BY id ASC
    `).all();

    console.log(`Loaded ${users.length} active subscribed user(s) for job ${jobId}`);

    const findDelivery = db.prepare(`
    SELECT id
    FROM job_deliveries
    WHERE job_id = ? AND user_id = ?
    ORDER BY id DESC
    LIMIT 1
  `);

    const insertDelivery = db.prepare(`
      INSERT INTO job_deliveries (
        job_id,
        user_id,
        delivery_status,
        telegram_message_id,
        retry_count,
        last_error,
        sent_at,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
    `);

    const updateDelivery = db.prepare(`
      UPDATE job_deliveries
      SET
        delivery_status = ?,
        telegram_message_id = ?,
        retry_count = ?,
        last_error = ?,
        sent_at = ?,
        updated_at = datetime('now')
      WHERE id = ?
    `);

    function saveDelivery(jobIdValue, userIdValue, deliveryStatus, telegramMessageId, retryCount, errorText, sentAt) {
      const existing = findDelivery.get(jobIdValue, userIdValue);
      if (existing) {
        updateDelivery.run(deliveryStatus, telegramMessageId, retryCount, errorText, sentAt, existing.id);
        return;
      }

      insertDelivery.run(
        jobIdValue,
        userIdValue,
        deliveryStatus,
        telegramMessageId,
        retryCount,
        errorText,
        sentAt
      );
    }

    const finaliseJob = db.prepare(`
      UPDATE scheduled_jobs
      SET status = ?, last_error = ?, updated_at = datetime('now')
      WHERE id = ?
    `);

    let successCount = 0;
    let failureCount = 0;
    const failures = [];

    for (const user of users) {
      console.log(`Sending job ${jobId} to user_id=${user.id}, chat_id=${user.chat_id}`);
      const result = await sendWithRetry(bot, user.chat_id, message);

      if (result.success) {
        successCount += 1;
        console.log(
          `Delivered job ${jobId} to user_id=${user.id}, chat_id=${user.chat_id}, telegram_message_id=${result.response.message_id}, attempts=${result.attempt}`
        );
        saveDelivery(
          jobId,
          user.id,
          'sent',
          result.response.message_id,
          result.attempt - 1,
          null,
          new Date().toISOString()
        );
      } else {
        failureCount += 1;
        const errorMessage = result.error?.message || 'Unknown Telegram send error';
        failures.push(`user ${user.id}: ${errorMessage}`);
        console.error(`Failed delivery for user_id=${user.id}, chat_id=${user.chat_id}: ${errorMessage}`);
        saveDelivery(
          jobId,
          user.id,
          'failed',
          null,
          result.attempt - 1,
          errorMessage,
          null
        );
      }
    }

    let finalStatus = 'failed';
    if (users.length === 0) {
      finalStatus = 'failed';
      failures.push('No active subscribed users found');
    } else if (successCount === users.length) {
      finalStatus = 'sent';
    } else if (successCount > 0) {
      finalStatus = 'partial';
    }

    const lastError = failures.length ? failures.join(' | ').slice(0, 2000) : null;
    finaliseJob.run(finalStatus, lastError, jobId);

    console.log(
      `Completed job ${jobId}: status=${finalStatus}, success=${successCount}, failed=${failureCount}, total=${users.length}`
    );

    if (lastError) {
      console.error(`Job ${jobId} errors: ${lastError}`);
    }
  } catch (err) {
    const errorMessage = err?.message || String(err);
    console.error(`Fatal error while processing job ${jobId}:`, err);
    failJob.run(errorMessage.slice(0, 2000), jobId);
    throw err;
  }
}

main()
  .catch((err) => {
    console.error('Unhandled send_alert error:', err);
    process.exitCode = 1;
  })
  .finally(() => {
    process.exit();
  });
