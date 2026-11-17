// Messages from the admin to the phones.
//
//   GET    /api/notices?batch=bs-2026-2030   anyone: messages of the last 7 days
//                                            for that batch or for everyone
//   POST   /api/notices {title, body, batch, send_at}
//                                            admin: send one now, or at send_at
//                                            ('' batch = everyone)
//   DELETE /api/notices?id=12                admin: take one back
//
// Phones with push get a message at once; the rest when they next check.
// A message set for later goes out when the first phone checks in after its
// time (see sendDue in lib/push.js), so within a few minutes in the daytime.

const { sql, isAdmin, sessionUser, text } = require('../lib/db');
const { push, topicFor, sendDue } = require('../lib/push');

const BATCH = /^[a-z0-9-]{2,40}$/;

module.exports = async (req, res) => {
  if (req.method === 'GET') {
    const batch = String(req.query.batch || '').toLowerCase();
    if (batch && !BATCH.test(batch)) return res.status(400).json({ error: 'bad batch' });
    await sendDue(sql);
    const rows = await sql`
      SELECT id, batch, title, body, send_at AS created FROM notices
      WHERE send_at <= now() AND send_at > now() - interval '7 days'
        AND (batch = '' OR batch = ${batch})
      ORDER BY send_at DESC LIMIT 20`;
    res.setHeader('Cache-Control', 'public, max-age=0, s-maxage=15');
    return res.status(200).json({ notices: rows.map((r) => ({ ...r, id: Number(r.id) })) });
  }
  if (!isAdmin(req)) return res.status(401).json({ error: 'not allowed' });
  res.setHeader('Cache-Control', 'no-store');

  if (req.method === 'POST') {
    const b = req.body || {};
    const title = text(b.title, 80);
    const body = typeof b.body === 'string' ? b.body.replace(/\r/g, '').trim().slice(0, 500) : '';
    const batch = text(b.batch, 40).toLowerCase();
    if (!title) return res.status(400).json({ error: 'Write a title.' });
    if (batch && !BATCH.test(batch)) return res.status(400).json({ error: 'bad batch' });
    let at = null;
    if (b.send_at) {
      const t = Date.parse(b.send_at);
      if (Number.isNaN(t)) return res.status(400).json({ error: 'That time could not be read.' });
      if (t > Date.now() + 60 * 86400e3) return res.status(400).json({ error: 'At most 60 days ahead.' });
      if (t > Date.now() + 30e3) at = new Date(t).toISOString();
    }
    const by = sessionUser(req) || 'key';
    if (at) {
      const [row] = await sql`
        INSERT INTO notices (batch, title, body, sent_by, send_at, pushed)
        VALUES (${batch}, ${title}, ${body}, ${by}, ${at}::timestamptz, false)
        RETURNING id, send_at`;
      return res.status(200).json({ ok: true, id: Number(row.id), scheduled: row.send_at });
    }
    const [row] = await sql`
      INSERT INTO notices (batch, title, body, sent_by) VALUES (${batch}, ${title}, ${body}, ${by})
      RETURNING id, created`;
    const pushed = await push(topicFor(batch), {
      show: { title, body },
      data: { type: 'notice', id: Number(row.id) },
    });
    return res.status(200).json({ ok: true, id: Number(row.id), created: row.created, pushed });
  }
  if (req.method === 'DELETE') {
    const id = Number(req.query.id);
    if (!Number.isInteger(id)) return res.status(400).json({ error: 'bad id' });
    await sql`DELETE FROM notices WHERE id = ${id}`;
    return res.status(200).json({ ok: true });
  }
  res.setHeader('Allow', 'GET, POST, DELETE');
  return res.status(405).json({ error: 'method not allowed' });
};
