// Generates the bulk instrument catalogs shipped as assets:
//   assets/data/instruments_us.json.gz    (official NASDAQ Trader symbol directory)
//   assets/data/instruments_intl.json.gz  (curated EU / Asia / Americas + indices)
//
// Downloads the symbol directory itself, so the catalog is reproducible:
//
//   node tool/build_catalog.js
//
// Entries omit anything that can be defaulted at parse time (provider `yahoo`,
// currency `USD`, providerSymbol == symbol) and are gzip-compressed, which takes
// the payload from ~2 MB to ~250 KB.
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const ROOT = path.resolve(__dirname, '..');
const CACHE = path.join(__dirname, '.cache');
const CATALOG_VERSION = 6;

const NASDAQ_LISTED =
  'https://www.nasdaqtrader.com/dynamic/SymDir/nasdaqlisted.txt';
const OTHER_LISTED =
  'https://www.nasdaqtrader.com/dynamic/SymDir/otherlisted.txt';

const EXCLUDE_NAME =
  /warrant|right(s)?\b|preferred|depositary share|notes due|% |unit\b|acquisition corp|blank check/i;
const EXCLUDE_SYMBOL = /[$^/]/;

function cleanName(raw) {
  return raw
    .replace(/\s*[-–]\s*(Common Stock|Class [A-Z]|Ordinary Shares|American Depositary.*|New|When Issued).*$/i, '')
    .replace(/\s+(Common Stock|Ordinary Shares|Class [A-Z]|Capital Stock|Sponsored ADR|American Depositary Shares.*)$/i, '')
    .replace(/\s+(New|When Issued)$/i, '')
    .replace(/\?/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 60);
}

function usable(symbol, name) {
  if (!symbol || !name) return false;
  if (EXCLUDE_SYMBOL.test(symbol)) return false;
  if (EXCLUDE_NAME.test(name)) return false;
  return /^[A-Z]{1,5}([.\-][A-Z])?$/.test(symbol);
}

/** Drops fields that the parser defaults, keeping the payload small. */
function compact(entry) {
  const out = { symbol: entry.symbol, name: entry.name, assetClass: entry.assetClass };
  if (entry.exchange) out.exchange = entry.exchange;
  if (entry.currency && entry.currency !== 'USD') out.currency = entry.currency;
  if (entry.isin) out.isin = entry.isin;
  if (entry.expenseRatio != null) out.expenseRatio = entry.expenseRatio;
  if (entry.provider && entry.provider !== 'yahoo') out.provider = entry.provider;
  if (entry.providerSymbol && entry.providerSymbol !== entry.symbol) {
    out.providerSymbol = entry.providerSymbol;
  }
  return out;
}

function parseNasdaqListed(text) {
  const out = [];
  const lines = text.split(/\r?\n/).filter((line) => line.includes('|'));
  for (let i = 1; i < lines.length; i++) {
    const f = lines[i].split('|');
    if (f.length < 8) continue;
    const [symbol, name, , testIssue, , , etf] = f;
    if (testIssue !== 'N' || !usable(symbol, name)) continue;
    const normalized = symbol.replace(/\./g, '-');
    out.push({
      symbol: normalized,
      name: cleanName(name),
      assetClass: etf === 'Y' ? 'ETF' : 'STOCK',
      exchange: 'NASDAQ',
      providerSymbol: normalized,
    });
  }
  return out;
}

function parseOtherListed(text) {
  const exchanges = { N: 'NYSE', A: 'NYSE American', P: 'NYSE Arca', Z: 'Cboe', V: 'IEX' };
  const out = [];
  const lines = text.split(/\r?\n/).filter((line) => line.includes('|'));
  for (let i = 1; i < lines.length; i++) {
    const f = lines[i].split('|');
    if (f.length < 8) continue;
    const [actSymbol, name, exchange, , etf, , testIssue] = f;
    if (testIssue !== 'N' || !usable(actSymbol, name)) continue;
    const normalized = actSymbol.replace(/\./g, '-');
    out.push({
      symbol: normalized,
      name: cleanName(name),
      assetClass: etf === 'Y' ? 'ETF' : 'STOCK',
      exchange: exchanges[exchange] || exchange,
      providerSymbol: normalized,
    });
  }
  return out;
}

// suffix | venue | currency | "TICKER=Name,..."
const MARKETS = require('./markets.js');

