// Enumerates European cash-equity listings from Yahoo Finance's screener and
// caches them for tool/build_catalog.js.
//
//   node tool/fetch_eu_listings.js            # uses tool/.cache/eu_listings.json
//   node tool/fetch_eu_listings.js --refresh  # re-downloads
//
// Yahoo's screener needs a cookie + crumb pair; both are fetched here. Every
// venue is queried by exchange code with a market-cap floor, which keeps bonds,
// certificates and warrants out of the result. The screener labels European
// bonds as EQUITY, so names that look like debt/structured products are dropped
// as well.
const fs = require('fs');
const path = require('path');
const https = require('https');

const CACHE = path.join(__dirname, '.cache');
const TARGET = path.join(CACHE, 'eu_listings.json');
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)';

/// [Yahoo exchange code, venue label, symbol suffix], in preference order: when
/// the same company shows up on several venues, the first one keeps it. Vienna
/// comes last because it lists hundreds of German/Swiss names alongside its own
/// handful of Austrian ones.
const VENUES = [
  ['GER', 'XETRA', '.DE'],
  ['PAR', 'Euronext Paris', '.PA'],
  ['AMS', 'Euronext Amsterdam', '.AS'],
  ['BRU', 'Euronext Brussels', '.BR'],
  ['LIS', 'Euronext Lisbon', '.LS'],
  ['MIL', 'Borsa Italiana', '.MI'],
  ['MCE', 'Bolsa de Madrid', '.MC'],
  ['EBS', 'SIX Swiss Exchange', '.SW'],
  ['STO', 'Nasdaq Stockholm', '.ST'],
  ['CPH', 'Nasdaq Copenhagen', '.CO'],
  ['OSL', 'Oslo Bors', '.OL'],
  ['HEL', 'Nasdaq Helsinki', '.HE'],
  ['WSE', 'GPW Warsaw', '.WA'],
  ['ATH', 'Athens Exchange', '.AT'],
  ['BUD', 'Budapest Stock Exchange', '.BD'],
  ['ISE', 'Euronext Dublin', '.IR'],
  ['IST', 'Borsa Istanbul', '.IS'],
  ['LSE', 'London Stock Exchange', '.L'],
  ['VIE', 'Wiener Boerse', '.VI'],
];

/// LSE numbers its international/DR lines `0…`; the home listings are already
/// covered by the other venues, so they would only be duplicates.
const SECONDARY_LINE = /^0/;

const MIN_MARKET_CAP = 20000000;
const PAGE = 250;

const DEBT_OR_STRUCTURED =
  /%|\bC\.[A-Z]{2,}|\b(certificate|certificates|cert\.?|warrant|warrants|turbo|knock-?out|open end|anleihe|obligation|bond|bonds|notes? due|schuldverschreibung|tracker|ETC|ETN|discount|bonus)\b/i;

function request(method, url, headers, payload) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const body = payload ? JSON.stringify(payload) : null;
    const req = https.request(
      {
        hostname: u.hostname,
        path: u.pathname + u.search,
        method,
        headers: body
          ? {
              ...headers,
              'content-type': 'application/json',
              'content-length': Buffer.byteLength(body),
            }
          : headers,
      },
      (res) => {
        let text = '';
        res.on('data', (chunk) => (text += chunk));
        res.on('end', () =>
          resolve({ status: res.statusCode, headers: res.headers, text }),
        );
      },
    );
    req.on('error', reject);
    req.setTimeout(25000, () => req.destroy(new Error('timeout')));
    if (body) req.write(body);
    req.end();
  });
}

async function credentials() {
  const consent = await request('GET', 'https://fc.yahoo.com', {
    'User-Agent': UA,
  });
  const cookie = (consent.headers['set-cookie'] || [])
    .map((c) => c.split(';')[0])
    .join('; ');
  const crumb = await request(
    'GET',
    'https://query1.finance.yahoo.com/v1/test/getcrumb',
    { 'User-Agent': UA, Cookie: cookie },
  );
  if (crumb.status !== 200 || !crumb.text.trim()) {
    throw new Error(`could not obtain a Yahoo crumb (HTTP ${crumb.status})`);
  }
  return { cookie, crumb: crumb.text.trim() };
}

async function screen(code, offset, creds, minCap) {
  const operands = [
    { operator: 'eq', operands: ['exchange', code] },
  ];
  if (minCap) {
    operands.push({
      operator: 'gt',
      operands: ['intradaymarketcap', minCap],
    });
  }
  const payload = {
    size: PAGE,
    offset,
    sortField: 'intradaymarketcap',
    sortType: 'DESC',
    quoteType: 'EQUITY',
    topOperator: 'and',
    query: { operator: 'and', operands },
    userId: '',
    userIdType: 'guid',
  };
  const res = await request(
    'POST',
    `https://query1.finance.yahoo.com/v1/finance/screener?crumb=${encodeURIComponent(
      creds.crumb,
    )}&lang=en-US&region=US`,
    {
      'User-Agent': UA,
      Cookie: creds.cookie,
      Accept: 'application/json',
    },
    payload,
  );
  if (res.status !== 200) {
    throw new Error(`screener ${code}@${offset} -> HTTP ${res.status}`);
  }
  const result = JSON.parse(res.text)?.finance?.result?.[0];
  if (!result) throw new Error(`screener ${code}@${offset} returned no result`);
  return result;
}

