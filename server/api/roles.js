// Students who may post from the app: class reps (CR), mess secretaries and
// hostel secretaries. The admin picks them from the list of app users.
//
//   GET    /api/roles                          admin: everyone who has a role
//   POST   /api/roles {action:'set', user, role, batch}
//                                             admin: give or change a role
//                                             (batch: who they post to, '' = everyone)
//   DELETE /api/roles?user=<install id>       admin: take the role away
//   POST   /api/roles {action:'me', user}     the phone: its role and token, if any
//   POST   /api/roles {action:'mine'}         a role holder (header X-Role): what
//                                             they posted in the last two weeks
//
// The phone learns its role by asking with its install id, a random name only
// that phone and the admin know. Posts then carry the token in X-Role.

const crypto = require('crypto');
const { sql, isAdmin, sessionUser, text } = require('../lib/db');
const { push } = require('../lib/push');
const { ROLES, CAN, roleOf } = require('../lib/roles');

const USER = /^[0-9a-f]{16}$/;
const BATCH = /^[a-z0-9-]{2,40}$/;

const tell = (user) => push(`user-${user}`, { data: { type: 'role' } });

module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  const b = req.body || {};

  if (req.method === 'POST' && b.action === 'me') {
    const user = String(b.user || '');
    if (!USER.test(user)) return res.status(400).json({ error: 'bad user' });
    const rows = await sql`SELECT role, batch, token FROM roles WHERE user_id = ${user}`;
    const r = rows[0];
    if (!r || !ROLES[r.role]) return res.status(200).json({ role: null });
    return res.status(200).json({
      role: r.role, label: ROLES[r.role], batch: r.batch, token: r.token, can: CAN[r.role],
    });
  }

  if (req.method === 'POST' && b.action === 'mine') {
    const me = await roleOf(req);
    if (!me) return res.status(401).json({ error: 'not allowed' });
    const notices = await sql`
      SELECT id, batch, title, body, send_at, pushed FROM notices
      WHERE by_user = ${me.user_id} AND send_at > now() - interval '14 days'
      ORDER BY send_at DESC LIMIT 30`;
    const cancelled = me.can.cancel ? await sql`
      SELECT id, to_char(d, 'YYYY-MM-DD') AS d, s, c, why FROM cancellations
      WHERE batch = ${me.batch} AND d >= (now() AT TIME ZONE 'Asia/Kolkata')::date - 1
      ORDER BY d, s, id` : [];
    return res.status(200).json({
      notices: notices.map((n) => ({ ...n, id: Number(n.id) })),
      cancelled: cancelled.map((c) => ({ ...c, id: Number(c.id) })),
    });
  }

  if (!isAdmin(req)) return res.status(401).json({ error: 'not allowed' });

  if (req.method === 'GET') {
    const roles = await sql`
      SELECT r.user_id, r.role, r.batch, r.name, r.roll, r.created, r.set_by,
             u.last_seen, u.app_version,
             (SELECT count(*)::int FROM notices n WHERE n.by_user = r.user_id) AS posts
      FROM roles r LEFT JOIN users u ON u.id = r.user_id
      ORDER BY r.role, r.name`;
    return res.status(200).json({ roles, kinds: ROLES });
  }

  if (req.method === 'POST' && b.action === 'set') {
    const user = String(b.user || '');
    const role = String(b.role || '');
    const batch = text(b.batch, 40).toLowerCase();
    if (!USER.test(user)) return res.status(400).json({ error: 'Pick a person from the list.' });
    if (!ROLES[role]) return res.status(400).json({ error: 'Pick a role.' });
    if (batch && !BATCH.test(batch)) return res.status(400).json({ error: 'bad batch' });
    if (role === 'cr' && !batch) return res.status(400).json({ error: 'A CR posts to one batch: fill in the batch.' });
    const [u] = await sql`SELECT name, roll FROM users WHERE id = ${user}`;
    if (!u) return res.status(400).json({ error: 'That person has not used the app yet.' });
    const token = crypto.randomBytes(24).toString('hex');
    await sql`
      INSERT INTO roles (user_id, role, batch, name, roll, token, set_by)
      VALUES (${user}, ${role}, ${batch}, ${u.name}, ${u.roll}, ${token}, ${sessionUser(req) || 'key'})
      ON CONFLICT (user_id) DO UPDATE SET role = EXCLUDED.role, batch = EXCLUDED.batch,
        name = EXCLUDED.name, roll = EXCLUDED.roll, set_by = EXCLUDED.set_by`;
    const pushed = await tell(user);
    return res.status(200).json({ ok: true, pushed });
  }

  if (req.method === 'DELETE') {
    const user = String(req.query.user || '');
    if (!USER.test(user)) return res.status(400).json({ error: 'bad user' });
    await sql`DELETE FROM roles WHERE user_id = ${user}`;
    await tell(user);
    return res.status(200).json({ ok: true });
  }
  return res.status(400).json({ error: 'unknown action' });
};
