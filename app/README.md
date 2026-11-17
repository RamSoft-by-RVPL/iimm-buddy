# IIMM Buddy: Android app

The Flutter app. See the [main README](../README.md) for what it does and how
it fits together.

| File | What it holds |
| --- | --- |
| `lib/main.dart` | App start, the four tabs, sign-in screen |
| `lib/site.dart`, `lib/net.dart` | Attendance portal: sign-in session, data model, local store |
| `lib/moodle*.dart`, `lib/notes_index.dart`, `lib/file_view.dart` | Moodle courses, files, search inside notes, in-app viewer |
| `lib/planner.dart`, `lib/plan_ui.dart` | Leave maths: classes left, safe breaks, long weekends |
| `lib/timetable_ui.dart`, `lib/sheet.dart` | Week and month views, reading the mailed .xlsx timetable |
| `lib/acal.dart`, `lib/exams*.dart` | Academic calendar, exam countdowns |
| `lib/notify.dart`, `lib/background.dart`, `lib/push.dart` | Reminders, background checks, Firebase push |
| `lib/backend.dart`, `lib/log.dart`, `lib/update.dart` | Talking to the server, diagnostics, self-update |
| `packages/cookie_bridge` | Small Kotlin plugin: cookies, widget, calendar, battery, file intents |

```sh
flutter pub get
flutter test
flutter build apk --release --split-per-abi
```

`android/app/google-services.json` (Firebase) is not in the repo; add your own.
