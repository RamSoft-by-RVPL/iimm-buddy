// One-time: creates the tables. Run with the project's .env.local loaded.
const fs = require('fs');
const path = require('path');
for (const l of fs.readFileSync(path.join(__dirname, '..', '.env.local'), 'utf8').split('\n')) {
  const m = l.match(/^(\w+)="?(.*?)"?$/);
  if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
}
const { sql } = require('./db');
(async () => {
  for (const stmt of fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8')
    .replace(/--.*$/gm, '').split(';').map((s) => s.trim()).filter(Boolean)) {
    await sql.query(stmt);
  }
  const t = await sql`SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY 1`;
  console.log('tables:', t.map((r) => r.table_name).join(', '));
})().catch((e) => { console.error(e.message); process.exit(1); });
