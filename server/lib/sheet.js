// Reads the programme office's weekly timetable sheet (.xlsx): a grid with a
// header row of time slots and one row per day; each cell is "Course" then
// the teacher. Mirrors lib/sheet.dart in the app.
const { unzipSync, strFromU8 } = require('fflate');

const plain = (xml) => xml.replace(/<[^>]+>/g, '')
  .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
  .replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/_x000D_/g, '');

function column(ref) {
  let n = 0;
  for (const ch of ref) n = n * 26 + (ch.charCodeAt(0) - 64);
  return n - 1;
}

/** First sheet as rows of {columnNumber: text}. */
function readXlsx(bytes) {
  const zip = unzipSync(new Uint8Array(bytes));
  const file = (name) => (zip[name] ? strFromU8(zip[name]) : '');
  const shared = [...file('xl/sharedStrings.xml').matchAll(/<si\b[^>]*>([\s\S]*?)<\/si>/g)]
    .map((m) => plain([...m[1].matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)].map((t) => t[1]).join('')));
  const names = Object.keys(zip).filter((n) => n.startsWith('xl/worksheets/sheet')).sort();
  if (!names.length) throw new Error('No sheet in this file');
  const rows = [];
  for (const r of file(names[0]).matchAll(/<row\b[^>]*>([\s\S]*?)<\/row>/g)) {
    const row = {};
    for (const c of r[1].matchAll(/<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
      const ref = (c[1].match(/\br="([A-Z]+)\d+"/) || [])[1];
      if (!ref) continue;
      const type = (c[1].match(/\bt="(\w+)"/) || [])[1];
      const body = c[2] || '';
      const v = (body.match(/<v>([\s\S]*?)<\/v>/) || [])[1];
      let value;
      if (type === 's') value = shared[Number(v)] || '';
      else if (type === 'inlineStr') value = plain([...body.matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)].map((t) => t[1]).join(''));
      else value = plain(v || '');
      if (value.trim()) row[column(ref)] = value.trim();
    }
    if (Object.keys(row).length) rows.push(row);
  }
  return rows;
}

const SLOT = /^\s*(\d{1,2})[:.](\d{2})\s*(?:to|-|–|—)\s*(\d{1,2})[:.](\d{2})\s*$/i;
const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
const iso = (y, m, d) => `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;

function day(s) {
  const n = Number(s);
  if (!Number.isNaN(n) && s.trim() !== '') {
    if (n < 30000 || n > 80000) return null;
    const d = new Date(Date.UTC(1899, 11, 30 + Math.floor(n))); // Excel day count
    return iso(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate());
  }
  let m = s.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})/);
  if (m) return iso(m[3], m[2], m[1]);
  m = s.match(/^(\d{1,2})\s+([A-Za-z]{3})[a-z]*\.?,?\s+(\d{4})/);
  if (m && MONTHS.includes(m[2].toLowerCase())) return iso(m[3], MONTHS.indexOf(m[2].toLowerCase()) + 1, m[1]);
  return null;
}

/** Classes in the grid: [{d, s, e, c, f}]. Throws when it is not a timetable. */
function parseTimetable(rows) {
  const hm = (h, m) => `${String(h).padStart(2, '0')}:${m}`;
  let slots = null;
  const out = [];
  for (const row of rows) {
    const found = {};
    for (const [k, v] of Object.entries(row)) {
      const m = v.match(SLOT);
      if (m) found[k] = [hm(m[1], m[2]), hm(m[3], m[4])];
    }
    if (Object.keys(found).length >= 2) { slots = found; continue; }
    if (!slots) continue;
    let d = null;
    for (const [k, v] of Object.entries(row)) if (!(k in slots) && !d) d = day(v);
    if (!d) continue;
    for (const [k, [s, e]] of Object.entries(slots)) {
      const cell = row[k];
      if (!cell || /^(lunch|break|tea|holiday|no class|-+)\b/i.test(cell.trim())) continue;
      let lines = cell.split('\n').map((l) => l.replace(/\s+/g, ' ').trim()).filter(Boolean);
      if (lines.length === 1) {
        const i = lines[0].search(/\s(Prof|Dr)\b/);
        if (i > 0) lines = [lines[0].slice(0, i), lines[0].slice(i).trim()];
      }
      out.push({ d, s, e, c: lines[0], f: lines.slice(1).join(', ') });
    }
  }
  if (!slots) throw new Error('This sheet does not look like a timetable');
  return out;
}

module.exports = { readXlsx, parseTimetable };
