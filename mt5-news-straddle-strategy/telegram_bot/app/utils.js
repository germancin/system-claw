const { exec } = require('child_process');
const util = require('util');
const execPromise = util.promisify(exec);

/**
 * Convert an ISO datetime string to a NY-local display string.
 */
function toNewYorkDisplay(isoString) {
  const d = new Date(isoString);
  return d.toLocaleString('en-US', {
    timeZone: 'America/New_York',
    weekday: 'long',
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: true,
  });
}

/**
 * Convert an ISO datetime string to NY time as YYYY-MM-DD HH:MM
 */
function toNewYorkISO(isoString) {
  const d = new Date(isoString);
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/New_York',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(d);
  
  const get = (type) => parts.find(p => p.type === type)?.value || '';
  return `${get('year')}-${get('month')}-${get('day')} ${get('hour')}:${get('minute')}`;
}

/**
 * Schedule an `at` job. Returns the at job number.
 */
async function scheduleAtJob(command, triggerTimeUTC) {
  const d = new Date(triggerTimeUTC);
  // at format: HH:MM YYYY-MM-DD (in UTC)
  const hours = String(d.getUTCHours()).padStart(2, '0');
  const minutes = String(d.getUTCMinutes()).padStart(2, '0');
  const year = d.getUTCFullYear();
  const month = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  const atTime = `${hours}:${minutes} ${year}-${month}-${day}`;

  const fullCommand = `${command} >> /opt/newsbot/logs/alerts.log 2>&1`;
  const atCmd = `echo "${fullCommand}" | TZ=UTC at ${atTime} 2>&1`;

  const { stdout, stderr } = await execPromise(atCmd);
  const output = (stderr || '') + (stdout || '');

  const match = output.match(/job\s+(\d+)/);
  const jobNumber = match ? parseInt(match[1]) : null;

  return { jobNumber, raw: output.trim() };
}

/**
 * Cancel an `at` job by its job number.
 */
async function cancelAtJob(jobNumber) {
  try {
    await execPromise(`atrm ${jobNumber}`);
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
}

/**
 * List pending `at` jobs.
 */
async function listAtJobs() {
  const { stdout } = await execPromise('atq');
  if (!stdout.trim()) return [];
  return stdout.trim().split('\n').map(line => {
    const parts = line.trim().split(/\s+/);
    return {
      jobNumber: parseInt(parts[0]),
      raw: line.trim(),
    };
  });
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

module.exports = {
  toNewYorkDisplay,
  toNewYorkISO,
  scheduleAtJob,
  cancelAtJob,
  listAtJobs,
  sleep,
  execPromise,
};
