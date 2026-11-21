// Teachers' institute email addresses, taken from the institute's Outlook
// address book, so the app can offer "Email" next to a teacher's name.
//
//   GET  /api/faculty                          anyone: {teachers:[{name, email}]}
//   POST /api/faculty {teachers:[{name, email}]}   admin: replace the list

const { sql, isAdmin, text } = require('../lib/db');

const EMAIL = /^[^\s@<>"]{1,64}@iimmumbai\.ac\.in$/i;

module.exports = async (req, res) => {
  if (req.method === 'GET') {
    res.setHeader('Cache-Control', 'public, max-age=0, s-maxage=300');
    const rows = await sql`SELECT name, email FROM faculty ORDER BY name`;
    return res.status(200).json({ teachers: rows });
  }
  if (!isAdmin(req)) return res.status(401).json({ error: 'not allowed' });
  res.setHeader('Cache-Control', 'no-store');
  if (req.method === 'POST') {
    const list = Array.isArray((req.body || {}).teachers) ? req.body.teachers : null;
    if (!list || list.length > 500) return res.status(400).json({ error: 'bad list' });
    const clean = [];
    for (const t of list) {
      const name = text(t && t.name, 120), email = text(t && t.email, 120).toLowerCase();
      if (!name || !EMAIL.test(email)) return res.status(400).json({ error: `Check the line for ${name || 'a teacher'}: only @iimmumbai.ac.in addresses.` });
      clean.push({ name, email });
    }
    await sql`DELETE FROM faculty`;
    for (const t of clean) {
      await sql`INSERT INTO faculty (name, email) VALUES (${t.name}, ${t.email}) ON CONFLICT (name) DO UPDATE SET email = EXCLUDED.email, updated = now()`;
    }
    return res.status(200).json({ ok: true, count: clean.length });
  }
  res.setHeader('Allow', 'GET, POST');
  return res.status(405).json({ error: 'method not allowed' });
};
