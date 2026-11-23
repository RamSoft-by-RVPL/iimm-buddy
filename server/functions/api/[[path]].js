// Runs the API on Cloudflare Pages. Each /api/<name> request goes to the
// same handler in api/<name>.js that Vercel ran, through a small stand-in
// for the (req, res) objects those handlers expect.

// Loaded on first use, after the settings are in process.env (lib/db.js
// reads DATABASE_URL as soon as it loads).
const handlers = {
  admin: () => require('../../api/admin.js'),
  app: () => require('../../api/app.js'),
  auth: () => require('../../api/auth.js'),
  'calendar-doc': () => require('../../api/calendar-doc.js'),
  calendar: () => require('../../api/calendar.js'),
  cancelled: () => require('../../api/cancelled.js'),
  exams: () => require('../../api/exams.js'),
  log: () => require('../../api/log.js'),
  extra: () => require('../../api/extra.js'),
  faculty: () => require('../../api/faculty.js'),
  menu: () => require('../../api/menu.js'),
  notices: () => require('../../api/notices.js'),
  poke: () => require('../../api/poke.js'),
  polls: () => require('../../api/polls.js'),
  sheet: () => require('../../api/sheet.js'),
  roles: () => require('../../api/roles.js'),
  uploads: () => require('../../api/uploads.js'),
  timetable: () => require('../../api/timetable.js'),
};

const json = (status, o) => new Response(JSON.stringify(o), {
  status,
  headers: { 'Content-Type': 'application/json; charset=utf-8' },
});

async function readBody(request) {
  if (request.method === 'GET' || request.method === 'HEAD') return undefined;
  const raw = Buffer.from(await request.arrayBuffer());
  const type = request.headers.get('content-type') || '';
  if (type.includes('application/json')) {
    if (!raw.length) return {};
    return JSON.parse(raw.toString('utf8'));
  }
  if (type.includes('application/x-www-form-urlencoded')) {
    return Object.fromEntries(new URLSearchParams(raw.toString('utf8')));
  }
  if (type.startsWith('text/')) return raw.toString('utf8');
  return raw;
}

export async function onRequest({ request, env, params }) {
  for (const [k, v] of Object.entries(env)) {
    if (typeof v === 'string') process.env[k] = v;
  }
  const name = [].concat(params.path || []).join('/');
  const load = handlers[name];
  if (!load) return json(404, { error: 'no such endpoint' });

  const url = new URL(request.url);
  let body;
  try {
    body = await readBody(request);
  } catch (e) {
    return json(400, { error: 'invalid JSON' });
  }
  const query = {};
  for (const [k, v] of url.searchParams) {
    query[k] = k in query ? [].concat(query[k], v) : v;
  }
  const req = {
    method: request.method,
    url: url.pathname + url.search,
    headers: Object.fromEntries(request.headers),
    query,
    body,
  };

  let status = 200;
  let sent = null;
  const headers = new Headers();
  const res = {
    get statusCode() { return status; },
    set statusCode(c) { status = c; },
    status(c) { status = c; return res; },
    setHeader(k, v) {
      headers.delete(k);
      for (const one of [].concat(v)) headers.append(k, String(one));
      return res;
    },
    getHeader: (k) => headers.get(k) ?? undefined,
    json(o) {
      if (!headers.has('content-type')) headers.set('Content-Type', 'application/json; charset=utf-8');
      sent = JSON.stringify(o);
      return res;
    },
    send(x) {
      if (x !== null && typeof x === 'object' && !Buffer.isBuffer(x) && !(x instanceof Uint8Array)) return res.json(x);
      sent = x ?? '';
      return res;
    },
    end(x) { sent = x ?? ''; return res; },
  };

  try {
    await load()(req, res);
  } catch (e) {
    console.error(`/api/${name}: ${e.stack || e.message}`);
    return json(500, { error: 'server error' });
  }
  const noBody = status === 204 || status === 304 || request.method === 'HEAD';
  return new Response(noBody ? null : sent ?? '', { status, headers });
}
