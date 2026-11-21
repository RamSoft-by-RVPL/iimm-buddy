// Quick polls: "Shift Friday's class to Saturday?", "Rate today's dinner".
//
//   GET    /api/polls?batch=bs-2026-2030&user=<install id>
//                     anyone: polls of the last two weeks for that batch or
//                     everyone, with the votes so far and this phone's vote
//   POST   /api/polls {action:'vote', poll, user, choice}
//                     a phone that uses the app votes (again, while open)
//   POST   /api/polls {action:'create', question, options, hours, batch}
//                     admin, or a role holder (header X-Role) for the people
//                     their role covers; also sends a notification
//   POST   /api/polls {action:'close', poll}    its maker or the admin
//   DELETE /api/polls?id=12                     its maker or the admin

const { sql, isAdmin, sessionUser, text } = require('../lib/db');
const { pushNotice } = require('../lib/push');
const { roleOf } = require('../lib/roles');

const BATCH = /^[a-z0-9-]{2,40}$/;
const USER = /^[0-9a-f]{16}$/;

async function listFor(batch, user) {
  const polls = await sql`
    SELECT p.id, p.batch, p.question, p.options, p.sent_by, p.created, p.closes, p.closed,
      (p.closed OR p.closes <= now()) AS ended,
      COALESCE((SELECT json_agg(json_build_object('c', v.choice, 'n', v.n)) FROM
        (SELECT choice, count(*)::int AS n FROM poll_votes WHERE poll_id = p.id GROUP BY choice) v), '[]') AS counts,
      (SELECT choice FROM poll_votes WHERE poll_id = p.id AND user_id = ${user}) AS mine
    FROM polls p
    WHERE (p.batch = '' OR p.batch = ${batch}) AND p.created > now() - interval '14 days'
    ORDER BY p.created DESC LIMIT 20`;
  return polls.map(shape);
}

function shape(p) {
  const votes = p.options.map(() => 0);
  for (const x of p.counts || []) if (x.c >= 0 && x.c < votes.length) votes[x.c] = x.n;
  return {
    id: Number(p.id), batch: p.batch, question: p.question, options: p.options, votes,
    total: votes.reduce((a, b) => a + b, 0), from: p.sent_by, created: p.created,
    closes: p.closes, open: !p.ended, mine: p.mine === null || p.mine === undefined ? null : p.mine,
  };
}

