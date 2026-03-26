#!/usr/bin/env node

const { initDb } = require('/opt/newsbot/app/db');
const { toNewYorkISO, scheduleAtJob, cancelAtJob } = require('/opt/newsbot/app/utils');
const config = require('/opt/newsbot/app/config');

function parseArgs(argv) {
  const args = {};

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--event-id') {
      args.eventId = Number(argv[i + 1]);
      i += 1;
    } else if (arg === '--new-time') {
      args.newTime = argv[i + 1];
      i += 1;
    }
  }

  return args;
}

async function main() {
  const { eventId, newTime } = parseArgs(process.argv.slice(2));

  if (!Number.isInteger(eventId) || eventId <= 0) {
    throw new Error('Usage: node scripts/reschedule_event.js --event-id <id> --new-time "2026-04-04T08:30:00-04:00"');
  }

  if (!newTime) {
    throw new Error('Missing required --new-time argument');
  }

  const parsedDate = new Date(newTime);
  if (Number.isNaN(parsedDate.getTime())) {
    throw new Error(`Invalid --new-time value: ${newTime}`);
  }

  const db = initDb();
  const now = new Date();
  const newEventTimeUtc = parsedDate.toISOString();
  const newEventTimeNy = newTime;

  const getEvent = db.prepare(`
    SELECT id, instrument, market, event_name, event_time_ny, event_time_utc
    FROM events
    WHERE id = ?
    LIMIT 1
  `);

  const event = getEvent.get(eventId);
  if (!event) {
    throw new Error(`Event ${eventId} not found`);
  }

  const pendingJobs = db.prepare(`
    SELECT id, template_name, trigger_time_utc, scheduler_job_ref, status
    FROM scheduled_jobs
    WHERE event_id = ?
      AND status IN ('pending', 'scheduled')
    ORDER BY trigger_time_utc ASC, id ASC
  `).all(eventId);

  const cancelJobStmt = db.prepare(`
    UPDATE scheduled_jobs
    SET status = 'cancelled',
        last_error = ?,
        updated_at = datetime('now')
    WHERE id = ?
  `);

  const updateEventStmt = db.prepare(`
    UPDATE events
    SET event_time_ny = ?,
        event_time_utc = ?,
        updated_at = datetime('now')
    WHERE id = ?
  `);

  const insertJobStmt = db.prepare(`
    INSERT INTO scheduled_jobs (
      event_id,
      template_name,
      trigger_time_utc,
      trigger_time_ny,
      status,
      last_error
    ) VALUES (?, ?, ?, ?, ?, ?)
  `);

  const markScheduledStmt = db.prepare(`
    UPDATE scheduled_jobs
    SET scheduler_job_ref = ?,
        status = 'scheduled',
        last_error = NULL,
        updated_at = datetime('now')
    WHERE id = ?
  `);

  const markFailedStmt = db.prepare(`
    UPDATE scheduled_jobs
    SET status = 'failed',
        last_error = ?,
        updated_at = datetime('now')
    WHERE id = ?
  `);

  let cancelled = 0;
  let cancelErrors = 0;

  for (const job of pendingJobs) {
    let cancelNote = 'Cancelled due to event reschedule.';

    if (job.scheduler_job_ref) {
      const cancelledAt = await cancelAtJob(job.scheduler_job_ref);
      if (!cancelledAt.success) {
        cancelErrors += 1;
        cancelNote = `Reschedule requested; atrm may have failed for at job ${job.scheduler_job_ref}: ${cancelledAt.error}`;
      }
    }

    cancelJobStmt.run(cancelNote, job.id);
    cancelled += 1;
  }

  updateEventStmt.run(newEventTimeNy, newEventTimeUtc, eventId);

  let created = 0;
  let scheduled = 0;
  let failed = 0;

  for (const offset of config.ALERT_OFFSETS) {
    const triggerMs = parsedDate.getTime() - (offset.minutes * 60 * 1000);
    const triggerDate = new Date(triggerMs);
    const triggerTimeUtc = triggerDate.toISOString();
    const triggerTimeNy = toNewYorkISO(triggerTimeUtc);

    const insertResult = insertJobStmt.run(
      eventId,
      offset.name,
      triggerTimeUtc,
      triggerTimeNy,
      'pending',
      null
    );

    const jobId = insertResult.lastInsertRowid;
    created += 1;

    if (triggerDate.getTime() <= now.getTime()) {
      markFailedStmt.run('Trigger time is already in the past after reschedule; at job not created.', jobId);
      failed += 1;
      continue;
    }

    const command = `node /opt/newsbot/app/send_alert.js --job-id ${jobId}`;

    try {
      const atJob = await scheduleAtJob(command, triggerTimeUtc);
      if (!atJob || !atJob.jobNumber) {
        markFailedStmt.run(`Unable to parse at job number. Raw output: ${atJob?.raw || 'no output'}`, jobId);
        failed += 1;
        continue;
      }

      markScheduledStmt.run(atJob.jobNumber, jobId);
      scheduled += 1;
    } catch (err) {
      markFailedStmt.run(err.message || String(err), jobId);
      failed += 1;
    }
  }

  console.log('reschedule_event summary');
  console.log(`Event ID: ${eventId}`);
  console.log(`Event: ${event.instrument} / ${event.market} / ${event.event_name}`);
  console.log(`Old time (NY): ${event.event_time_ny}`);
  console.log(`Old time (UTC): ${event.event_time_utc}`);
  console.log(`New time (NY): ${newEventTimeNy}`);
  console.log(`New time (UTC): ${newEventTimeUtc}`);
  console.log(`Cancelled existing jobs: ${cancelled}`);
  console.log(`Cancellation issues: ${cancelErrors}`);
  console.log(`New jobs created: ${created}`);
  console.log(`New jobs scheduled: ${scheduled}`);
  console.log(`New jobs failed/past: ${failed}`);
}

main().catch((err) => {
  console.error('reschedule_event fatal error:', err);
  process.exit(1);
});
