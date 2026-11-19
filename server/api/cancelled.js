// Classes the admin has called off. Each phone hides them from its
// timetable and reminders, and says "Class cancelled" like any other change.
//
//   GET    /api/cancelled?batch=bs-2026-2030          anyone: from yesterday on
//   POST   /api/cancelled?batch=bs-2026-2030          admin: {classes: [{d, s, c}], why, notice}
//   DELETE /api/cancelled?batch=bs-2026-2030&id=12    admin: the class is on again
//
//   d  date 'YYYY-MM-DD'    s  start 'HH:MM'
//   c  course as on the timetable ('' = every class starting then)
//   notice  true also sends a notification (for phones on older app versions)

const { sql, isAdmin, text } = require('../lib/db');
const { push, topicFor, pushNotice } = require('../lib/push');

const BATCH = /^[a-z0-9-]{2,40}$/;
const DAY = /^\d{4}-\d{2}-\d{2}$/;
const TIME = /^([01]\d|2[0-3]):[0-5]\d$/;
const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const when = (d, s) => {
  const x = new Date(d + 'T00:00:00Z');
  return `${DAYS[x.getUTCDay()]} ${x.getUTCDate()} ${MONTHS[x.getUTCMonth()]}, ${s}`;
};

function clean(body) {
  if (!body || !Array.isArray(body.classes) || !body.classes.length || body.classes.length > 60) return null;
  const out = [];
  for (const x of body.classes) {
    if (!x || !DAY.test(x.d) || !TIME.test(x.s)) return null;
    out.push({ d: x.d, s: x.s, c: text(x.c, 120) });
  }
  return out;
}

const list = (batch) => sql`
  SELECT id, to_char(d, 'YYYY-MM-DD') AS d, s, c, why
  FROM cancellations
  WHERE batch = ${batch} AND d >= (now() AT TIME ZONE 'Asia/Kolkata')::date - 1
  ORDER BY d, s, id`;

module.exports = async (req, res) => {
  const batch = String(req.query.batch || '').toLowerCase();
  if (!BATCH.test(batch)) return res.status(400).json({ error: 'bad batch' });

  if (req.method === 'GET') {
    res.setHeader('Cache-Control', 'public, max-age=0, s-maxage=15');
    return res.status(200).json({ classes: await list(batch) });
  }
  if (!isAdmin(req)) return res.status(401).json({ error: 'not allowed' });
  res.setHeader('Cache-Control', 'no-store');

  if (req.method === 'POST') {
    const classes = clean(req.body);
    if (!classes) return res.status(400).json({ error: 'bad classes' });
    const why = text(req.body.why, 200);
    for (const x of classes) {
      await sql`
        INSERT INTO cancellations (batch, d, s, c, why)
        SELECT ${batch}, ${x.d}, ${x.s}, ${x.c}, ${why}
        WHERE NOT EXISTS (SELECT 1 FROM cancellations
          WHERE batch = ${batch} AND d = ${x.d} AND s = ${x.s} AND c = ${x.c})`;
    }
    // Phones fetch the timetable again; the app announces the change itself.
    const pushed = await push(topicFor(batch), { data: { type: 'timetable' } });
    let noticed = null;
    if (req.body.notice === true) {
      const title = classes.length === 1
        ? `Class cancelled: ${classes[0].c || 'class at ' + classes[0].s}`
        : `${classes.length} classes cancelled`;
      const body = [classes.map((x) => (classes.length > 1 && x.c ? x.c + ' · ' : '') + when(x.d, x.s)).join('; '), why]
        .filter(Boolean).join('. ').slice(0, 500);
      const rows = await sql`
        INSERT INTO notices (batch, title, body, pushed)
        VALUES (${batch}, ${title}, ${body}, true)
        RETURNING id, batch, title, body, users`;
      noticed = await pushNotice(rows[0]);
    }
    return res.status(200).json({ ok: true, classes: await list(batch), pushed, noticed });
  }
  if (req.method === 'DELETE') {
    const id = Number(req.query.id);
    if (!Number.isInteger(id)) return res.status(400).json({ error: 'bad id' });
    await sql`DELETE FROM cancellations WHERE id = ${id} AND batch = ${batch}`;
    await push(topicFor(batch), { data: { type: 'timetable' } });
    return res.status(200).json({ ok: true, classes: await list(batch) });
  }
  res.setHeader('Allow', 'GET, POST, DELETE');
  return res.status(405).json({ error: 'method not allowed' });
};