module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  const b = req.body || {};

  if (req.method === 'GET') {
    const batch = String(req.query.batch || '').toLowerCase();
    if (batch && !BATCH.test(batch)) return res.status(400).json({ error: 'bad batch' });
    const user = String(req.query.user || '');
    if (user && !USER.test(user)) return res.status(400).json({ error: 'bad user' });
    if (isAdmin(req) && req.query.all) {
      const rows = await sql`
        SELECT p.*, (p.closed OR p.closes <= now()) AS ended,
          COALESCE((SELECT json_agg(json_build_object('c', v.choice, 'n', v.n)) FROM
            (SELECT choice, count(*)::int AS n FROM poll_votes WHERE poll_id = p.id GROUP BY choice) v), '[]') AS counts,
          NULL AS mine
        FROM polls p ORDER BY p.created DESC LIMIT 30`;
      return res.status(200).json({ polls: rows.map(shape) });
    }
    return res.status(200).json({ polls: await listFor(batch, user) });
  }

  if (req.method === 'POST' && b.action === 'vote') {
    const user = String(b.user || '');
    const id = Number(b.poll), choice = Number(b.choice);
    if (!USER.test(user) || !Number.isInteger(id) || !Number.isInteger(choice)) {
      return res.status(400).json({ error: 'bad vote' });
    }
    const [p] = await sql`
      SELECT batch, options, (closed OR closes <= now()) AS ended FROM polls WHERE id = ${id}`;
    if (!p) return res.status(404).json({ error: 'That poll is gone.' });
    if (p.ended) return res.status(400).json({ error: 'This poll has closed.' });
    if (choice < 0 || choice >= p.options.length) return res.status(400).json({ error: 'bad choice' });
    // Only phones that use the app, and for a batch's poll only that batch.
    const [u] = await sql`SELECT batch FROM users WHERE id = ${user}`;
    if (!u || (p.batch && u.batch !== p.batch)) return res.status(403).json({ error: 'This poll is not for you.' });
    await sql`
      INSERT INTO poll_votes (poll_id, user_id, choice) VALUES (${id}, ${user}, ${choice})
      ON CONFLICT (poll_id, user_id) DO UPDATE SET choice = EXCLUDED.choice, at = now()`;
    return res.status(200).json({ ok: true, polls: await listFor(u.batch, user) });
  }

  const admin = isAdmin(req);
  const role = admin ? null : await roleOf(req);
  if (!admin && !(role && role.can.poll)) return res.status(401).json({ error: 'not allowed' });

  if (req.method === 'POST' && b.action === 'create') {
    const question = text(b.question, 140);
    const options = Array.isArray(b.options) ? b.options.map((o) => text(o, 60)).filter(Boolean) : [];
    const hours = Math.round(Number(b.hours) || 24);
    if (!question) return res.status(400).json({ error: 'Write the question.' });
    if (options.length < 2 || options.length > 6 || new Set(options).size !== options.length) {
      return res.status(400).json({ error: 'Give 2 to 6 different answers.' });
    }
    if (hours < 1 || hours > 24 * 14) return res.status(400).json({ error: 'Open for 1 hour to 2 weeks.' });
    let batch = text(b.batch, 40).toLowerCase();
    if (batch && !BATCH.test(batch)) return res.status(400).json({ error: 'bad batch' });
    if (role) {
      batch = role.batch;
      const [{ n }] = await sql`
        SELECT count(*)::int AS n FROM notices
        WHERE by_user = ${role.user_id} AND created > now() - interval '1 day'`;
      if (n >= 10) return res.status(429).json({ error: 'At most 10 posts a day. Try again tomorrow.' });
    }
    const by = role ? `${role.name} (${role.label})` : sessionUser(req) || 'key';
    const byUser = role ? role.user_id : '';
    const [p] = await sql`
      INSERT INTO polls (batch, question, options, by_user, sent_by, closes)
      VALUES (${batch}, ${question}, ${JSON.stringify(options)}::jsonb, ${byUser},
        ${role ? role.label : ''}, now() + make_interval(hours => ${hours}))
      RETURNING id`;
    // Everyone hears about it the usual way; the app shows the poll itself.
    const title = `${role ? role.label + ' poll' : 'Poll'}: ${question}`.slice(0, 120);
    const body = `Open Crony to vote: ${options.join(' / ')}`.slice(0, 500);
    const [n] = await sql`
      INSERT INTO notices (batch, title, body, sent_by, by_user)
      VALUES (${batch}, ${title}, ${body}, ${by}, ${byUser}) RETURNING id`;
    const pushed = await pushNotice({ id: n.id, batch, title, body, users: [] });
    return res.status(200).json({ ok: true, id: Number(p.id), pushed });
  }

  if (req.method === 'POST' && b.action === 'close') {
    const id = Number(b.poll);
    if (!Number.isInteger(id)) return res.status(400).json({ error: 'bad poll' });
    if (role) await sql`UPDATE polls SET closed = true WHERE id = ${id} AND by_user = ${role.user_id}`;
    else await sql`UPDATE polls SET closed = true WHERE id = ${id}`;
    return res.status(200).json({ ok: true });
  }

  if (req.method === 'DELETE') {
    const id = Number(req.query.id);
    if (!Number.isInteger(id)) return res.status(400).json({ error: 'bad id' });
    if (role) await sql`DELETE FROM polls WHERE id = ${id} AND by_user = ${role.user_id}`;
    else await sql`DELETE FROM polls WHERE id = ${id}`;
    return res.status(200).json({ ok: true });
  }
  return res.status(400).json({ error: 'unknown action' });
};
