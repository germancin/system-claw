#!/usr/bin/env node
/**
 * getFuturesPrice
 * Fetch a futures quote from Stooq's public CSV endpoint (no API key).
 * Usage:
 *   node scripts/getFuturesPrice.mjs NQ
 *   node scripts/getFuturesPrice.mjs ES
 */

const input = (process.argv[2] || '').trim();
if (!input) {
  console.error('Usage: getFuturesPrice <SYMBOL> (e.g., NQ, ES)');
  process.exit(2);
}

const MAP = {
  // Stooq futures symbols: https://stooq.com/
  NQ: { symbol: 'nq.f', name: 'E-mini NASDAQ 100 Futures' },
  ES: { symbol: 'es.f', name: 'E-mini S&P 500 Futures' },
  YM: { symbol: 'ym.f', name: 'E-mini Dow Futures' },
  RTY: { symbol: 'rty.f', name: 'E-mini Russell 2000 Futures' },
  CL: { symbol: 'cl.f', name: 'Crude Oil Futures' },
  GC: { symbol: 'gc.f', name: 'Gold Futures' },
  SI: { symbol: 'si.f', name: 'Silver Futures' }
};

function resolveSymbol(s) {
  const key = s.toUpperCase();
  if (MAP[key]) return { input: key, ...MAP[key] };
  // allow passing a raw yahoo symbol
  return { input: s, symbol: s, name: null };
}

async function httpJson(url) {
  const res = await fetch(url, {
    headers: {
      'accept': 'application/json',
      'user-agent': 'TradingClaw/getFuturesPrice (OpenClaw)'
    }
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = null; }
  if (!res.ok) {
    const msg = (json && (json.quoteSummary && JSON.stringify(json.quoteSummary))) ? JSON.stringify(json.quoteSummary) : (text || '');
    throw new Error(`HTTP ${res.status}: ${msg}`);
  }
  return json;
}

function parseCsvLine(line) {
  // Very simple CSV (no quoted commas in this endpoint)
  return line.split(',').map(s => s.trim());
}

async function main() {
  const r = resolveSymbol(input);
  const url = `https://stooq.com/q/l/?s=${encodeURIComponent(r.symbol)}&f=sd2t2ohlcv&h&e=csv`;
  const res = await fetch(url, { headers: { 'user-agent': 'TradingClaw/getFuturesPrice (OpenClaw)' } });
  const text = await res.text();
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${text.slice(0, 200)}`);

  const lines = text.trim().split(/\r?\n/);
  if (lines.length < 2) {
    console.log(JSON.stringify({
      ok: false,
      input,
      resolved: { symbol: r.symbol, name: r.name },
      error: { code: 'NOT_FOUND', message: `No data returned for '${input}' (resolved to '${r.symbol}').` },
      ts: new Date().toISOString(),
      source: 'stooq'
    }, null, 2));
    process.exit(1);
  }

  const header = parseCsvLine(lines[0]);
  const row = parseCsvLine(lines[1]);
  const idx = Object.fromEntries(header.map((h, i) => [h.toLowerCase(), i]));

  const close = Number(row[idx['close']]);
  const open = Number(row[idx['open']]);
  const high = Number(row[idx['high']]);
  const low = Number(row[idx['low']]);
  const date = row[idx['date']];
  const time = row[idx['time']];
  const symbol = row[idx['symbol']];

  if (!Number.isFinite(close)) {
    console.log(JSON.stringify({
      ok: false,
      input,
      resolved: { symbol: r.symbol, name: r.name },
      error: { code: 'PARSE_FAILED', message: `Could not parse close price for '${input}'.` },
      ts: new Date().toISOString(),
      source: 'stooq'
    }, null, 2));
    process.exit(1);
  }

  const change = (Number.isFinite(open)) ? (close - open) : null;
  const changePercent = (Number.isFinite(open) && open !== 0) ? ((close - open) / open) * 100 : null;
  const ts = (date && time) ? new Date(`${date}T${time}Z`).toISOString() : new Date().toISOString();

  console.log(JSON.stringify({
    ok: true,
    input,
    resolved: { symbol: r.symbol, name: r.name },
    currency: 'USD',
    price: close,
    ohlc: {
      open: Number.isFinite(open) ? open : null,
      high: Number.isFinite(high) ? high : null,
      low: Number.isFinite(low) ? low : null,
      close
    },
    change,
    changePercent,
    ts,
    raw: { symbol },
    source: 'stooq'
  }, null, 2));
}

main().catch((err) => {
  console.log(JSON.stringify({
    ok: false,
    input,
    error: {
      code: 'FETCH_FAILED',
      message: err?.message || String(err)
    },
    ts: new Date().toISOString(),
    source: 'stooq'
  }, null, 2));
  process.exit(1);
});
