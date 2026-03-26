const Database = require('better-sqlite3');
const path = require('path');
const config = require('./config');

let _db = null;

function getDb() {
  if (!_db) {
    _db = new Database(config.DATABASE_PATH);
    _db.pragma('journal_mode = WAL');
    _db.pragma('foreign_keys = ON');
  }
  return _db;
}

function initDb() {
  const db = getDb();

  db.exec(`
    CREATE TABLE IF NOT EXISTS events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      instrument TEXT NOT NULL,
      market TEXT NOT NULL,
      event_name TEXT NOT NULL,
      reference_month TEXT,
      event_time_ny TEXT NOT NULL,
      event_time_utc TEXT NOT NULL,
      day_name_ny TEXT,
      source_status TEXT,
      notes TEXT,
      source_url TEXT,
      event_key TEXT UNIQUE NOT NULL,
      active INTEGER DEFAULT 1,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS alert_templates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT UNIQUE NOT NULL,
      offset_minutes INTEGER NOT NULL,
      label TEXT NOT NULL,
      active INTEGER DEFAULT 1
    );

    CREATE TABLE IF NOT EXISTS scheduled_jobs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      event_id INTEGER NOT NULL,
      template_name TEXT NOT NULL,
      trigger_time_utc TEXT NOT NULL,
      trigger_time_ny TEXT NOT NULL,
      status TEXT DEFAULT 'pending' CHECK(status IN ('pending','scheduled','processing','sent','partial','failed','cancelled')),
      scheduler_job_ref INTEGER,
      retry_count INTEGER DEFAULT 0,
      last_error TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (event_id) REFERENCES events(id)
    );

    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      telegram_user_id INTEGER UNIQUE NOT NULL,
      chat_id INTEGER NOT NULL,
      username TEXT,
      first_name TEXT,
      active INTEGER DEFAULT 1,
      subscribed_all INTEGER DEFAULT 1,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS job_deliveries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      job_id INTEGER NOT NULL,
      user_id INTEGER NOT NULL,
      delivery_status TEXT DEFAULT 'pending' CHECK(delivery_status IN ('pending','sent','failed')),
      telegram_message_id INTEGER,
      retry_count INTEGER DEFAULT 0,
      last_error TEXT,
      sent_at TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (job_id) REFERENCES scheduled_jobs(id),
      FOREIGN KEY (user_id) REFERENCES users(id)
    );

    CREATE INDEX IF NOT EXISTS idx_scheduled_jobs_status ON scheduled_jobs(status);
    CREATE INDEX IF NOT EXISTS idx_scheduled_jobs_trigger ON scheduled_jobs(trigger_time_utc);
    CREATE INDEX IF NOT EXISTS idx_scheduled_jobs_event ON scheduled_jobs(event_id);
    CREATE INDEX IF NOT EXISTS idx_job_deliveries_status ON job_deliveries(delivery_status);
    CREATE INDEX IF NOT EXISTS idx_job_deliveries_job ON job_deliveries(job_id);
    CREATE INDEX IF NOT EXISTS idx_users_active ON users(active);
    CREATE INDEX IF NOT EXISTS idx_events_active ON events(active);
    CREATE INDEX IF NOT EXISTS idx_events_time ON events(event_time_utc);
  `);

  // Seed alert templates
  const insert = db.prepare(`
    INSERT OR IGNORE INTO alert_templates (name, offset_minutes, label)
    VALUES (?, ?, ?)
  `);
  for (const t of config.ALERT_OFFSETS) {
    insert.run(t.name, t.minutes, t.label);
  }

  return db;
}

module.exports = { getDb, initDb };