/// Yahoo caps a result set at 1,250 rows, and its market-cap field is missing
/// for some listings, so every venue is queried twice — with a cap floor (which
/// can be paged to completion) and without (the largest 1,250 by cap) — and the
/// two are unioned.
async function collect(code, creds) {
  const bySymbol = new Map();
  for (const [minCap, maxPages] of [[MIN_MARKET_CAP, Infinity], [0, 5]]) {
    let total = Infinity;
    let offset = 0;
    let pages = 0;
    while (offset < total && pages < maxPages) {
      const result = await screen(code, offset, creds, minCap);
      total = result.total ?? 0;
      const quotes = result.quotes ?? [];
      if (quotes.length === 0) break;
      for (const quote of quotes) bySymbol.set(quote.symbol, quote);
      offset += quotes.length;
      pages++;
    }
  }
  return bySymbol;
}

function cleanName(raw) {
  return raw
    .replace(/\s{2,}[A-Z]\s*$/, '') // Yahoo pads share-class markers: "BECHTLE AG    I"
    .replace(
      /((?:AG|SE|SA|S\.A\.|NV|N\.V\.|AS|ASA|A\/S|AB|PLC|SPA|S\.p\.A\.|BV|OYJ|KGaA|GmbH|Ltd\.?|Inc\.?)\s+)[A-Z]$/i,
      '$1',
    )
    .replace(/\s+/g, ' ')
    .replace(/[\s,]+$/, '')
    .trim();
}

/// "NVIDIA CORP." -> "NVIDIA Corp.", "ASML HOLDING" -> "ASML Holding".
function tidyCase(name) {
  if (name !== name.toUpperCase()) return name;
  return name
    .split(' ')
    .map((word) => {
      const bare = word.replace(/[^A-Za-z0-9]/g, '');
      if (!bare) return word;
      if (bare.length <= 4) return word;
      return word
        .toLowerCase()
        .replace(/(^|[-'&/(])([a-z])/g, (_, p, c) => p + c.toUpperCase());
    })
    .join(' ');
}

/// Drops Yahoo's trailing share-class marker ("Swiss RE N", "SAP SE I") but
/// keeps real class suffixes ("Atlas Copco AB ser. A").
function stripShareClassMarker(name) {
  const match = name.match(/^(.*\S)\s+([ABINR])$/);
  if (!match) return name;
  if (/\b(ser\.?|Class|CL|Cl|shs|SHS)$/.test(match[1])) return name;
  // I/N/R are venue share-type markers and never part of a company name.
  // A/B can be a genuine share class, so only strip them from longer names.
  if ('AB'.includes(match[2]) && match[1].length < 6) return name;
  return match[1];
}

function usable(quote, suffix) {
  const symbol = quote.symbol || '';
  const name = stripShareClassMarker(
    cleanName(quote.shortName || quote.longName || ''),
  );
  if (!name || name.length < 2) return null;
  if (!symbol.toUpperCase().endsWith(suffix)) return null;
  if (!/^[A-Z0-9][A-Z0-9.\-]{0,15}$/i.test(symbol)) return null;
  if (suffix === '.L' && SECONDARY_LINE.test(symbol)) return null;
  if (DEBT_OR_STRUCTURED.test(name)) return null;
  if (!quote.currency) return null;
  return {
    symbol,
    name: name.slice(0, 60),
    currency: quote.currency,
  };
}

/// Cross-venue duplicate key: ignores case, punctuation and share-class noise.
function nameKey(name) {
  return name.toLowerCase().replace(/[^a-z0-9]/g, '');
}

async function fetchAll() {
  const creds = await credentials();
  const out = [];
  const seen = new Set();
  for (const [code, venue, suffix] of VENUES) {
    const quotes = [...(await collect(code, creds)).values()];
    let kept = 0;
    for (const quote of quotes) {
      const entry = usable(quote, suffix);
      if (!entry) continue;
      const key = nameKey(entry.name);
      if (seen.has(key)) continue;
      seen.add(key);
      out.push({
        symbol: entry.symbol,
        name: tidyCase(entry.name),
        assetClass: 'STOCK',
        exchange: venue,
        currency: entry.currency,
        providerSymbol: entry.symbol,
      });
      kept++;
    }
    process.stdout.write(
      `  ${code.padEnd(4)} ${String(quotes.length).padStart(5)} quotes, ${kept} kept\n`,
    );
  }
  return out;
}

async function main() {
  const refresh = process.argv.includes('--refresh');
  if (!refresh && fs.existsSync(TARGET)) {
    const cached = JSON.parse(fs.readFileSync(TARGET, 'utf8'));
    console.log(
      `${path.relative(process.cwd(), TARGET)}: ${cached.length} listings (cached, use --refresh to re-download)`,
    );
    return;
  }
  const listings = await fetchAll();
  fs.mkdirSync(CACHE, { recursive: true });
  fs.writeFileSync(TARGET, JSON.stringify(listings));
  console.log(`wrote ${listings.length} European listings to ${TARGET}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
