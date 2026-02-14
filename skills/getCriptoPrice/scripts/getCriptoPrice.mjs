#!/usr/bin/env node
/**
 * getCriptoPrice
 * Fetch latest USD spot price for a crypto asset via CoinGecko.
 * Usage:
 *   node scripts/getCriptoPrice.mjs BTC
 *   node scripts/getCriptoPrice.mjs bitcoin
 */

const input = (process.argv[2] || '').trim();
if (!input) {
  console.error('Usage: getCriptoPrice <SYMBOL|coingecko_id> (e.g., BTC or bitcoin)');
  process.exit(2);
}

const COINGECKO = 'https://api.coingecko.com/api/v3';

const SYMBOL_TO_ID = {
  BTC: 'bitcoin',
  ETH: 'ethereum',
  SOL: 'solana',
  BNB: 'binancecoin',
  XRP: 'ripple',
  ADA: 'cardano',
  DOGE: 'dogecoin',
  AVAX: 'avalanche-2',
  DOT: 'polkadot',
  LINK: 'chainlink',
  LTC: 'litecoin',
  BCH: 'bitcoin-cash',
  MATIC: 'polygon-ecosystem-token',
  SHIB: 'shiba-inu',
  TRX: 'tron',
  UNI: 'uniswap',
  ATOM: 'cosmos',
  XLM: 'stellar',
  XMR: 'monero'
};

function toId(s) {
  const upper = s.toUpperCase();
  if (SYMBOL_TO_ID[upper]) return { id: SYMBOL_TO_ID[upper], inputType: 'symbol' };
  // assume it's a coingecko id
  return { id: s.toLowerCase(), inputType: 'id' };
}

async function httpJson(url) {
  const res = await fetch(url, {
    headers: {
      'accept': 'application/json',
      'user-agent': 'TradingClaw/getCriptoPrice (OpenClaw)'
    }
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = null; }
  if (!res.ok) {
    const msg = (json && (json.error || json.message)) ? (json.error || json.message) : text;
    throw new Error(`HTTP ${res.status}: ${msg}`);
  }
  return json;
}

async function main() {
  const { id, inputType } = toId(input);

  // Resolve basic asset info (best-effort). If it fails, we still try price.
  let info = null;
  try {
    info = await httpJson(`${COINGECKO}/coins/${encodeURIComponent(id)}?localization=false&tickers=false&market_data=false&community_data=false&developer_data=false&sparkline=false`);
  } catch {
    // ignore
  }

  const priceJson = await httpJson(`${COINGECKO}/simple/price?ids=${encodeURIComponent(id)}&vs_currencies=usd&include_last_updated_at=true`);
  const priceObj = priceJson?.[id];
  const price = priceObj?.usd;
  const lastUpdatedAt = priceObj?.last_updated_at ? new Date(priceObj.last_updated_at * 1000).toISOString() : new Date().toISOString();

  if (typeof price !== 'number') {
    console.log(JSON.stringify({
      ok: false,
      error: {
        code: 'NOT_FOUND',
        message: `Could not resolve price for input '${input}' (resolved id '${id}'). Try a CoinGecko id like 'bitcoin'.`
      },
      ts: new Date().toISOString(),
      source: 'coingecko'
    }, null, 2));
    process.exit(1);
  }

  console.log(JSON.stringify({
    ok: true,
    asset: {
      input,
      input_type: inputType,
      coingecko_id: id,
      symbol: info?.symbol ?? (inputType === 'symbol' ? input.toLowerCase() : null),
      name: info?.name ?? null
    },
    currency: 'usd',
    price,
    ts: lastUpdatedAt,
    source: 'coingecko'
  }, null, 2));
}

main().catch((err) => {
  console.log(JSON.stringify({
    ok: false,
    error: {
      code: 'FETCH_FAILED',
      message: err?.message || String(err)
    },
    ts: new Date().toISOString(),
    source: 'coingecko'
  }, null, 2));
  process.exit(1);
});
