// Tells every phone to look for something now. Admin only.
//
//   POST /api/poke?type=update     a new app version was published

const { isAdmin } = require('../lib/db');
const { push } = require('../lib/push');

module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });
  if (!isAdmin(req)) return res.status(401).json({ error: 'not allowed' });
  const type = String(req.query.type || '');
  if (type !== 'update') return res.status(400).json({ error: 'unknown type' });
  return res.status(200).json(await push('all', { data: { type } }));
};
