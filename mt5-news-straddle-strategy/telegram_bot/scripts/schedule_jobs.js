#!/usr/bin/env node

const path = require('path');
const { initDb } = require('/opt/newsbot/app/db');
const { toNewYorkISO, scheduleAtJob } = require('/opt/newsbot/app/utils');
const config = require('/opt/newsbot/app/config');

async function main() {
  const db = initDb();

  const now = new Date();
  const nowIso = now.toISOString();

  const events = db.prepare(`
    SELECT id, instrument, market, event_name, event_time_utc, active
    FROM events
    WHERE active = 1
    ORDER BY event_time_utc ASC, id ASC
  `).all();

  const templates = db.prepare(`
    SELECT id, name, offset_minutes, label, active
    FROM alert_templates
    WHERE active = 1
    ORDER BY offset_minutes DESC, id ASC
  `).all();

  const findExisting = db.prepare(`
    SELECT id, status, scheduler_job_ref
    FROM scheduled_jobs
    WHERE event_id = ? AND template_name = ?
    LIMIT 1
  `);

  const insertScheduledJob = db.prepare(`
    INSERT INTO scheduled_jobs (
      event_id,
      template_name,
      trigger_time_utc,
      trigger_time_ny,
      status
    ) VALUES (?, ?, ?, ?, 'pending')
  `);

  const markScheduled = db.prepare(`
    UPDATE scheduled_jobs
    SET scheduler_job_ref = ?,
        status = 'scheduled',
        updated_at = datetime('now')
    WHERE id = ?
  `);

  const markFailed = db.prepare(`
    UPDATE scheduled_jobs
    SET status = 'failed',
        last_error = ?,
        updated_at = datetime('now')
    WHERE id = ?
  `);

  let created = 0;
  let skippedPast = 0;
  let skippedExisting = 0;
  let failed = 0;

  for (const event of events) {
    const eventTime = new Date(event.event_time_utc);
    if (Number.isNaN(eventTime.getTime())) {
      console.warn(`Skipping event ${event.id}: invalid event_time_utc (${event.event_time_utc})`);
      continue;
    }

    for (const template of templates) {
      const existing = findExisting.get(event.id, template.name);
      if (existing) {
        skippedExisting += 1;
        continue;
      }

      const triggerMs = eventTime.getTime() - (template.offset_minutes * 60 * 1000);
      const triggerDate = new Date(triggerMs);

      if (triggerDate.getTime() <= now.getTime()) {
        skippedPast += 1;
        continue;
      }

      const triggerTimeUtc = triggerDate.toISOString();
      const triggerTimeNy = toNewYorkISO(triggerTimeUtc);

      const insertResult = insertScheduledJob.run(
        event.id,
        template.name,
        triggerTimeUtc,
        triggerTimeNy
      );

      const jobId = insertResult.lastInsertRowid;
      const command = `node /opt/newsbot/app/send_alert.js --job-id ${jobId}`;

      try {
        const scheduled = await scheduleAtJob(command, triggerTimeUtc);

        if (!scheduled || !scheduled.jobNumber) {
          failed += 1;
          markFailed.run(
            `Unable to parse at job number. Raw output: ${scheduled?.raw || 'no output'}`,
            jobId
          );
          console.error(
            `Failed to schedule job ${jobId} for event ${event.id} (${template.name}): no at job number returned.`
          );
          continue;
        }

        markScheduled.run(scheduled.jobNumber, jobId);
        created += 1;
      } catch (err) {
        failed += 1;
        markFailed.run(err.message || String(err), jobId);
        console.error(
          `Failed to schedule job ${jobId} for event ${event.id} (${template.name}): ${err.message || err}`
        );
      }
    }
  }

  console.log(`schedule_jobs complete (${path.basename(config.DATABASE_PATH)})`);
  console.log(`Jobs created: ${created}`);
  console.log(`Skipped (past): ${skippedPast}`);
  console.log(`Skipped (existing): ${skippedExisting}`);
  if (failed > 0) {
    console.log(`Failed to schedule: ${failed}`);
  }
}

main().catch((err) => {
  console.error('schedule_jobs fatal error:', err);
  process.exit(1);
});
