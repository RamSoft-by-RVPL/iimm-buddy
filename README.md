# IIMM Buddy

An Android app for IIM Mumbai students that puts attendance, the class
timetable, Moodle notes and deadlines in one place. It's made by a student
and is **not an official app of IIM Mumbai**.

**Download:** https://buddy.iimmumbai.in

## What it does

- **Attendance that does the maths.** Every course with its percentage, how
  many classes you can still miss, and how many you must attend to get back to
  the minimum (85%).
- **A reminder before every class.** "Class in 5 mins" with the course and
  room, scheduled on the phone so it works with the app closed.
- **Moodle on the phone.** Course files download and open inside the app,
  new material triggers a notification, and you can search inside PDFs, slides
  and Word files.
- **Deadline reminders.** They start two days before an assignment is due,
  then follow the times you choose, and show what you've already submitted.
- **Timetable.** Week and month views. Classes the college mails out but
  hasn't put on the attendance portal yet (HPE, for example) are added from
  the weekly timetable sheet.
- **Academic calendar.** Holidays, breaks and exams, with reminders.
- **Leave planner.** Finds long weekends and the longest safe breaks, and
  checks any dates you pick against every course.
- **Home-screen widget**, a leave log, and announcements from the admin page.

## How it works

```
 Phone (Flutter app)                                Server (Vercel + Neon Postgres)
 ───────────────────                                ───────────────────────────────
 Microsoft sign-in in a web view                    /api/timetable   weekly classes per batch
   └─ attendance portal API ─┐                      /api/calendar    academic calendar
   └─ Moodle (AJAX + pages) ─┼─ all on the phone    /api/notices     messages, sent by push
                             │                      /api/log         diagnostics from the app
 Shared data from the server ┘ ◄─────────────────── /admin           login, stats, uploads
 Push via Firebase Cloud Messaging ◄──────────────── lib/push.js (FCM HTTP v1)
```

- The student signs in on Microsoft's own page inside the app. The app never
  sees the password; it keeps only the session cookies, like a browser.
- Attendance and Moodle are read **directly from the phone**. The server
  never receives attendance figures or Moodle content.
- The server only holds what is the same for a whole batch, uploaded by the
  admin: the week's timetable (from the mailed .xlsx), the academic calendar
  (from the .docx) and messages. It also keeps a short diagnostic log per
  user (roll number, name, app version and whether syncs worked), which the
  student can turn off in Settings.
- Class reminders are scheduled locally with exact alarms. Background checks
  for new marks, Moodle items and deadlines run through WorkManager about
  every 15–30 minutes.
- The app updates itself: it reads `version.json`, downloads the APK, checks
  its SHA-256 and hands it to the Android installer.

## Repository layout

| Folder | What it is |
| --- | --- |
| [`app/`](app) | The Flutter app (Dart, with a small Kotlin plugin in `app/packages/cookie_bridge` and the home-screen widget). |
| [`server/`](server) | Vercel serverless functions (Node), the admin page and the download page in `server/public`. |

## How a change reaches students

Every push to `main` that changes `app/` runs `.github/workflows/app.yml`:

1. runs the tests;
2. numbers the version: the build number goes up by one, and the version name
   too (or takes the one in `app/pubspec.yaml` if that was raised by hand);
3. builds the APK, signs it with the key every installed copy uses and checks
   that it did;
4. creates a GitHub Release with the APK and `version.json`;
5. redeploys the site on Vercel, which copies them from the release;
6. waits until https://buddy.iimmumbai.in serves the new build and tells
   every phone by push to update. The app then shows an Update button.

The first line of the commit message becomes the "what's new" line shown to
students. A release can also be started by hand from the Actions tab.

Changes to `server/` only are deployed by Vercel on push, with no new app
version.

## Building the app

Needs Flutter 3.24 (Dart 3.5), JDK 17 and the Android SDK.

```sh
cd app
flutter pub get
flutter test
flutter build apk --release --split-per-abi
```

Push notifications use Firebase. The Firebase config file
`app/android/app/google-services.json` is **not in this repo**: create a
Firebase project, add an Android app with the package name
`in.bharadia.attendance_planner`, and put its `google-services.json` there.

## Running the server

```sh
cd server
npm install
vercel link
vercel env add DATABASE_URL          # Neon Postgres connection string
vercel env add ADMIN_KEY             # long random string, the publisher key
vercel env add FCM_SERVICE_ACCOUNT   # base64 of the Firebase service-account JSON
node lib/setup.js                    # creates the tables (lib/schema.sql)
vercel deploy --prod
```

Then open `/admin` and create the admin login with the publisher key.

## Privacy

The full privacy policy is in the app (Settings → Privacy). In short:
passwords stay with Microsoft, attendance and Moodle data stay on the phone,
and the diagnostic log can be turned off.

## Disclaimer

IIMM Buddy is an independent student project. It is not made, endorsed or
supported by IIM Mumbai. If the app and the official portal ever disagree,
the portal is right.
