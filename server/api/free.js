// Free time shared between friends. A phone that turns sharing on sends a
// first name and the times it is in class, nothing else: no course, no room,
// no attendance. Whoever has its code can read those; stopping deletes them.
//
//   GET  /api/free?codes=ABCD2345,EFGH6789
//                     whoever has the codes: each one's name and class times
//                     (a code that is not shared any more is left out)
//   POST /api/free {action:'share', user, name, busy: [{d, s, e}]}
//                     a phone that uses the app: saves them, answers {code}
//   POST /api/free {action:'stop', user}
//                     deletes them; the code stops working

const crypto = require('crypto');
const { sql, text } = require('../lib/db');

const USER = /^[0-9a-f]{16}$/;
const DAY = /^\d{4}-\d{2}-\d{2}$/;
const TIME = /^\d{2}:\d{2}$/;
// No I, O, 0 or 1: a code is read out and typed in.
const LETTERS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const CODE = /^[A-HJ-NP-Z2-9]{8}$/;

// The table makes itself the first time it is needed (the same statement is
// in lib/schema.sql), so this endpoint does not wait for lib/setup.js.
let ready;
const table = () => (ready ||= sql`
  CREATE TABLE IF NOT EXISTS free_shares (
    user_id text PRIMARY KEY,
    code    text NOT NULL UNIQUE,
    name    text NOT NULL DEFAULT '',
    busy    jsonb NOT NULL,
    updated timestamptz NOT NULL DEFAULT now()
  )`.catch((e) => { ready = null; throw e; }));

const newCode = () => Array.from({ length: 8 }, () => LETTERS[crypto.randomInt(32)]).join('');

/** The cleaned class times, or null when the body is not acceptable. */
function clean(busy) {
  if (!Array.isArray(busy) || busy.length > 200) return null;
  const out = [];
  for (const b of busy) {
    if (!b || !DAY.test(b.d) || !TIME.test(b.s) || !TIME.test(b.e) || b.s >= b.e) return null;
    out.push({ d: b.d, s: b.s, e: b.e });
  }
  return out;
}

module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  await table();

  if (req.method === 'GET') {
    const codes = String(req.query.codes || '').split(',').filter(Boolean);
    if (!codes.length || codes.length > 30 || !codes.every((c) => CODE.test(c))) {
      return res.status(400).json({ error: 'bad codes' });
    }
    const rows = await sql`
      SELECT code, name, busy, updated FROM free_shares
      WHERE code = ANY(${codes}) AND updated > now() - interval '30 days'`;
    return res.status(200).json({
      friends: rows.map((r) => ({
        code: r.code, name: r.name, busy: r.busy, updated: new Date(r.updated).toISOString(),
      })),
    });
  }

  const b = req.body || {};
  const user = String(b.user || '');
  if (req.method !== 'POST' || !USER.test(user)) return res.status(400).json({ error: 'bad request' });

  if (b.action === 'stop') {
    await sql`DELETE FROM free_shares WHERE user_id = ${user}`;
    return res.status(200).json({ ok: true });
  }

  if (b.action === 'share') {
    const busy = clean(b.busy);
    if (!busy) return res.status(400).json({ error: 'bad times' });
    const name = text(b.name, 30);
    const [u] = await sql`SELECT 1 AS known FROM users WHERE id = ${user}`;
    if (!u) return res.status(403).json({ error: 'Open Crony once, then share.' });
    await sql`DELETE FROM free_shares WHERE updated < now() - interval '30 days'`;
    // A new code only the first time; it collides about never, but try again if it does.
    for (let i = 0; i < 5; i++) {
      try {
        const [row] = await sql`
          INSERT INTO free_shares (user_id, code, name, busy)
          VALUES (${user}, ${newCode()}, ${name}, ${JSON.stringify(busy)}::jsonb)
          ON CONFLICT (user_id) DO UPDATE SET name = EXCLUDED.name, busy = EXCLUDED.busy, updated = now()
          RETURNING code`;
        return res.status(200).json({ ok: true, code: row.code });
      } catch (e) {
        if (e.code !== '23505') throw e;
      }
    }
    return res.status(500).json({ error: 'Could not make a code. Try again.' });
  }
  return res.status(400).json({ error: 'unknown action' });
};

module.exports.clean = clean;
module.exports.CODE = CODE;
module.exports.newCode = newCode;
