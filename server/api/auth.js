// Sign-in for the admin page.
//
//   GET  /api/auth                                  {signedIn, user, hasAdmin}
//   POST /api/auth {action:'login', username, password}
//   POST /api/auth {action:'setup', key, username, password}   first time, or to
//        change the password: needs the publisher key
//   POST /api/auth {action:'logout'}

const crypto = require('crypto');
const { sql, hasKey, same, sessionCookie, clearCookie, sessionUser, hashPassword, text } = require('../lib/db');

const USER = /^[a-z0-9._-]{3,30}$/;

module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method === 'GET') {
    const [{ n }] = await sql`SELECT count(*)::int AS n FROM admins`;
    const user = sessionUser(req);
    return res.status(200).json({ signedIn: user !== null, user, hasAdmin: n > 0 });
  }
  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });
  const b = req.body || {};
  const username = text(b.username, 30).toLowerCase();
  const password = typeof b.password === 'string' ? b.password : '';

  if (b.action === 'logout') {
    res.setHeader('Set-Cookie', clearCookie);
    return res.status(200).json({ ok: true });
  }

  if (b.action === 'setup') {
    if (!hasKey(req, text(b.key, 200))) return res.status(401).json({ error: 'The publisher key is wrong.' });
    if (!USER.test(username)) return res.status(400).json({ error: 'Username: 3 to 30 small letters, numbers, dots or dashes.' });
    if (password.length < 8 || password.length > 200) return res.status(400).json({ error: 'Password: at least 8 characters.' });
    const salt = crypto.randomBytes(16).toString('hex');
    await sql`
      INSERT INTO admins (username, salt, hash) VALUES (${username}, ${salt}, ${hashPassword(password, salt)})
      ON CONFLICT (username) DO UPDATE SET salt = EXCLUDED.salt, hash = EXCLUDED.hash`;
    await sql`DELETE FROM login_fails WHERE username = ${username}`;
    res.setHeader('Set-Cookie', sessionCookie(username));
    return res.status(200).json({ ok: true, user: username });
  }

  if (b.action === 'login') {
    const bad = () => res.status(401).json({ error: 'Wrong username or password.' });
    if (!USER.test(username) || !password) return bad();
    const [{ n }] = await sql`
      SELECT count(*)::int AS n FROM login_fails
      WHERE username = ${username} AND at > now() - interval '15 minutes'`;
    if (n >= 8) return res.status(429).json({ error: 'Too many wrong tries. Wait 15 minutes.' });
    const rows = await sql`SELECT salt, hash FROM admins WHERE username = ${username}`;
    // Same work whether or not the user exists.
    const salt = rows.length ? rows[0].salt : '00';
    const ok = same(hashPassword(password, salt), rows.length ? rows[0].hash : 'x');
    if (!rows.length || !ok) {
      await sql`INSERT INTO login_fails (username) VALUES (${username})`;
      if (Math.random() < 0.05) await sql`DELETE FROM login_fails WHERE at < now() - interval '1 day'`;
      return bad();
    }
    res.setHeader('Set-Cookie', sessionCookie(username));
    return res.status(200).json({ ok: true, user: username });
  }
  return res.status(400).json({ error: 'unknown action' });
};
