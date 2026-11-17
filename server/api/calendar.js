// The academic calendar of a batch: exams, holidays, breaks and term dates.
//
//   GET    /api/calendar?batch=bs-2026-2030   anyone
//   POST   /api/calendar?batch=bs-2026-2030   admin: {title, events:[{title, from, to, kind, group}]}
//   DELETE /api/calendar?batch=bs-2026-2030   admin: remove it

const { sql, isAdmin, text } = require('../lib/db');
const { push, topicFor, sendDue } = require('../lib/push');

const BATCH = /^[a-z0-9-]{2,40}$/;
const DAY = /^\d{4}-\d{2}-\d{2}$/;
const KINDS = ['exam', 'holiday', 'break', 'info'];

function clean(body) {
  if (!body || !Array.isArray(body.events) || body.events.length > 400) return null;
  const out = [];
  for (const e of body.events) {
    if (!e || !DAY.test(e.from) || !DAY.test(e.to) || e.to < e.from) return null;
    const title = text(e.title, 120);
    if (!title || !KINDS.includes(e.kind)) return null;
    out.push({ title, from: e.from, to: e.to, kind: e.kind, group: text(e.group, 60) });
  }
  return out;
}

module.exports = async (req, res) => {
  const batch = String(req.query.batch || '').toLowerCase();
  if (!BATCH.test(batch)) return res.status(400).json({ error: 'bad batch' });

  if (req.method === 'GET') {
    await sendDue(sql);
    const rows = await sql`SELECT updated, title, events FROM calendars WHERE batch = ${batch}`;
    res.setHeader('Cache-Control', 'public, max-age=0, s-maxage=30');
    if (!rows.length) return res.status(200).json({ updated: null, title: '', events: [] });
    return res.status(200).json({
      updated: new Date(rows[0].updated).toISOString(),
      title: rows[0].title,
      events: rows[0].events,
    });
  }
  if (!isAdmin(req)) return res.status(401).json({ error: 'not allowed' });
  res.setHeader('Cache-Control', 'no-store');

  if (req.method === 'POST') {
    const events = clean(req.body);
    if (!events) return res.status(400).json({ error: 'bad calendar' });
    const rows = await sql`
      INSERT INTO calendars (batch, updated, title, events)
      VALUES (${batch}, now(), ${text(req.body.title, 120)}, ${JSON.stringify(events)}::jsonb)
      ON CONFLICT (batch) DO UPDATE
        SET updated = now(), title = EXCLUDED.title, events = EXCLUDED.events
      RETURNING updated`;
    const pushed = await push(topicFor(batch), { data: { type: 'calendar' } });
    return res.status(200).json({
      ok: true, updated: new Date(rows[0].updated).toISOString(), count: events.length, pushed,
    });
  }
  if (req.method === 'DELETE') {
    await sql`DELETE FROM calendars WHERE batch = ${batch}`;
    await push(topicFor(batch), { data: { type: 'calendar' } });
    return res.status(200).json({ ok: true });
  }
  res.setHeader('Allow', 'GET, POST, DELETE');
  return res.status(405).json({ error: 'method not allowed' });
};
