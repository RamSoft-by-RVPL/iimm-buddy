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
-- Install ids of the only phones a message is for ('{}' = the batch or everyone).
ALTER TABLE notices ADD COLUMN IF NOT EXISTS users text[] NOT NULL DEFAULT '{}';

-- The academic calendar of a batch: exams, holidays, breaks, term dates.
CREATE TABLE IF NOT EXISTS calendars (
  batch   text PRIMARY KEY,
  updated timestamptz NOT NULL,
  title   text NOT NULL DEFAULT '',
  events  jsonb NOT NULL
);

-- The mess menu, one row per week (its first day). The same for everyone.
CREATE TABLE IF NOT EXISTS menus (
  week    date PRIMARY KEY,
  updated timestamptz NOT NULL,
  days    jsonb NOT NULL                -- [{d, meals: [{n, items: [...]}]}]
);

-- The exam timetable of a batch, one entry per paper.
CREATE TABLE IF NOT EXISTS exam_timetables (
  batch   text PRIMARY KEY,
  updated timestamptz NOT NULL,
  title   text NOT NULL DEFAULT '',
  exams   jsonb NOT NULL                -- [{d, s, e, c, r, n}]
);

-- Classes called off by the admin; phones hide them (api/cancelled.js).
CREATE TABLE IF NOT EXISTS cancellations (
  id      bigserial PRIMARY KEY,
  batch   text NOT NULL,
  d       date NOT NULL,
  s       text NOT NULL,                -- start 'HH:MM'
  c       text NOT NULL DEFAULT '',     -- course as on the timetable ('' = any)
  why     text NOT NULL DEFAULT '',
  created timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS cancellations_batch_d ON cancellations (batch, d);

-- Students who may post from the app: class reps, mess and hostel
-- secretaries. Keyed by the app's install id; the token is what the phone
-- sends with each post.
CREATE TABLE IF NOT EXISTS roles (
  user_id text PRIMARY KEY,
  role    text NOT NULL,                -- cr | mess | hostel
  batch   text NOT NULL DEFAULT '',     -- who they post to ('' = everyone)
  name    text NOT NULL DEFAULT '',
  roll    text NOT NULL DEFAULT '',
  token   text NOT NULL UNIQUE,
  set_by  text NOT NULL DEFAULT '',
  created timestamptz NOT NULL DEFAULT now()
);
-- The install id of the student who posted a message ('' = the admin).
ALTER TABLE notices ADD COLUMN IF NOT EXISTS by_user text NOT NULL DEFAULT '';
-- Which app the phone runs: in.ramyaventures.crony (Play) or the site's build; '' before 0.9.2.
ALTER TABLE users ADD COLUMN IF NOT EXISTS app text NOT NULL DEFAULT '';
ALTER TABLE cancellations ADD COLUMN IF NOT EXISTS by_user text NOT NULL DEFAULT '';

-- Classes a CR (or the admin) added or moved to a new time. A moved class
-- also has a row in cancellations for its old time (cancel_id).
CREATE TABLE IF NOT EXISTS extra_classes (
  id        bigserial PRIMARY KEY,
  batch     text NOT NULL,
  d         date NOT NULL,
  s         text NOT NULL,              -- start 'HH:MM'
  e         text NOT NULL,              -- end 'HH:MM'
  c         text NOT NULL,              -- course as on the timetable
  room      text NOT NULL DEFAULT '',
  why       text NOT NULL DEFAULT '',
  cancel_id bigint,
  by_user   text NOT NULL DEFAULT '',
  created   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS extra_classes_batch_d ON extra_classes (batch, d);

-- Quick polls from the admin, a CR or a secretary. One vote per phone
-- (install id); a vote can be changed while the poll is open.
CREATE TABLE IF NOT EXISTS polls (
  id       bigserial PRIMARY KEY,
  batch    text NOT NULL DEFAULT '',    -- '' = everyone
  question text NOT NULL,
  options  jsonb NOT NULL,              -- ["Yes", "No"]
  by_user  text NOT NULL DEFAULT '',    -- install id of a role holder, '' = admin
  sent_by  text NOT NULL DEFAULT '',
  created  timestamptz NOT NULL DEFAULT now(),
  closes   timestamptz NOT NULL,
  closed   boolean NOT NULL DEFAULT false
);
CREATE TABLE IF NOT EXISTS poll_votes (
  poll_id bigint NOT NULL REFERENCES polls(id) ON DELETE CASCADE,
  user_id text NOT NULL,
  choice  int NOT NULL,
  at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (poll_id, user_id)
);

-- Files a mess secretary sends in (the week's menu as a photo or PDF), for
-- the admin to publish.
CREATE TABLE IF NOT EXISTS uploads (
  id      bigserial PRIMARY KEY,
  kind    text NOT NULL DEFAULT 'menu',
  by_user text NOT NULL,
  sent_by text NOT NULL DEFAULT '',
  name    text NOT NULL DEFAULT '',
  mime    text NOT NULL DEFAULT '',
  size    int NOT NULL DEFAULT 0,
  note    text NOT NULL DEFAULT '',
  data    bytea NOT NULL,
  created timestamptz NOT NULL DEFAULT now(),
  done    boolean NOT NULL DEFAULT false
);

-- Teachers' institute email addresses, for the Email button in the app.
CREATE TABLE IF NOT EXISTS faculty (
  name    text PRIMARY KEY,
  email   text NOT NULL,
  updated timestamptz NOT NULL DEFAULT now()
);

-- Small settings every phone reads (api/app.js), such as the oldest app
-- version that may still be used.
CREATE TABLE IF NOT EXISTS settings (
  key     text PRIMARY KEY,
  value   text NOT NULL DEFAULT '',
  updated timestamptz NOT NULL DEFAULT now()
);

-- One-tap ratings of mess meals, 1 (poor) to 3 (good). One per phone and
-- meal; rating again replaces it (api/ratings.js).
CREATE TABLE IF NOT EXISTS meal_ratings (
  d       date NOT NULL,
  meal    text NOT NULL,                -- as on the menu: "Lunch"
  user_id text NOT NULL,
  score   smallint NOT NULL,
  at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (d, meal, user_id)
);

-- Free time a student shares with friends (api/free.js): a first name and
-- the times they are in class, nothing else. Read by whoever has the code;
-- the row is deleted when the student stops sharing.
CREATE TABLE IF NOT EXISTS free_shares (
  user_id text PRIMARY KEY,             -- install id
  code    text NOT NULL UNIQUE,         -- 8 letters and digits
  name    text NOT NULL DEFAULT '',
  busy    jsonb NOT NULL,               -- [{d, s, e}]
  updated timestamptz NOT NULL DEFAULT now()
);
