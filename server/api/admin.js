// Numbers and logs for the person who runs the app. Admin key required.
//
//   GET /api/admin               totals and the list of users
//   GET /api/admin?user=<id>     one user's details and last 500 events

const { sql, isAdmin } = require('../lib/db');

module.exports = async (req, res) => {
  if (req.method !== 'GET') return res.status(405).json({ error: 'method not allowed' });
  if (!isAdmin(req)) return res.status(401).json({ error: 'not allowed' });
  res.setHeader('Cache-Control', 'no-store');

  const id = String(req.query.user || '');
  if (id) {
    const user = await sql`SELECT * FROM users WHERE id = ${id}`;
    if (!user.length) return res.status(404).json({ error: 'no such user' });
    const events = await sql`
      SELECT at, received, kind, detail FROM events
      WHERE user_id = ${id} ORDER BY at DESC, id DESC LIMIT 500`;
    return res.status(200).json({ user: user[0], events });
  }

  const [totals] = await sql`
    SELECT count(*)::int AS users,
           count(*) FILTER (WHERE last_seen > now() - interval '1 day')::int AS active_1d,
           count(*) FILTER (WHERE last_seen > now() - interval '7 days')::int AS active_7d,
           count(*) FILTER (WHERE last_seen > now() - interval '30 days')::int AS active_30d,
           count(*) FILTER (WHERE first_seen > now() - interval '7 days')::int AS new_7d,
           count(*) FILTER (WHERE health <> '')::int AS reminders_blocked,
           count(*) FILTER (WHERE last_error <> '')::int AS with_errors
    FROM users`;
  const versions = await sql`
    SELECT app_version AS label, count(*)::int AS n FROM users GROUP BY 1 ORDER BY 2 DESC`;
  const batches = await sql`
    SELECT batch AS label, count(*)::int AS n FROM users GROUP BY 1 ORDER BY 2 DESC`;
  const makers = await sql`
    SELECT lower(split_part(device, ' ', 1)) AS label, count(*)::int AS n
    FROM users GROUP BY 1 ORDER BY 2 DESC`;
  const daily = await sql`
    SELECT to_char(date_trunc('day', received AT TIME ZONE 'Asia/Kolkata'), 'YYYY-MM-DD') AS day,
           count(DISTINCT user_id)::int AS users, count(*)::int AS events
    FROM events WHERE received > now() - interval '14 days' GROUP BY 1 ORDER BY 1`;
  const kinds = await sql`
    SELECT kind AS label, count(*)::int AS n FROM events
    WHERE received > now() - interval '7 days' GROUP BY 1 ORDER BY 2 DESC`;
  const users = await sql`
    SELECT id, roll, name, batch, app_version, device, first_seen, last_seen, last_error, health
    FROM users ORDER BY last_seen DESC LIMIT 1000`;
  const timetables = await sql`
    SELECT batch, updated, jsonb_array_length(classes) AS classes FROM timetables ORDER BY 1`;
  // Each message with how many phones said they got it, out of the phones
  // it was meant for that were active in the last week.
  const notices = (await sql`
    SELECT n.id, n.batch, n.title, n.body, n.sent_by, n.created, n.send_at, n.pushed, n.users,
      (SELECT count(DISTINCT e.user_id)::int FROM events e
        WHERE e.kind IN ('notice_got', 'notice_shown') AND e.detail = '#' || n.id) AS received,
      CASE WHEN cardinality(n.users) > 0 THEN cardinality(n.users) ELSE
      (SELECT count(*)::int FROM users u
        WHERE (n.batch = '' OR u.batch = n.batch)
          AND u.last_seen > now() - interval '7 days') END AS audience
    FROM notices n ORDER BY n.send_at DESC LIMIT 30`)
    .map((r) => ({ ...r, id: Number(r.id) }));
  const calendars = await sql`
    SELECT batch, updated, title, jsonb_array_length(events) AS events FROM calendars ORDER BY 1`;
  const menus = await sql`
    SELECT to_char(week, 'YYYY-MM-DD') AS week, updated, days FROM menus
    WHERE week >= now()::date - 14 ORDER BY week`;
  const exams = await sql`
    SELECT batch, updated, title, exams FROM exam_timetables ORDER BY 1`;
  return res.status(200).json({ totals, versions, batches, makers, daily, kinds, users, timetables, notices, calendars, menus, exams });
};
