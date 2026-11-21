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
// A CR, mess or hostel secretary (header X-Role, see api/roles.js) may also
// post and take back their own: only to the batch their role covers, at
// most a week ahead and 10 a day. The title starts with their role
// ("CR: ...") so everyone sees who it is from.
//
// Phones with push get a message at once; the rest when they next check.
// A message set for later goes out when the first phone checks in after its
// time (see sendDue in lib/push.js), so within a few minutes in the daytime.

const { sql, isAdmin, sessionUser, text } = require('../lib/db');
const { sendDue, pushNotice } = require('../lib/push');
const { roleOf } = require('../lib/roles');

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
  const admin = isAdmin(req);
  const role = admin ? null : await roleOf(req);
  if (!admin && !(role && role.can.notice)) return res.status(401).json({ error: 'not allowed' });
  res.setHeader('Cache-Control', 'no-store');

  if (req.method === 'POST') {
    const b = req.body || {};
    let title = text(b.title, 80);
    const body = typeof b.body === 'string' ? b.body.replace(/\r/g, '').trim().slice(0, 500) : '';
    let batch = text(b.batch, 40).toLowerCase();
    if (!title) return res.status(400).json({ error: 'Write a title.' });
    if (role) {
      if (b.users && b.users.length) return res.status(400).json({ error: 'not allowed' });
      batch = role.batch;
      title = `${role.label}: ${title}`;
      const [{ n }] = await sql`
        SELECT count(*)::int AS n FROM notices
        WHERE by_user = ${role.user_id} AND created > now() - interval '1 day'`;
      if (n >= 10) return res.status(429).json({ error: 'At most 10 a day. Try again tomorrow.' });
    }
    if (batch && !BATCH.test(batch)) return res.status(400).json({ error: 'bad batch' });
    const users = Array.isArray(b.users) ? [...new Set(b.users.map(String))] : [];
    if (users.length > 50 || users.some((u) => !USER.test(u))) return res.status(400).json({ error: 'bad users' });
    if (users.length && batch) return res.status(400).json({ error: 'Choose people or a batch, not both.' });
    let at = null;
    if (b.send_at) {
      const t = Date.parse(b.send_at);
      if (Number.isNaN(t)) return res.status(400).json({ error: 'That time could not be read.' });
      if (role && t > Date.now() + 7 * 86400e3) return res.status(400).json({ error: 'At most a week ahead.' });
      if (t > Date.now() + 60 * 86400e3) return res.status(400).json({ error: 'At most 60 days ahead.' });
      if (t > Date.now() + 30e3) at = new Date(t).toISOString();
    }
    const by = role ? `${role.name} (${role.label})` : sessionUser(req) || 'key';
    const byUser = role ? role.user_id : '';
    if (at) {
      const [row] = await sql`
        INSERT INTO notices (batch, title, body, sent_by, send_at, pushed, users, by_user)
        VALUES (${batch}, ${title}, ${body}, ${by}, ${at}::timestamptz, false, ${users}, ${byUser})
        RETURNING id, send_at`;
      return res.status(200).json({ ok: true, id: Number(row.id), scheduled: row.send_at });
    }
    const [row] = await sql`
      INSERT INTO notices (batch, title, body, sent_by, users, by_user)
      VALUES (${batch}, ${title}, ${body}, ${by}, ${users}, ${byUser})
      RETURNING id, created`;
    const pushed = await pushNotice({ id: row.id, batch, title, body, users });
    return res.status(200).json({ ok: true, id: Number(row.id), created: row.created, pushed });
  }
  if (req.method === 'DELETE') {
    const id = Number(req.query.id);
    if (!Number.isInteger(id)) return res.status(400).json({ error: 'bad id' });
    if (role) await sql`DELETE FROM notices WHERE id = ${id} AND by_user = ${role.user_id}`;
    else await sql`DELETE FROM notices WHERE id = ${id}`;
    return res.status(200).json({ ok: true });
  }
  res.setHeader('Allow', 'GET, POST, DELETE');
  return res.status(405).json({ error: 'method not allowed' });
};
