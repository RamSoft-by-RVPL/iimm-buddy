// Reads an academic calendar document (.docx) into dated events.
//
// The document is tables of three columns: activity, date(s), day(s). A
// heading before each table says what it is about ("Semester-I", "List of
// holidays"). Every row with a real date becomes one event:
//   { title, from: 'YYYY-MM-DD', to: 'YYYY-MM-DD', kind, group }
// kind is one of: exam, holiday, break, info. Rows that only name a month
// ("January 2027") have no exact date and are returned separately.

const { unzipSync, strFromU8 } = require('fflate');

const MONTHS = ['january', 'february', 'march', 'april', 'may', 'june', 'july',
  'august', 'september', 'october', 'november', 'december'];
const M = '(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';

const month = (name) => MONTHS.findIndex((m) => m.startsWith(name.toLowerCase().slice(0, 3))) + 1;
const iso = (y, m, d) => `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
const real = (y, m, d) => {
  const t = new Date(Date.UTC(y, m - 1, d));
  return t.getUTCFullYear() === +y && t.getUTCMonth() === m - 1 && t.getUTCDate() === +d;
};

/**
 * "5–6 September 2026", "31 October–4 November 2026",
 * "20 December 2026 – 3 January 2027", "30 May – 31 July 2027",
 * "14 September 2026" -> [from, to]. Null when there is no exact day.
 */
function parseDates(raw) {
  const s = String(raw).replace(/[‒-―−]/g, '-').replace(/\s+/g, ' ').trim();
  let m;
  const out = (y1, m1, d1, y2, m2, d2) =>
    real(y1, m1, d1) && real(y2, m2, d2) && iso(y1, m1, d1) <= iso(y2, m2, d2)
      ? [iso(y1, m1, d1), iso(y2, m2, d2)] : null;
  // 20 December 2026 - 3 January 2027
  m = s.match(new RegExp(`^(\\d{1,2}) ${M},? (\\d{4}) ?- ?(\\d{1,2}) ${M},? (\\d{4})$`, 'i'));
  if (m) return out(+m[3], month(m[2]), +m[1], +m[6], month(m[5]), +m[4]);
  // 31 October - 4 November 2026 (the first date is in the year before
  // when its month comes later in the year than the second)
  m = s.match(new RegExp(`^(\\d{1,2}) ${M} ?- ?(\\d{1,2}) ${M},? (\\d{4})$`, 'i'));
  if (m) {
    const y2 = +m[5];
    const y1 = month(m[2]) > month(m[4]) ? y2 - 1 : y2;
    return out(y1, month(m[2]), +m[1], y2, month(m[4]), +m[3]);
  }
  // 5-6 September 2026
  m = s.match(new RegExp(`^(\\d{1,2}) ?- ?(\\d{1,2}) ${M},? (\\d{4})$`, 'i'));
  if (m) return out(+m[4], month(m[3]), +m[1], +m[4], month(m[3]), +m[2]);
  // 14 September 2026
  m = s.match(new RegExp(`^(\\d{1,2}) ${M},? (\\d{4})$`, 'i'));
  if (m) return out(+m[3], month(m[2]), +m[1], +m[3], month(m[2]), +m[1]);
  return null;
}

/** exam, holiday, break or info, from the wording. */
function kindOf(title, holidayTable) {
  if (/\bexam/i.test(title)) return 'exam';
  // "Classes Resume after Diwali Break" is a normal working day.
  if (/\bclasses\b.*\b(resume|begin|end|start)/i.test(title)) return 'info';
  if (/\bbreak\b|\bvacation\b/i.test(title)) return 'break';
  if (holidayTable || /\bholiday\b/i.test(title)) return 'holiday';
  return 'info';
}

const textOf = (xml) => [...xml.matchAll(/<w:t(?: [^>]*)?>([^<]*)<\/w:t>/g)].map((t) => t[1]).join('')
  .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
  .replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/\s+/g, ' ').trim();

/** Returns { events, undated, title }. Throws when it is not a Word file. */
function readCalendar(bytes) {
  let doc;
  try {
    doc = strFromU8(unzipSync(new Uint8Array(bytes))['word/document.xml']);
  } catch (e) {
    throw new Error('This is not a Word (.docx) file.');
  }
  const body = doc.split('<w:body>')[1] || doc;
  const events = [];
  const undated = [];
  let heading = '';
  let title = '';
  for (const part of body.matchAll(/<w:tbl>[\s\S]*?<\/w:tbl>|<w:p[ >][\s\S]*?<\/w:p>/g)) {
    const xml = part[0];
    if (!xml.startsWith('<w:tbl>')) {
      const t = textOf(xml);
      if (!t) continue;
      if (!title && /calendar/i.test(t)) title = t.slice(0, 120);
      if (t.length <= 90) heading = t;
      continue;
    }
    const rows = [...xml.matchAll(/<w:tr[ >][\s\S]*?<\/w:tr>/g)]
      .map((r) => [...r[0].matchAll(/<w:tc>[\s\S]*?<\/w:tc>/g)].map((c) => textOf(c[0])));
    if (!rows.length || rows[0].length < 2) continue;
    // Which column holds the dates? Look at the header row.
    const head = rows[0].map((c) => c.toLowerCase());
    const dateCol = head.findIndex((c) => /^date/.test(c));
    if (dateCol < 0) continue; // not a table of dated rows
    const nameCol = dateCol === 0 ? 1 : 0;
    const holidayTable = /holiday/.test(head[nameCol]) || /holiday/i.test(heading);
    const group = holidayTable ? 'Holidays' : heading.replace(/\s*\(.*$/, '').slice(0, 60);
    for (const row of rows.slice(1)) {
      const name = (row[nameCol] || '').slice(0, 120);
      const when = row[dateCol] || '';
      if (!name || !when) continue;
      const span = parseDates(when);
      if (!span) { undated.push({ title: name, when }); continue; }
      events.push({ title: name, from: span[0], to: span[1], kind: kindOf(name, holidayTable), group });
    }
  }
  // The same days are often listed twice (in the term table and again in
  // the holiday list): keep one, preferring the wording that says "break".
  const seen = new Map();
  for (const e of events) {
    const key = `${e.from}|${e.to}`;
    const have = seen.get(key);
    const base = (s) => s.toLowerCase().replace(/\b(holiday|break)\b/g, '').replace(/\s+/g, ' ').trim();
    if (have && base(have.title) === base(e.title)) {
      if (e.kind === 'break') seen.set(key, e);
      continue;
    }
    seen.set(have ? `${key}|${e.title}` : key, e);
  }
  const out = [...seen.values()].sort((a, b) => (a.from + a.to).localeCompare(b.from + b.to));
  return { events: out, undated, title };
}

module.exports = { readCalendar, parseDates, kindOf };
