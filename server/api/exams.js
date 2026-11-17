// The exam timetable of a batch: one entry per paper. Each student's app
// picks out the papers of their own courses.
//
//   GET    /api/exams?batch=bs-2026-2030   anyone
//   POST   /api/exams?batch=bs-2026-2030   admin: {title, exams: [{d, s, e, c, r, n}]}
//   DELETE /api/exams?batch=bs-2026-2030   admin: remove it
//
//   d  date 'YYYY-MM-DD'     s, e  start and end 'HH:MM' (e may be '')
//   c  course                r  room (may be '')     n  note, e.g. a section

const { sql, isAdmin, text } = require('../lib/db');
const { push, topicFor } = require('../lib/push');

const BATCH = /^[a-z0-9-]{2,40}$/;
const DAY = /^\d{4}-\d{2}-\d{2}$/;
const TIME = /^([01]\d|2[0-3]):[0-5]\d$/;

function clean(body) {
  if (!body || !Array.isArray(body.exams) || body.exams.length > 300) return null;
  const out = [];
  for (const x of body.exams) {
    if (!x || !DAY.test(x.d) || !TIME.test(x.s)) return null;
    const e = x.e ? String(x.e) : '';
    if (e && (!TIME.test(e) || e <= x.s)) return null;
    const c = text(x.c, 120);
    if (!c) return null;
    out.push({ d: x.d, s: x.s, e, c, r: text(x.r, 60), n: text(x.n, 120) });
  }
  return out.sort((a, b) => (a.d + a.s).localeCompare(b.d + b.s));
}

module.exports = async (req, res) => {
  const batch = String(req.query.batch || '').toLowerCase();
  if (!BATCH.test(batch)) return res.status(400).json({ error: 'bad batch' });

  if (req.method === 'GET') {
    const rows = await sql`SELECT updated, title, exams FROM exam_timetables WHERE batch = ${batch}`;
    res.setHeader('Cache-Control', 'public, max-age=0, s-maxage=30');
    if (!rows.length) return res.status(200).json({ updated: null, title: '', exams: [] });
    return res.status(200).json({
      updated: new Date(rows[0].updated).toISOString(),
      title: rows[0].title,
      exams: rows[0].exams,
    });
  }
  if (!isAdmin(req)) return res.status(401).json({ error: 'not allowed' });
  res.setHeader('Cache-Control', 'no-store');

  if (req.method === 'POST') {
    const exams = clean(req.body);
    if (!exams || !exams.length) return res.status(400).json({ error: 'bad exam timetable' });
    const rows = await sql`
      INSERT INTO exam_timetables (batch, updated, title, exams)
      VALUES (${batch}, now(), ${text(req.body.title, 120)}, ${JSON.stringify(exams)}::jsonb)
      ON CONFLICT (batch) DO UPDATE
        SET updated = now(), title = EXCLUDED.title, exams = EXCLUDED.exams
      RETURNING updated`;
    const pushed = await push(topicFor(batch), { data: { type: 'exams' } });
    return res.status(200).json({
      ok: true, updated: new Date(rows[0].updated).toISOString(), count: exams.length, pushed,
    });
  }
  if (req.method === 'DELETE') {
    await sql`DELETE FROM exam_timetables WHERE batch = ${batch}`;
    await push(topicFor(batch), { data: { type: 'exams' } });
    return res.status(200).json({ ok: true });
  }
  res.setHeader('Allow', 'GET, POST, DELETE');
  return res.status(405).json({ error: 'method not allowed' });
};

module.exports.clean = clean;
