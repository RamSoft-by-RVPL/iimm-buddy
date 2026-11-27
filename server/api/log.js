// The app's diagnostic log.
//
//   POST /api/log   {id, roll, name, batch, version, device, health, events:[{t, k, d}]}
//
// Any copy of the app may write its own log. Reading is admin only
// (see api/admin.js). Events older than 30 days are removed.

const { sql, text } = require('../lib/db');
const { sendDue } = require('../lib/push');

const ID = /^[a-f0-9]{16,32}$/;
const KIND = /^[a-z_]{2,30}$/;

module.exports = async (req, res) => {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'method not allowed' });
  }
  const b = req.body || {};
  if (!ID.test(String(b.id || ''))) return res.status(400).json({ error: 'bad id' });
  if (!Array.isArray(b.events) || b.events.length > 300) {
    return res.status(400).json({ error: 'bad events' });
  }
  // Versions were renamed from 1.x to 0.x; older builds still say 1.x.
  const renamed = (v) => String(v || '').replace(/^1\.(\d+\.\d+)$/, '0.$1');
  b.version = renamed(b.version);
  const now = Date.now();
  const kinds = [], details = [], times = [];
  const open = new Map();
  let sawOk = false;
  for (const e of b.events) {
    const kind = text(e && e.k, 30);
    const at = Date.parse(e && e.t);
    if (!KIND.test(kind) || Number.isNaN(at)) continue;
    // A phone with a wrong clock must not write far-off times.
    times.push(new Date(Math.min(Math.max(at, now - 40 * 86400e3), now + 600e3)).toISOString());
    kinds.push(kind);
    const detail = text(e.d, 400);
    details.push(detail);
    // A later success of the same kind clears the error ("sync", "moodle"...).
    const family = kind.replace(/^bg_/, '').replace(/_(ok|fail)$/, '');
    if (kind.endsWith('_fail')) open.set(family, `${kind}: ${detail}`.slice(0, 400));
    else if (kind.endsWith('_ok')) { open.delete(family); sawOk = true; }
  }

  // null = leave what is stored; '' = everything that failed works again.
  const lastError = open.size ? [...open.values()].pop() : (sawOk ? '' : null);

  await sql`
    INSERT INTO users (id, roll, name, batch, app_version, device, health, last_error, app)
    VALUES (${b.id}, ${text(b.roll, 30)}, ${text(b.name, 80)}, ${text(b.batch, 40)},
            ${text(b.version, 20)}, ${text(b.device, 80)}, ${text(b.health, 200)},
            ${lastError || ''}, ${text(b.app, 60)})
    ON CONFLICT (id) DO UPDATE SET
      roll = CASE WHEN EXCLUDED.roll <> '' THEN EXCLUDED.roll ELSE users.roll END,
      name = CASE WHEN EXCLUDED.name <> '' THEN EXCLUDED.name ELSE users.name END,
      batch = CASE WHEN EXCLUDED.batch <> '' THEN EXCLUDED.batch ELSE users.batch END,
      app_version = EXCLUDED.app_version,
      device = CASE WHEN EXCLUDED.device <> '' THEN EXCLUDED.device ELSE users.device END,
      app = CASE WHEN EXCLUDED.app <> '' THEN EXCLUDED.app ELSE users.app END,
      health = EXCLUDED.health,
      last_error = CASE WHEN ${lastError !== null} THEN EXCLUDED.last_error ELSE users.last_error END,
      last_seen = now()`;

  // The same student on the same phone under a new id: the app was
  // reinstalled or its data cleared. Keep only this copy (its role moves
  // with it), so the admin page lists each student's phone once.
  // The Play app and the site's app can sit side by side on one phone: those
  // are two copies, not a reinstall, so only the same app is matched (phones
  // before 0.9.2 do not say which app they are).
  const roll = text(b.roll, 30), device = text(b.device, 80), app = text(b.app, 60);
  if (roll && device) {
    const old = (await sql`
      SELECT id FROM users
      WHERE roll = ${roll} AND device = ${device} AND id <> ${b.id}
        AND app = ${app}`).map((r) => r.id);
    if (old.length) {
      // Keep the date Crony first saw this student (the admin's serial number).
      await sql`
        UPDATE users SET first_seen = LEAST(first_seen,
          (SELECT min(first_seen) FROM users WHERE id = ANY(${old})))
        WHERE id = ${b.id}`;
      await sql`
        UPDATE roles SET user_id = ${b.id}
        WHERE user_id = ${old[0]} AND NOT EXISTS (SELECT 1 FROM roles WHERE user_id = ${b.id})`;
      await sql`DELETE FROM roles WHERE user_id = ANY(${old})`;
      await sql`DELETE FROM events WHERE user_id = ANY(${old})`;
      await sql`DELETE FROM users WHERE id = ANY(${old})`;
    }
  }

  if (kinds.length) {
    await sql`
      INSERT INTO events (user_id, at, kind, detail)
      SELECT ${b.id}, t::timestamptz, k, d
      FROM unnest(${times}::text[], ${kinds}::text[], ${details}::text[]) AS x(t, k, d)`;
  }
  // Tidy up now and then instead of on every request.
  if (Math.random() < 0.02) {
    await sql`DELETE FROM events WHERE received < now() - interval '30 days'`;
  }
  await sendDue(sql); // messages set for a time that has now come
  return res.status(200).json({ ok: true, stored: kinds.length });
};
