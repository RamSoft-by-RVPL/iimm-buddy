// Reads an uploaded timetable sheet and returns its classes. Nothing is
// saved here: the admin page shows the result and then publishes it through
// /api/timetable. Admin key required.
//
//   POST /api/sheet   body: the .xlsx file (application/octet-stream)

const { isAdmin } = require('../lib/db');
const { readXlsx, parseTimetable } = require('../lib/sheet');

module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });
  if (!isAdmin(req)) return res.status(401).json({ error: 'not allowed' });
  const body = req.body;
  if (!Buffer.isBuffer(body) || body.length < 100 || body.length > 2 * 1024 * 1024) {
    return res.status(400).json({ error: 'Send the Excel file itself (up to 2 MB).' });
  }
  try {
    const classes = parseTimetable(readXlsx(body));
    if (!classes.length) return res.status(400).json({ error: 'No classes found in this sheet.' });
    return res.status(200).json({ classes });
  } catch (e) {
    return res.status(400).json({ error: `Could not read this file as a timetable. ${e.message}` });
  }
};
