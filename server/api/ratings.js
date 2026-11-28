// Meal ratings: one tap after a meal, 1 (poor) to 3 (good).
//
//   GET  /api/ratings?user=<install id>
//                     anyone: every meal of the last week that has a rating,
//                     with the count, the average and this phone's own
//   GET  /api/ratings?all=1
//                     admin: the same for the last 30 days
//   POST /api/ratings {action:'rate', user, d, meal, score}
//                     a phone that uses the app rates a meal of today or
//                     yesterday that is on the menu (again to change it)

const { sql, isAdmin, text } = require('../lib/db');

const USER = /^[0-9a-f]{16}$/;
const DAY = /^\d{4}-\d{2}-\d{2}$/;

// The table makes itself the first time it is needed (the same statement is
// in lib/schema.sql), so this endpoint does not wait for lib/setup.js.
let ready;
const table = () => (ready ||= sql`
  CREATE TABLE IF NOT EXISTS meal_ratings (
    d       date NOT NULL,
    meal    text NOT NULL,
    user_id text NOT NULL,
    score   smallint NOT NULL,
    at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (d, meal, user_id)
  )`.catch((e) => { ready = null; throw e; }));

async function listFor(user, days) {
  const rows = await sql`
    SELECT to_char(d, 'YYYY-MM-DD') AS d, meal, count(*)::int AS n,
      round(avg(score)::numeric, 2)::float AS avg,
      max(score) FILTER (WHERE user_id = ${user}) AS mine
    FROM meal_ratings
    WHERE d >= (now() AT TIME ZONE 'Asia/Kolkata')::date - ${days}::int
    GROUP BY d, meal ORDER BY d, meal`;
  return rows.map((r) => ({
    d: r.d, meal: r.meal, n: r.n, avg: Number(r.avg),
    mine: r.mine === null || r.mine === undefined ? null : Number(r.mine),
  }));
}

module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  await table();

  if (req.method === 'GET') {
    if (req.query.all && isAdmin(req)) {
      return res.status(200).json({ ratings: await listFor('', 30) });
    }
    const user = String(req.query.user || '');
    if (user && !USER.test(user)) return res.status(400).json({ error: 'bad user' });
    return res.status(200).json({ ratings: await listFor(user, 7) });
  }

  const b = req.body || {};
  if (req.method === 'POST' && b.action === 'rate') {
    const user = String(b.user || '');
    const d = String(b.d || '');
    const meal = text(b.meal, 30);
    const score = Number(b.score);
    if (!USER.test(user) || !DAY.test(d) || !meal || ![1, 2, 3].includes(score)) {
      return res.status(400).json({ error: 'bad rating' });
    }
    const [now] = await sql`
      SELECT to_char((now() AT TIME ZONE 'Asia/Kolkata')::date, 'YYYY-MM-DD') AS today,
        to_char((now() AT TIME ZONE 'Asia/Kolkata')::date - 1, 'YYYY-MM-DD') AS yesterday,
        (SELECT days FROM menus WHERE week <= ${d}::date AND week > ${d}::date - 7
          ORDER BY week DESC LIMIT 1) AS days,
        EXISTS (SELECT 1 FROM users WHERE id = ${user}) AS known`;
    // Only phones that use the app, and only a meal that was just served.
    if (!now.known) return res.status(403).json({ error: 'Open Crony once, then rate.' });
    if (d !== now.today && d !== now.yesterday) {
      return res.status(400).json({ error: 'Only today\'s and yesterday\'s meals can be rated.' });
    }
    const day = (now.days || []).find((x) => x.d === d);
    if (!day || !day.meals.some((m) => m.n === meal)) {
      return res.status(400).json({ error: 'That meal is not on the menu.' });
    }
    await sql`
      INSERT INTO meal_ratings (d, meal, user_id, score) VALUES (${d}, ${meal}, ${user}, ${score})
      ON CONFLICT (d, meal, user_id) DO UPDATE SET score = EXCLUDED.score, at = now()`;
    await sql`DELETE FROM meal_ratings WHERE d < now()::date - 120`;
    return res.status(200).json({ ok: true, ratings: await listFor(user, 7) });
  }

  res.setHeader('Allow', 'GET, POST');
  return res.status(400).json({ error: 'unknown action' });
};
