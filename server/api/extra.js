// Classes added to a batch's timetable, or moved to a new time, by its CR
// or the admin. Phones show them like classes from the mailed timetable
// ("not on portal yet") until the attendance site lists them.
//
//   GET    /api/extra?batch=bs-2026-2030          anyone: from yesterday on
//   POST   /api/extra?batch=bs-2026-2030          admin or the batch's CR:
//          {d, s, e, c, room, why}                add a class
//          ... plus move: {d, s, c}               and call off the old one
//          ... or id: 12                          change that added class instead
//   DELETE /api/extra?batch=bs-2026-2030&id=12    take it away (a moved class
//                                                 goes back to its old time)
//
//   d  date 'YYYY-MM-DD'    s, e  start and end 'HH:MM'    c  course

const { sql, isAdmin, text } = require('../lib/db');
const { push, topicFor } = require('../lib/push');
const { roleOf } = require('../lib/roles');

const BATCH = /^[a-z0-9-]{2,40}$/;
const DAY = /^\d{4}-\d{2}-\d{2}$/;
const TIME = /^([01]\d|2[0-3]):[0-5]\d$/;
const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const when = (d, s) => {
  const x = new Date(d + 'T00:00:00Z');
  return `${DAYS[x.getUTCDay()]} ${x.getUTCDate()} ${MONTHS[x.getUTCMonth()]}, ${s}`;
};

const list = (batch) => sql`
  SELECT id, to_char(d, 'YYYY-MM-DD') AS d, s, e, c, room, why, cancel_id IS NOT NULL AS moved
  FROM extra_classes
  WHERE batch = ${batch} AND d >= (now() AT TIME ZONE 'Asia/Kolkata')::date - 1
  ORDER BY d, s, id`;

const out = (rows) => rows.map((r) => ({ ...r, id: Number(r.id) }));

module.exports = async (req, res) => {
  const batch = String(req.query.batch || '').toLowerCase();
  if (!BATCH.test(batch)) return res.status(400).json({ error: 'bad batch' });

  if (req.method === 'GET') {
    res.setHeader('Cache-Control', 'public, max-age=0, s-maxage=15');
    return res.status(200).json({ classes: out(await list(batch)) });
  }
  const admin = isAdmin(req);
  const role = admin ? null : await roleOf(req);
  if (!admin && !(role && role.can.cancel && role.batch === batch)) {
    return res.status(401).json({ error: 'not allowed' });
  }
  const byUser = role ? role.user_id : '';
  res.setHeader('Cache-Control', 'no-store');

  if (req.method === 'POST') {
    const b = req.body || {};
    const c = text(b.c, 120);
    if (!DAY.test(b.d) || !TIME.test(b.s) || !TIME.test(b.e) || b.e <= b.s || !c) {
      return res.status(400).json({ error: 'Fill in the day, the start and end time and the course.' });
    }
    const room = text(b.room, 40);
    let why = text(b.why, 200);
    if (b.id !== undefined) {
      // An added (or already moved) class goes to a new day or time: its
      // old time stays called off, so only this row changes.
      const id = Number(b.id);
      if (!Number.isInteger(id)) return res.status(400).json({ error: 'bad id' });
      const rows = await sql`
        UPDATE extra_classes SET d = ${b.d}, s = ${b.s}, e = ${b.e}, c = ${c}, room = ${room},
          why = CASE WHEN ${why} = '' THEN why ELSE ${why} END
        WHERE id = ${id} AND batch = ${batch} RETURNING id`;
      if (!rows.length) return res.status(404).json({ error: 'That class is gone.' });
      const pushed = await push(topicFor(batch), { data: { type: 'timetable' } });
      return res.status(200).json({ ok: true, classes: out(await list(batch)), pushed });
    }
    let cancelId = null;
    if (b.move) {
      const m = b.move;
      if (!DAY.test(m.d) || !TIME.test(m.s)) return res.status(400).json({ error: 'bad move' });
      if (m.d === b.d && m.s === b.s) return res.status(400).json({ error: 'Pick a new day or time.' });
      const [row] = await sql`
        INSERT INTO cancellations (batch, d, s, c, why, by_user)
        VALUES (${batch}, ${m.d}, ${m.s}, ${text(m.c, 120)}, ${'Moved to ' + when(b.d, b.s)}, ${byUser})
        RETURNING id`;
      cancelId = row.id;
      if (!why) why = 'Moved from ' + when(m.d, m.s);
    }
    await sql`
      INSERT INTO extra_classes (batch, d, s, e, c, room, why, cancel_id, by_user)
      VALUES (${batch}, ${b.d}, ${b.s}, ${b.e}, ${c}, ${room}, ${why}, ${cancelId}, ${byUser})`;
    const pushed = await push(topicFor(batch), { data: { type: 'timetable' } });
    return res.status(200).json({ ok: true, classes: out(await list(batch)), pushed });
  }
  if (req.method === 'DELETE') {
    const id = Number(req.query.id);
    if (!Number.isInteger(id)) return res.status(400).json({ error: 'bad id' });
    const rows = await sql`
      DELETE FROM extra_classes WHERE id = ${id} AND batch = ${batch} RETURNING cancel_id`;
    if (rows.length && rows[0].cancel_id) {
      await sql`DELETE FROM cancellations WHERE id = ${rows[0].cancel_id} AND batch = ${batch}`;
    }
    await push(topicFor(batch), { data: { type: 'timetable' } });
    return res.status(200).json({ ok: true, classes: out(await list(batch)) });
  }
  res.setHeader('Allow', 'GET, POST, DELETE');
  return res.status(405).json({ error: 'method not allowed' });
};
