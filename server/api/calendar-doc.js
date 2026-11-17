// Reads an uploaded academic calendar (.docx) and returns its events.
// Nothing is saved here: the admin page shows the result and then publishes
// it through /api/calendar. Admin only.
//
//   POST /api/calendar-doc   body: the .docx file (application/octet-stream)

const { isAdmin } = require('../lib/db');
const { readCalendar } = require('../lib/caldoc');

module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });
  if (!isAdmin(req)) return res.status(401).json({ error: 'not allowed' });
  const body = req.body;
  if (!Buffer.isBuffer(body) || body.length < 100 || body.length > 4 * 1024 * 1024) {
    return res.status(400).json({ error: 'Send the Word file itself (up to 4 MB).' });
  }
  try {
    const out = readCalendar(body);
    if (!out.events.length) {
      return res.status(400).json({
        error: 'No dated rows found. The document needs a table with a "Date" column.',
      });
    }
    return res.status(200).json(out);
  } catch (e) {
    return res.status(400).json({ error: e.message });
  }
};
