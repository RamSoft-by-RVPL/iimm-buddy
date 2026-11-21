// Files a mess secretary sends in from the app (the week's menu as a photo
// or PDF). The admin downloads them from the admin page and publishes the
// menu the usual way.
//
//   POST   /api/uploads {name, mime, data (base64), note}
//                                   a role holder who may upload (header X-Role)
//   GET    /api/uploads             admin: the last 30, without the files
//   GET    /api/uploads?id=12       admin: the file itself
//   POST   /api/uploads {action:'done', id, done}   admin: mark it dealt with

const { sql, isAdmin, text } = require('../lib/db');
const { roleOf } = require('../lib/roles');

const TYPES = /^(image\/(jpeg|png|webp|heic|heif)|application\/pdf)$/;
const MAX = 10 * 1024 * 1024;

module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  const b = req.body || {};
  const admin = isAdmin(req);

  if (req.method === 'POST' && !b.action) {
    const role = admin ? null : await roleOf(req);
    if (!role || !role.can.upload) return res.status(401).json({ error: 'not allowed' });
    const mime = String(b.mime || '').toLowerCase();
    if (!TYPES.test(mime)) return res.status(400).json({ error: 'Send a photo or a PDF.' });
    const data = Buffer.from(String(b.data || ''), 'base64');
    if (!data.length) return res.status(400).json({ error: 'The file is empty.' });
    if (data.length > MAX) return res.status(400).json({ error: 'The file is over 10 MB.' });
    const [{ n }] = await sql`
      SELECT count(*)::int AS n FROM uploads WHERE by_user = ${role.user_id} AND created > now() - interval '1 day'`;
    if (n >= 10) return res.status(429).json({ error: 'At most 10 files a day.' });
    const [row] = await sql`
      INSERT INTO uploads (by_user, sent_by, name, mime, size, note, data)
      VALUES (${role.user_id}, ${`${role.name} (${role.label})`}, ${text(b.name, 120)}, ${mime},
        ${data.length}, ${text(b.note, 300)}, ${'\\x' + data.toString('hex')}::bytea)
      RETURNING id`;
    return res.status(200).json({ ok: true, id: Number(row.id) });
  }

  if (!admin) return res.status(401).json({ error: 'not allowed' });

  if (req.method === 'GET' && req.query.id) {
    const id = Number(req.query.id);
    if (!Number.isInteger(id)) return res.status(400).json({ error: 'bad id' });
    const rows = await sql`SELECT name, mime, encode(data, 'base64') AS data FROM uploads WHERE id = ${id}`;
    if (!rows.length) return res.status(404).json({ error: 'not found' });
    const name = (rows[0].name || `upload-${id}`).replace(/[^\w.\- ]+/g, '_');
    res.setHeader('Content-Type', rows[0].mime || 'application/octet-stream');
    res.setHeader('Content-Disposition', `inline; filename="${name}"`);
    return res.status(200).send(Buffer.from(rows[0].data, 'base64'));
  }
  if (req.method === 'GET') {
    const rows = await sql`
      SELECT id, kind, sent_by, name, mime, size, note, created, done
      FROM uploads ORDER BY created DESC LIMIT 30`;
    return res.status(200).json({ uploads: rows.map((r) => ({ ...r, id: Number(r.id) })) });
  }
  if (req.method === 'POST' && b.action === 'done') {
    const id = Number(b.id);
    if (!Number.isInteger(id)) return res.status(400).json({ error: 'bad id' });
    await sql`UPDATE uploads SET done = ${b.done !== false} WHERE id = ${id}`;
    return res.status(200).json({ ok: true });
  }
  return res.status(400).json({ error: 'unknown action' });
};
