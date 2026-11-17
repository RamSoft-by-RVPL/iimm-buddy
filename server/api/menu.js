// The mess menu, week by week. The same for every batch.
//
//   GET    /api/menu                 anyone: this week's menu and any later ones
//   POST   /api/menu                 admin: {week: 'YYYY-MM-DD', days: [{d, meals: [{n, items}]}]}
//   DELETE /api/menu?week=YYYY-MM-DD admin: remove that week
//
// The weekly menu file is read outside the server (by Claude) and posted
// here as plain data, so the server never has to read PDFs.

const { sql, isAdmin, text } = require('../lib/db');
const { push, topicFor } = require('../lib/push');

const DAY = /^\d{4}-\d{2}-\d{2}$/;

const addDays = (iso, n) => {
  const t = new Date(iso + 'T00:00:00Z');
  t.setUTCDate(t.getUTCDate() + n);
  return t.toISOString().slice(0, 10);
};
const real = (iso) => DAY.test(iso) && addDays(iso, 0) === iso;

/** The cleaned days of a menu, or null when the body is not acceptable. */
function clean(body) {
  if (!body || !real(body.week) || !Array.isArray(body.days)) return null;
  const last = addDays(body.week, 6);
  if (body.days.length < 1 || body.days.length > 7) return null;
  const days = [];
  const seen = new Set();
  for (const day of body.days) {
    if (!day || !real(day.d) || day.d < body.week || day.d > last || seen.has(day.d)) return null;
    seen.add(day.d);
    if (!Array.isArray(day.meals) || day.meals.length > 8) return null;
    const meals = [];
    for (const m of day.meals) {
      const n = text(m && m.n, 30);
      if (!n || !Array.isArray(m.items) || m.items.length > 30) return null;
      const items = m.items.map((i) => text(i, 80)).filter(Boolean);
      if (items.length) meals.push({ n, items });
    }
    days.push({ d: day.d, meals });
  }
  return days.sort((a, b) => a.d.localeCompare(b.d));
}

module.exports = async (req, res) => {
  if (req.method === 'GET') {
    // This week and later, by the date in India.
    const rows = await sql`
      SELECT to_char(week, 'YYYY-MM-DD') AS week, updated, days FROM menus
      WHERE week >= (now() AT TIME ZONE 'Asia/Kolkata')::date - 6
      ORDER BY week LIMIT 4`;
    res.setHeader('Cache-Control', 'public, max-age=0, s-maxage=30');
    const updated = rows.reduce((a, r) => (!a || r.updated > a ? r.updated : a), null);
    return res.status(200).json({
      updated: updated ? new Date(updated).toISOString() : null,
      weeks: rows.map((r) => ({ week: r.week, days: r.days })),
    });
  }
  if (!isAdmin(req)) return res.status(401).json({ error: 'not allowed' });
  res.setHeader('Cache-Control', 'no-store');

  if (req.method === 'POST') {
    const days = clean(req.body);
    if (!days) return res.status(400).json({ error: 'bad menu' });
    const week = req.body.week;
    const rows = await sql`
      INSERT INTO menus (week, updated, days)
      VALUES (${week}, now(), ${JSON.stringify(days)}::jsonb)
      ON CONFLICT (week) DO UPDATE SET updated = now(), days = EXCLUDED.days
      RETURNING updated`;
    await sql`DELETE FROM menus WHERE week < now()::date - 60`;
    const pushed = await push(topicFor(''), { data: { type: 'menu' } });
    return res.status(200).json({
      ok: true, week, days: days.length, updated: new Date(rows[0].updated).toISOString(), pushed,
    });
  }
  if (req.method === 'DELETE') {
    const week = String(req.query.week || '');
    if (!real(week)) return res.status(400).json({ error: 'bad week' });
    await sql`DELETE FROM menus WHERE week = ${week}`;
    await push(topicFor(''), { data: { type: 'menu' } });
    return res.status(200).json({ ok: true });
  }
  res.setHeader('Allow', 'GET, POST, DELETE');
  return res.status(405).json({ error: 'method not allowed' });
};

module.exports.clean = clean;
