// Database access and the checks shared by every endpoint.
const crypto = require('crypto');
const { neon } = require('@neondatabase/serverless');

const sql = neon(process.env.DATABASE_URL);

function same(a, b) {
  const x = crypto.createHash('sha256').update(String(a)).digest();
  const y = crypto.createHash('sha256').update(String(b)).digest();
  return crypto.timingSafeEqual(x, y);
}

/** True when the request carries the publisher key (used by the app). */
function hasKey(req, given) {
  const key = process.env.ADMIN_KEY;
  const g = given !== undefined
    ? given
    : (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  return Boolean(key && g && same(g, key));
}

// ---- sign-in for the admin page: a signed cookie, valid for 30 days.
const DAYS = 30;
const secret = () => crypto.createHash('sha256').update('session:' + (process.env.ADMIN_KEY || '')).digest();
const sign = (body) => crypto.createHmac('sha256', secret()).update(body).digest('base64url');

function sessionCookie(username) {
  const body = Buffer.from(JSON.stringify({ u: username, e: Date.now() + DAYS * 86400e3 })).toString('base64url');
  return `sid=${body}.${sign(body)}; Path=/; Max-Age=${DAYS * 86400}; HttpOnly; Secure; SameSite=Strict`;
}
const clearCookie = 'sid=; Path=/; Max-Age=0; HttpOnly; Secure; SameSite=Strict';

/** The signed-in admin's username, or null. */
function sessionUser(req) {
  const m = /(?:^|;\s*)sid=([^;]+)/.exec(req.headers.cookie || '');
  if (!m || !process.env.ADMIN_KEY) return null;
  const [body, mac] = m[1].split('.');
  if (!body || !mac || !same(mac, sign(body))) return null;
  try {
    const p = JSON.parse(Buffer.from(body, 'base64url').toString());
    return p.e > Date.now() && typeof p.u === 'string' ? p.u : null;
  } catch (e) {
    return null;
  }
}

/** Signed in on the admin page, or carrying the publisher key. */
const isAdmin = (req) => hasKey(req) || sessionUser(req) !== null;

function hashPassword(password, salt) {
  return crypto.scryptSync(password, salt, 32).toString('hex');
}

/** A short, single-line string, or '' when the value is not text. */
function text(v, max) {
  if (typeof v !== 'string' && typeof v !== 'number') return '';
  return String(v).replace(/[\u0000-\u001f]+/g, ' ').trim().slice(0, max);
}

module.exports = { sql, isAdmin, hasKey, same, sessionCookie, clearCookie, sessionUser, hashPassword, text };
