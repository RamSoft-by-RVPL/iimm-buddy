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
| `GET/POST/DELETE /api/menu` | anyone / admin | Mess menu, one week at a time, the same for everyone |
| `GET/POST/DELETE /api/exams?batch=<key>` | anyone / admin | The batch's exam timetable |
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

Deploys come from GitHub: Vercel builds the `server/` folder of
`RamSoft-by-RVPL/iimm-buddy` on every push to `main`, and again when the app workflow
publishes a release (deploy hook). The APK is not kept in git. The build
command (`lib/fetch-release.js`, set in `vercel.json`) copies
`IIMM-Buddy.apk` and `version.json` from the newest GitHub Release into
`public/`, checks them against each other, and writes the version on the
download page.

App releases are made by `.github/workflows/app.yml`, see the main README.

## Publishing the mess menu and the exam timetable

There is no upload form for these: the file (the mess's weekly PDF, the exam
office's schedule) is read by hand or by Claude and posted as JSON with the
publisher key. The admin page shows what is published and can remove it.

```sh
# Mess menu. week = the menu's first day; days = up to 7 days within it.
curl -X POST https://buddy.iimmumbai.in/api/menu \
  -H "Authorization: Bearer $ADMIN_KEY" -H "Content-Type: application/json" \
  -d '{"week":"2026-11-23","days":[{"d":"2026-11-23","meals":[
        {"n":"Breakfast","items":["Poha","Tea / Coffee"]},
        {"n":"Lunch","items":["Dal Fry","Rice","Chapati"]}]}]}'

# Exam timetable for one batch. e (end), r (room) and n (note) may be "".
curl -X POST "https://buddy.iimmumbai.in/api/exams?batch=bs-2026-2030" \
  -H "Authorization: Bearer $ADMIN_KEY" -H "Content-Type: application/json" \
  -d '{"title":"End-term exams","exams":[
        {"d":"2026-12-08","s":"10:00","e":"13:00","c":"Marketing Management","r":"101","n":""}]}'
```

Posting a week again replaces it. Phones are told by push to fetch it. Each
student's app keeps the exam papers whose course name matches one of their
courses (spelling differences are tolerated), so use the course names as the
exam office writes them.
