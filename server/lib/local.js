// Runs the admin page and the real API handlers on this machine for testing:
//   node lib/local.js [port]
// Sign-in is skipped (every request counts as the admin unless it carries
// X-Role or X-Guest), so never expose
// this beyond localhost. It talks to the real database: use a test batch.
const fs = require('fs');
const http = require('http');
const path = require('path');
const root = path.join(__dirname, '..');
for (const l of fs.readFileSync(path.join(root, '.env.local'), 'utf8').split('\n')) {
  const m = l.match(/^(\w+)="?(.*?)"?$/);
  if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
}
process.env.ADMIN_KEY = 'local-only';
const port = Number(process.argv[2] || 8792);

http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${port}`);
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const raw = Buffer.concat(chunks);
  res.status = (c) => { res.statusCode = c; return res; };
  res.json = (o) => { res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify(o)); };
  try {
    if (url.pathname === '/api/auth' && req.method === 'GET') {
      return res.json({ signedIn: true, user: 'local test', hasAdmin: true });
    }
    if (url.pathname.startsWith('/api/')) {
      const file = path.join(root, 'api', url.pathname.slice(5) + '.js');
      if (!fs.existsSync(file)) return res.status(404).json({ error: 'no such endpoint' });
      req.query = Object.fromEntries(url.searchParams);
      // A request acting as a student (X-Role) or as nobody (X-Guest) is not the admin.
      if (!req.headers['x-role'] && !req.headers['x-guest']) req.headers.authorization = 'Bearer local-only';
      const type = req.headers['content-type'] || '';
      req.body = type.includes('json') ? JSON.parse(raw.toString() || '{}') : raw;
      return await require(file)(req, res);
    }
    const name = url.pathname === '/admin' || url.pathname === '/' ? 'admin.html' : url.pathname.slice(1);
    const f = path.join(root, 'public', path.basename(name));
    if (!fs.existsSync(f)) return res.status(404).end('not found');
    res.setHeader('Content-Type', f.endsWith('.html') ? 'text/html; charset=utf-8' : 'application/octet-stream');
    res.end(fs.readFileSync(f));
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
}).listen(port, '127.0.0.1', () => console.log('local admin on http://127.0.0.1:' + port + '/admin'));
