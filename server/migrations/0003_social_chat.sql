CREATE TABLE IF NOT EXISTS social_prefs (
  pkey TEXT PRIMARY KEY,
  name_key TEXT NOT NULL DEFAULT '',
  rp INTEGER,
  chat_enabled INTEGER NOT NULL DEFAULT 0,
  chat_allowed INTEGER
);
CREATE INDEX IF NOT EXISTS social_prefs_name ON social_prefs (name_key);
CREATE TABLE IF NOT EXISTS chat_dms (
  id TEXT PRIMARY KEY,
  conv TEXT NOT NULL,
  sender TEXT NOT NULL,
  at INTEGER NOT NULL,
  text TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS chat_dms_conv ON chat_dms (conv, at);
CREATE TABLE IF NOT EXISTS chat_unread (
  pkey TEXT NOT NULL,
  other TEXT NOT NULL,
  n INTEGER NOT NULL,
  PRIMARY KEY (pkey, other)
);
CREATE TABLE IF NOT EXISTS chat_mutes (
  pkey TEXT NOT NULL,
  other TEXT NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (pkey, other)
);
CREATE TABLE IF NOT EXISTS chat_reports (
  id TEXT PRIMARY KEY,
  reporter TEXT NOT NULL,
  reported TEXT NOT NULL,
  kind TEXT NOT NULL,
  msg_id TEXT NOT NULL,
  text TEXT NOT NULL,
  context TEXT NOT NULL,
  reason TEXT NOT NULL,
  match_id TEXT,
  at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS chat_reports_at ON chat_reports (at);
CREATE TABLE IF NOT EXISTS notify_items (
  id TEXT PRIMARY KEY,
  pkey TEXT NOT NULL,
  kind TEXT NOT NULL,
  at INTEGER NOT NULL,
  read INTEGER NOT NULL DEFAULT 0,
  data TEXT NOT NULL,
  expires INTEGER
);
CREATE INDEX IF NOT EXISTS notify_items_pkey ON notify_items (pkey, at);
