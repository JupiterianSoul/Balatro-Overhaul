CREATE TABLE IF NOT EXISTS social_players (
  pkey TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL DEFAULT '',
  last_seen INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS social_links (
  pkey TEXT NOT NULL,
  other TEXT NOT NULL,
  status TEXT NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (pkey, other)
);
CREATE INDEX IF NOT EXISTS social_links_other ON social_links (other);
