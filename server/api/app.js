// Settings every copy of the app reads.
//
//   GET  /api/app                    anyone: {min_version}
//   POST /api/app {min_version}      admin: '' lets every version in
//
// A phone older than min_version shows only "Update Crony to continue"
// (from app version 0.8.21; older copies do not ask).

const { sql, isAdmin } = require('../lib/db');

const VERSION = /^\d{1,3}\.\d{1,3}\.\d{1,3}$/;

module.exports = async (req, res) => {
  if (req.method === 'GET') {
    res.setHeader('Cache-Control', 'public, max-age=0, s-maxage=60');
    const rows = await sql`SELECT value FROM settings WHERE key = 'min_version'`;
    return res.status(200).json({ min_version: rows.length ? rows[0].value : '' });
  }
  if (!isAdmin(req)) return res.status(401).json({ error: 'not allowed' });
  res.setHeader('Cache-Control', 'no-store');
  if (req.method === 'POST') {
    const v = String((req.body || {}).min_version || '').trim();
    if (v && !VERSION.test(v)) return res.status(400).json({ error: 'Give a version like 0.8.21, or nothing.' });
    await sql`
      INSERT INTO settings (key, value) VALUES ('min_version', ${v})
      ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated = now()`;
    return res.status(200).json({ ok: true, min_version: v });
  }
  res.setHeader('Allow', 'GET, POST');
  return res.status(405).json({ error: 'method not allowed' });
};
