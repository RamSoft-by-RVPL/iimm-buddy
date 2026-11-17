# IIMM Buddy: server

Backend for the IIMM Buddy app, on Vercel with a Neon Postgres database. See
the [main README](../README.md) for the overall design and setup.

| Route | Who | What |
| --- | --- | --- |
| `GET /api/timetable?batch=<key>` | anyone | The batch's published classes |
| `POST /api/timetable?batch=<key>` | admin | Replace them |
| `POST /api/sheet` | admin | Read an uploaded .xlsx timetable (preview, not saved) |
| `GET/POST /api/calendar`, `POST /api/calendar-doc` | anyone / admin | Academic calendar, and reading it from a .docx |
| `GET/POST /api/notices` | anyone / admin | Messages to students, sent by push, can be scheduled |
| `POST /api/log` | the app | Diagnostic log lines |
| `GET /api/admin` | admin | Totals, users, one user's log |
| `POST /api/auth` | admin | Login, logout, first-time setup |
| `POST /api/poke` | admin | Push a "check now" to phones |
| `/admin` | admin | The admin page |
| `/` | anyone | Download page |

"Admin" means a signed login cookie, or `Authorization: Bearer <ADMIN_KEY>`.

Environment variables: `DATABASE_URL`, `ADMIN_KEY`, `FCM_SERVICE_ACCOUNT`
(base64 of the Firebase service-account JSON). Tables are in
`lib/schema.sql`; `node lib/setup.js` creates them. `node lib/local.js` runs
the handlers locally for testing.

`release.sh "notes"` publishes a new APK: copies it, writes `version.json`,
updates the download page, deploys and tells phones to check for the update.
`publish-code.sh "message"` copies the code into the public GitHub repo after
checking that no secrets came along.
