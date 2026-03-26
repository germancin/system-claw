const fs = require('fs');
const path = require('path');
const { initDb } = require('../app/db');

const CSV_PATH = '/opt/newsbot/data/market_news_calendar_mar_dec_2026.csv';

function stripBom(text) {
  return text.charCodeAt(0) === 0xFEFF ? text.slice(1) : text;
}

function parseCsvLine(line) {
  const fields = [];
  let current = '';
  let inQuotes = false;

  for (let i = 0; i < line.length; i += 1) {
    const char = line[i];
    const next = line[i + 1];

    if (char === '"') {
      if (inQuotes && next === '"') {
        current += '"';
        i += 1;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }

    if (char === ',' && !inQuotes) {
      fields.push(current);
      current = '';
      continue;
    }

    current += char;
  }

  fields.push(current);
  return fields;
}

function parseCsv(content) {
  const clean = stripBom(content).replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  const rawLines = clean.split('\n').filter((line) => line.trim() !== '');

  if (rawLines.length === 0) {
    return [];
  }

  const headers = parseCsvLine(rawLines[0]).map((h) => h.trim());
  const rows = [];

  for (let i = 1; i < rawLines.length; i += 1) {
    const values = parseCsvLine(rawLines[i]);
    const row = {};

    headers.forEach((header, index) => {
      row[header] = (values[index] || '').trim();
    });

    rows.push(row);
  }

  return rows;
}

function formatNyDateTime(isoString) {
  const match = isoString.match(/^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})(?::\d{2})?([+-]\d{2}:\d{2})$/);
  if (match) {
    const [, datePart, timePart, offset] = match;
    const tzLabel = offset === '-05:00' || offset === '-04:00' ? 'ET' : offset;
    return `${datePart} ${timePart} ${tzLabel}`;
  }

  const date = new Date(isoString);
  if (Number.isNaN(date.getTime())) {
    throw new Error(`Invalid New York datetime: ${isoString}`);
  }

  return isoString;
}

function toUtcIsoString(isoString) {
  const date = new Date(isoString);
  if (Number.isNaN(date.getTime())) {
    throw new Error(`Invalid datetime for UTC conversion: ${isoString}`);
  }
  return date.toISOString();
}

function main() {
  const csvText = fs.readFileSync(CSV_PATH, 'utf8');
  const rows = parseCsv(csvText);
  const db = initDb();

  const insertEvent = db.prepare(`
    INSERT OR IGNORE INTO events (
      instrument,
      market,
      event_name,
      reference_month,
      event_time_ny,
      event_time_utc,
      day_name_ny,
      source_status,
      notes,
      source_url,
      event_key
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  let inserted = 0;
  let ignored = 0;
  let failed = 0;

  const transaction = db.transaction((items) => {
    for (const row of items) {
      try {
        const instrument = row.instrumento;
        const market = row.mercado;
        const eventName = row.noticia_mensual_clave;
        const referenceMonth = row.mes_referencia;
        const sourceIso = row.fecha_hora_nueva_york_iso;
        const eventTimeNy = formatNyDateTime(sourceIso);
        const eventTimeUtc = toUtcIsoString(sourceIso);
        const dayNameNy = row.dia_semana_nueva_york;
        const sourceStatus = row.estado_fuente;
        const notes = row.aclaraciones;
        const sourceUrl = row.fuente_url;
        const eventKey = `${instrument}|${eventName}|${sourceIso}`;

        const result = insertEvent.run(
          instrument,
          market,
          eventName,
          referenceMonth,
          eventTimeNy,
          eventTimeUtc,
          dayNameNy,
          sourceStatus,
          notes,
          sourceUrl,
          eventKey
        );

        if (result.changes > 0) {
          inserted += 1;
        } else {
          ignored += 1;
        }
      } catch (error) {
        failed += 1;
        console.error(`Failed to import row for ${row.instrumento || 'unknown'} / ${row.noticia_mensual_clave || 'unknown'}: ${error.message}`);
      }
    }
  });

  transaction(rows);

  const totalInDb = db.prepare('SELECT COUNT(*) AS count FROM events').get().count;

  console.log('Import complete.');
  console.log(`CSV file: ${path.basename(CSV_PATH)}`);
  console.log(`Rows parsed: ${rows.length}`);
  console.log(`Inserted: ${inserted}`);
  console.log(`Ignored (duplicates): ${ignored}`);
  console.log(`Failed: ${failed}`);
  console.log(`Total events in DB: ${totalInDb}`);
}

try {
  main();
} catch (error) {
  console.error('Import failed:', error.message);
  process.exit(1);
}
