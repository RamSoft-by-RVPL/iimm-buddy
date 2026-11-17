CREATE TABLE IF NOT EXISTS timetables (
  batch   text PRIMARY KEY,
  updated timestamptz NOT NULL,
  classes jsonb NOT NULL
);

-- One row per installed copy of the app.
CREATE TABLE IF NOT EXISTS users (
  id          text PRIMARY KEY,          -- random id made by the app
  roll        text NOT NULL DEFAULT '',
  name        text NOT NULL DEFAULT '',
  batch       text NOT NULL DEFAULT '',
  app_version text NOT NULL DEFAULT '',
  device      text NOT NULL DEFAULT '',  -- "samsung SM-A546E, Android 14"
  first_seen  timestamptz NOT NULL DEFAULT now(),
  last_seen   timestamptz NOT NULL DEFAULT now(),
  last_error  text NOT NULL DEFAULT '',
  health      text NOT NULL DEFAULT ''   -- what blocks reminders, '' when fine
);

CREATE TABLE IF NOT EXISTS events (
  id       bigserial PRIMARY KEY,
  user_id  text NOT NULL,
  at       timestamptz NOT NULL,          -- when it happened on the phone
  received timestamptz NOT NULL DEFAULT now(),
  kind     text NOT NULL,
  detail   text NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS events_user_at ON events (user_id, at DESC);
CREATE INDEX IF NOT EXISTS events_received ON events (received);

-- People who may sign in to the admin page.
CREATE TABLE IF NOT EXISTS admins (
  username text PRIMARY KEY,
  salt     text NOT NULL,
  hash     text NOT NULL,            -- scrypt of the password
  created  timestamptz NOT NULL DEFAULT now()
);
-- Wrong passwords, to slow down guessing.
CREATE TABLE IF NOT EXISTS login_fails (
  username text NOT NULL,
  at       timestamptz NOT NULL DEFAULT now()
);

-- Messages the admin sends to every phone (or to one batch).
CREATE TABLE IF NOT EXISTS notices (
  id      bigserial PRIMARY KEY,
  batch   text NOT NULL DEFAULT '',     -- '' means everyone
  title   text NOT NULL,
  body    text NOT NULL DEFAULT '',
  sent_by text NOT NULL DEFAULT '',
  created timestamptz NOT NULL DEFAULT now()
);

-- Messages can be written now and sent later.
ALTER TABLE notices ADD COLUMN IF NOT EXISTS send_at timestamptz NOT NULL DEFAULT now(); -- on first run, existing rows were then set to their created time by hand
ALTER TABLE notices ADD COLUMN IF NOT EXISTS pushed boolean NOT NULL DEFAULT true;

-- The academic calendar of a batch: exams, holidays, breaks, term dates.
CREATE TABLE IF NOT EXISTS calendars (
  batch   text PRIMARY KEY,
  updated timestamptz NOT NULL,
  title   text NOT NULL DEFAULT '',
  events  jsonb NOT NULL
);