const INDICES = [
  ['^GSPC', 'S&P 500 Index', 'US'],
  ['^NDX', 'Nasdaq 100 Index', 'US'],
  ['^DJI', 'Dow Jones Industrial Average', 'US'],
  ['^RUT', 'Russell 2000 Index', 'US'],
  ['^VIX', 'CBOE Volatility Index', 'US'],
  ['^FTSE', 'FTSE 100 Index', 'UK'],
  ['^GDAXI', 'DAX Index', 'Germany'],
  ['^FCHI', 'CAC 40 Index', 'France'],
  ['^STOXX50E', 'Euro Stoxx 50 Index', 'Eurozone'],
  ['^AEX', 'AEX Index', 'Netherlands'],
  ['^IBEX', 'IBEX 35 Index', 'Spain'],
  ['^SSMI', 'Swiss Market Index', 'Switzerland'],
  ['^OMX', 'OMX Stockholm 30 Index', 'Sweden'],
  ['^N225', 'Nikkei 225 Index', 'Japan'],
  ['^TOPX', 'TOPIX Index', 'Japan'],
  ['^HSI', 'Hang Seng Index', 'Hong Kong'],
  ['^SSEC', 'Shanghai Composite Index', 'China'],
  ['^KS11', 'KOSPI Index', 'South Korea'],
  ['^TWII', 'Taiwan Weighted Index', 'Taiwan'],
  ['^NSEI', 'Nifty 50 Index', 'India'],
  ['^BSESN', 'BSE Sensex Index', 'India'],
  ['^AXJO', 'S&P/ASX 200 Index', 'Australia'],
  ['^GSPTSE', 'S&P/TSX Composite Index', 'Canada'],
  ['^BVSP', 'Bovespa Index', 'Brazil'],
  ['^MXX', 'IPC Mexico Index', 'Mexico'],
  ['^STI', 'Straits Times Index', 'Singapore'],
];

function buildInternational() {
  const out = [];
  for (const [suffix, venue, currency, list] of MARKETS) {
    for (const pair of list.split(',')) {
      const [ticker, name] = pair.split('=');
      if (!ticker || !name || name === 'x' || ticker.includes('?')) continue;
      const symbol = `${ticker}.${suffix}`;
      out.push({
        symbol,
        name: name.replace(/\?/g, '').trim(),
        assetClass: 'STOCK',
        exchange: venue,
        currency,
        providerSymbol: symbol,
      });
    }
  }
  for (const [symbol, name, region] of INDICES) {
    out.push({
      symbol,
      name,
      assetClass: 'INDEX',
      exchange: region,
      providerSymbol: symbol,
    });
  }
  return out;
}

function dedupe(list) {
  const seen = new Map();
  for (const item of list) if (!seen.has(item.symbol)) seen.set(item.symbol, item);
  return [...seen.values()];
}

async function fetchCached(url, file) {
  const target = path.join(CACHE, file);
  if (fs.existsSync(target)) return fs.readFileSync(target, 'utf8');
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url} -> HTTP ${response.status}`);
  const text = await response.text();
  fs.mkdirSync(CACHE, { recursive: true });
  fs.writeFileSync(target, text);
  return text;
}

function write(name, note, instruments) {
  const payload = {
    version: CATALOG_VERSION,
    note,
    instruments: instruments.map(compact),
  };
  const gz = zlib.gzipSync(Buffer.from(JSON.stringify(payload)), { level: 9 });
  const target = path.join(ROOT, 'assets', 'data', name);
  fs.writeFileSync(target, gz);
  console.log(
    `${name}: ${instruments.length} instruments, ${(gz.length / 1024).toFixed(0)} KB gzipped`,
  );
}

async function main() {
  // Reuse curated expense ratios already published in instruments.json.
  const curated = JSON.parse(
    fs.readFileSync(path.join(ROOT, 'assets', 'data', 'instruments.json'), 'utf8'),
  );
  const expense = {};
  for (const i of curated.instruments) {
    if (i.expenseRatio != null) expense[i.symbol] = i.expenseRatio;
  }

  const us = dedupe([
    ...parseNasdaqListed(await fetchCached(NASDAQ_LISTED, 'nasdaqlisted.txt')),
    ...parseOtherListed(await fetchCached(OTHER_LISTED, 'otherlisted.txt')),
  ]).map((i) => (expense[i.symbol] != null ? { ...i, expenseRatio: expense[i.symbol] } : i));

  write(
    'instruments_us.json.gz',
    'Generated from the NASDAQ Trader symbol directory. Regenerate with tool/build_catalog.js.',
    us,
  );
  write(
    'instruments_intl.json.gz',
    'Curated EU / Asia / Americas listings and global indices, mapped to Yahoo Finance symbols.',
    dedupe(buildInternational()),
  );
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
