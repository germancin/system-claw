#!/usr/bin/env node

const TelegramBot = require('node-telegram-bot-api');
const { initDb } = require('/opt/newsbot/app/db');
const config = require('/opt/newsbot/app/config');

function buildAlertMessage(job) {
  const eventTime = job.event_time_ny || job.event_time_utc;
  const parts = [
    `📣 Market News Alert (${job.template_label || job.template_name})`,
    '',
    `Instrument: ${job.instrument}`,
    `Market: ${job.market}`,
    `Event: ${job.event_name}`,
    `Reference Month: ${job.reference_month || 'N/A'}`,
    `Event Time (NY): ${eventTime}`,
  ];

  if (job.day_name_ny) {
    parts.push(`Day: ${job.day_name_ny}`);
  }

  if (job.notes) {
    parts.push(`Notes: ${job.notes}`);
  }

  if (job.source_url) {
    parts.push(`Source: ${job.source_url}`);
  }

  return parts.join('\n');
}

async function main() {
  if (!config.TELEGRAM_BOT_TOKEN) {
    throw new Error('Missing TELEGRAM_BOT_TOKEN in config');
  }

  const db = initDb();
  const bot = new TelegramBot(config.TELEGRAM_BOT_TOKEN);

  const jobs = db.prepare(`
    SELECT
      sj.id,
      sj.event_id,
      sj.template_name,
      sj.trigger_time_utc,
      sj.status,
      sj.retry_count,
      e.instrument,
      e.market,
      e.event_name,
      e.reference_month,
      e.event_time_ny,
      e.event_time_utc,
      e.day_name_ny,
      e.notes,
      e.source_url,
      at.label AS template_label
    FROM scheduled_jobs sj
    JOIN events e ON e.id = sj.event_id
    LEFT JOIN alert_templates at ON at.name = sj.template_name
    WHERE sj.status IN ('partial', 'failed')
      AND datetime(sj.trigger_time_utc) <= datetime('now')
    ORDER BY sj.trigger_time_utc ASC, sj.id ASC
  `).all();

  const failedDeliveriesStmt = db.prepare(`
    SELECT
      jd.id,
      jd.user_id,
      jd.retry_count,
      u.chat_id,
      u.username,
      u.first_name,
      u.active
    FROM job_deliveries jd
    JOIN users u ON u.id = jd.user_id
    WHERE jd.job_id = ?
      AND jd.delivery_status = 'failed'
      AND jd.retry_count < 2
      AND u.active = 1
    ORDER BY jd.id ASC
  `);

  const markDeliverySent = db.prepare(`
    UPDATE job_deliveries
    SET delivery_status = 'sent',
        telegram_message_id = ?,
        retry_count = retry_count + 1,
        last_error = NULL,
        sent_at = datetime('now'),
        updated_at = datetime('now')
    WHERE id = ?
  `);

  const markDeliveryFailed = db.prepare(`
    UPDATE job_deliveries
    SET delivery_status = 'failed',
        retry_count = retry_count + 1,
        last_error = ?,
        updated_at = datetime('now')
    WHERE id = ?
  `);

  const getDeliveryCounts = db.prepare(`
    SELECT
      SUM(CASE WHEN delivery_status = 'sent' THEN 1 ELSE 0 END) AS sent_count,
      SUM(CASE WHEN delivery_status = 'failed' THEN 1 ELSE 0 END) AS failed_count,
      SUM(CASE WHEN delivery_status = 'pending' THEN 1 ELSE 0 END) AS pending_count,
      COUNT(*) AS total_count
    FROM job_deliveries
    WHERE job_id = ?
  `);

  const updateJobStatus = db.prepare(`
    UPDATE scheduled_jobs
    SET status = ?,
        retry_count = retry_count + 1,
        last_error = ?,
        updated_at = datetime('now')
    WHERE id = ?
  `);

  let jobsScanned = 0;
  let jobsUpdated = 0;
  let deliveriesRetried = 0;
  let deliveriesRecovered = 0;
  let deliveriesStillFailed = 0;

  for (const job of jobs) {
    jobsScanned += 1;
    const deliveries = failedDeliveriesStmt.all(job.id);

    if (deliveries.length === 0) {
      const counts = getDeliveryCounts.get(job.id);
      let newStatus = 'failed';
      let lastError = job.status === 'failed' ? 'No retry-eligible failed deliveries remain.' : null;

      if (counts && counts.total_count > 0 && counts.sent_count === counts.total_count) {
        newStatus = 'sent';
        lastError = null;
      } else if (counts && counts.sent_count > 0) {
        newStatus = 'partial';
      }

      updateJobStatus.run(newStatus, lastError, job.id);
      jobsUpdated += 1;
      continue;
    }

    const message = buildAlertMessage(job);

    for (const delivery of deliveries) {
      deliveriesRetried += 1;

      try {
        const sent = await bot.sendMessage(delivery.chat_id, message, {
          disable_web_page_preview: true,
        });

        markDeliverySent.run(sent.message_id || null, delivery.id);
        deliveriesRecovered += 1;
        console.log(`Resent job ${job.id} to user ${delivery.user_id} (delivery ${delivery.id})`);
      } catch (err) {
        const errorMessage = err && err.message ? err.message : String(err);
        markDeliveryFailed.run(errorMessage, delivery.id);
        deliveriesStillFailed += 1;
        console.error(`Retry failed for job ${job.id}, delivery ${delivery.id}, user ${delivery.user_id}: ${errorMessage}`);
      }
    }

    const counts = getDeliveryCounts.get(job.id);
    let newStatus = 'failed';
    let lastError = counts.failed_count > 0 ? 'One or more deliveries still failed after rescue retry.' : null;

    if (counts.total_count > 0 && counts.sent_count === counts.total_count) {
      newStatus = 'sent';
      lastError = null;
    } else if (counts.sent_count > 0) {
      newStatus = 'partial';
    }

    updateJobStatus.run(newStatus, lastError, job.id);
    jobsUpdated += 1;
  }

  console.log('rescue_failed summary');
  console.log(`Jobs scanned: ${jobsScanned}`);
  console.log(`Jobs updated: ${jobsUpdated}`);
  console.log(`Deliveries retried: ${deliveriesRetried}`);
  console.log(`Deliveries recovered: ${deliveriesRecovered}`);
  console.log(`Deliveries still failed: ${deliveriesStillFailed}`);
}

main().catch((err) => {
  console.error('rescue_failed fatal error:', err);
  process.exit(1);
});
