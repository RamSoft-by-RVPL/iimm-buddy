// Students the admin lets post from the app.
const { sql } = require('./db');

const ROLES = { cr: 'CR', mess: 'Mess Secretary', hostel: 'Hostel Secretary' };

/** What each role may do. */
const CAN = {
  cr: { notice: true, cancel: true, calendar: true, poll: true },
  mess: { notice: true, cancel: false, calendar: false, poll: true, upload: true },
  hostel: { notice: true, cancel: false, calendar: false, poll: true },
};

/** The role row of the phone that sent [req] (header X-Role), or null. */
async function roleOf(req) {
  const t = String(req.headers['x-role'] || '');
  if (!/^[0-9a-f]{48}$/.test(t)) return null;
  const rows = await sql`SELECT user_id, role, batch, name, roll FROM roles WHERE token = ${t}`;
  if (!rows.length || !ROLES[rows[0].role]) return null;
  return { ...rows[0], label: ROLES[rows[0].role], can: CAN[rows[0].role] };
}

module.exports = { ROLES, CAN, roleOf };
