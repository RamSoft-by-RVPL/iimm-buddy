// Messages from the admin to the phones.
//
//   GET    /api/notices?batch=bs-2026-2030&user=<install id>
//                                            anyone: messages of the last 7 days
//                                            for that batch or for everyone, and
//                                            those for that phone alone (offered
//                                            for an hour after they go out)
//   POST   /api/notices {title, body, batch, send_at, users}
//                                            admin: send one now, or at send_at
//                                            ('' batch = everyone; users = install
//                                            ids of the only phones it is for)
//   DELETE /api/notices?id=12                admin: take one back
//
// Phones with push get a message at once; the rest when they next check.
// A message set for later goes out when the first phone checks in after its
// time (see sendDue in lib/push.js), so within a few minutes in the daytime.

const { sql, isAdmin, sessionUser, text } = require('../lib/db');
const { sendDue, pushNotice } = require('../lib/push');

const BATCH = /^[a-z0-9-]{2,40}$/;
const USER = /^[0-9a-f]{16}$/;

module.exports = async (req, res) => {
  if (req.method === 'GET') {
    const batch = String(req.query.batch || '').toLowerCase();
    if (batch && !BATCH.test(batch)) return res.status(400).json({ error: 'bad batch' });
    const user = String(req.query.user || '');
    if (user && !USER.test(user)) return res.status(400).json({ error: 'bad user' });
    await sendDue(sql);
    // Messages for chosen people are short-lived reminders: a phone that
    // only checks in later does not get a pile of old ones.
    const rows = await sql`
      SELECT id, batch, title, body, send_at AS created FROM notices
      WHERE send_at <= now() AND send_at > now() - interval '7 days'
        AND (batch = '' OR batch = ${batch})
        AND (cardinality(users) = 0
             OR (${user} <> '' AND ${user} = ANY(users) AND send_at > now() - interval '1 hour'))
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
    const users = Array.isArray(b.users) ? [...new Set(b.users.map(String))] : [];
    if (users.length > 50 || users.some((u) => !USER.test(u))) return res.status(400).json({ error: 'bad users' });
    if (users.length && batch) return res.status(400).json({ error: 'Choose people or a batch, not both.' });
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
        INSERT INTO notices (batch, title, body, sent_by, send_at, pushed, users)
        VALUES (${batch}, ${title}, ${body}, ${by}, ${at}::timestamptz, false, ${users})
        RETURNING id, send_at`;
      return res.status(200).json({ ok: true, id: Number(row.id), scheduled: row.send_at });
    }
    const [row] = await sql`
      INSERT INTO notices (batch, title, body, sent_by, users) VALUES (${batch}, ${title}, ${body}, ${by}, ${users})
      RETURNING id, created`;
    const pushed = await pushNotice({ id: row.id, batch, title, body, users });
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
