// Sends push messages through Firebase Cloud Messaging (free). The app on
// each phone listens to two topics: "all" and "batch-<its batch>".
//
// The service-account key is in FCM_SERVICE_ACCOUNT (base64 of the JSON).
// Nothing here throws: a failed push only means phones find out at their
// next regular check instead of at once.

const crypto = require('crypto');

let cached = null; // { token, until }

function account() {
  const raw = process.env.FCM_SERVICE_ACCOUNT;
  if (!raw) return null;
  try {
    return JSON.parse(Buffer.from(raw, 'base64').toString());
  } catch (e) {
    return null;
  }
}

async function accessToken(acc) {
  if (cached && cached.until > Date.now() + 60e3) return cached.token;
  const now = Math.floor(Date.now() / 1000);
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const unsigned = `${b64({ alg: 'RS256', typ: 'JWT' })}.${b64({
    iss: acc.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  })}`;
  const sig = crypto.createSign('RSA-SHA256').update(unsigned).sign(acc.private_key, 'base64url');
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${sig}`,
    }),
  });
  const j = await r.json();
  if (!r.ok) throw new Error(`token: ${j.error_description || r.status}`);
  cached = { token: j.access_token, until: Date.now() + j.expires_in * 1000 };
  return cached.token;
}

/** The topic for a batch ('' = everyone). */
const topicFor = (batch) => (batch ? `batch-${batch}` : 'all');

/**
 * Sends one message to a topic. [show] ({title, body}) makes the phone
 * display it by itself even if the app cannot run; [data] always reaches
 * the app so it can fetch what changed. Returns {ok, error}.
 */
async function push(topic, { show, data }) {
  const acc = account();
  if (!acc) return { ok: false, error: 'push is not set up' };
  try {
    const message = {
      topic,
      data: Object.fromEntries(Object.entries(data || {}).map(([k, v]) => [k, String(v)])),
      android: { priority: 'HIGH', ttl: '86400s' },
    };
    if (show) {
      message.notification = { title: show.title, body: show.body || '' };
      message.android.notification = { channel_id: 'news' };
    }
    const r = await fetch(`https://fcm.googleapis.com/v1/projects/${acc.project_id}/messages:send`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${await accessToken(acc)}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ message }),
    });
    if (r.ok) return { ok: true };
    const j = await r.json().catch(() => ({}));
    return { ok: false, error: (j.error && j.error.message) || `FCM answered ${r.status}` };
  } catch (e) {
    return { ok: false, error: e.message };
  }
}

/**
 * Pushes one message to the phones it is for: chosen people (by install id),
 * else its batch or everyone. Returns the first failure, or {ok: true}.
 */
async function pushNotice(n) {
  const message = { show: { title: n.title, body: n.body }, data: { type: 'notice', id: Number(n.id) } };
  const topics = n.users && n.users.length ? n.users.map((u) => `user-${u}`) : [topicFor(n.batch)];
  let out = { ok: true };
  for (const t of topics) {
    const r = await push(t, message);
    if (!r.ok && out.ok) out = r;
  }
  return out;
}

/**
 * Pushes every message whose time has come and that has not gone out yet.
 * Called whenever a phone talks to the server, so no timer is needed.
 * Each message is claimed first, so two requests never send it twice.
 */
async function sendDue(sql) {
  try {
    const due = await sql`
      UPDATE notices SET pushed = true
      WHERE pushed = false AND send_at <= now()
      RETURNING id, batch, title, body, users`;
    for (const n of due) await pushNotice(n);
    return due.length;
  } catch (e) {
    return 0;
  }
}

module.exports = { push, topicFor, sendDue, pushNotice };
