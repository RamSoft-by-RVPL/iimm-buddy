// Shared class timetable for one batch.
//
//   GET  /api/timetable?batch=bs-2026-2030   anyone: the batch's timetable
//   POST /api/timetable?batch=bs-2026-2030   publisher only (Authorization: Bearer <key>)

const { sql, isAdmin } = require('../lib/db');
const { push, topicFor } = require('../lib/push');

const BATCH = /^[a-z0-9-]{2,40}$/;
const DAY = /^\d{4}-\d{2}-\d{2}$/;
const TIME = /^\d{2}:\d{2}$/;

/** Returns the cleaned class list, or null when the body is not acceptable. */
function clean(body) {
  if (!body || !Array.isArray(body.classes) || body.classes.length > 600) return null;
  const out = [];
  for (const c of body.classes) {
    if (!c || !DAY.test(c.d) || !TIME.test(c.s) || !TIME.test(c.e)) return null;
    if (typeof c.c !== 'string' || !c.c.trim() || c.c.length > 120) return null;
    const f = typeof c.f === 'string' ? c.f.slice(0, 120) : '';
    out.push({ d: c.d, s: c.s, e: c.e, c: c.c.trim(), f });
  }
  return out;
}

module.exports = async (req, res) => {
  const batch = String(req.query.batch || '').toLowerCase();
  if (!BATCH.test(batch)) return res.status(400).json({ error: 'bad batch' });

  if (req.method === 'GET') {
    const rows = await sql`SELECT updated, classes FROM timetables WHERE batch = ${batch}`;
    // Every phone asks every 15 minutes: let the edge answer most of them.
    res.setHeader('Cache-Control', 'public, max-age=0, s-maxage=15');
    if (!rows.length) return res.status(200).json({ updated: null, classes: [] });
    return res.status(200).json({
      updated: new Date(rows[0].updated).toISOString(),
      classes: rows[0].classes,
    });
  }

  if (req.method === 'POST') {
    if (!isAdmin(req)) return res.status(401).json({ error: 'not allowed' });
    const classes = clean(req.body);
    if (!classes) return res.status(400).json({ error: 'bad timetable' });
    const rows = await sql`
      INSERT INTO timetables (batch, updated, classes)
      VALUES (${batch}, now(), ${JSON.stringify(classes)}::jsonb)
      ON CONFLICT (batch) DO UPDATE SET updated = now(), classes = EXCLUDED.classes
      RETURNING updated`;
    // Tell the batch's phones to fetch it now (no text: the app says
    // "Timetable updated" itself once the classes are in the schedule).
    const pushed = await push(topicFor(batch), { data: { type: 'timetable' } });
    return res.status(200).json({
      ok: true,
      updated: new Date(rows[0].updated).toISOString(),
      count: classes.length,
      pushed,
    });
  }

  res.setHeader('Allow', 'GET, POST');
  return res.status(405).json({ error: 'method not allowed' });
};
