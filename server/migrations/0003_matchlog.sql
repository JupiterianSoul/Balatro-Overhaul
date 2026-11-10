CREATE TABLE IF NOT EXISTS match_logs (
  id TEXT PRIMARY KEY,
  at INTEGER NOT NULL,
  ended INTEGER NOT NULL,
  mode TEXT NOT NULL,
  kind TEXT NOT NULL,
  ranked INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT '',
  keep_until INTEGER,
  has_replay INTEGER NOT NULL DEFAULT 0,
  bytes INTEGER NOT NULL,
  data TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS match_logs_keep ON match_logs (keep_until);
CREATE INDEX IF NOT EXISTS match_logs_status ON match_logs (status);

CREATE TABLE IF NOT EXISTS match_log_players (
  id TEXT NOT NULL,
  pkey TEXT NOT NULL,
  pid INTEGER NOT NULL,
  at INTEGER NOT NULL,
  keep_until INTEGER,
  item TEXT NOT NULL,
  PRIMARY KEY (id, pkey)
);
CREATE INDEX IF NOT EXISTS match_log_players_pkey ON match_log_players (pkey, at);
CREATE INDEX IF NOT EXISTS match_log_players_keep ON match_log_players (keep_until);

INSERT OR IGNORE INTO seasons (id, starts, ends, name) VALUES ('2026-Q4', 1790812800000, 1798761600000, 'Autumn 2026');
UPDATE players SET season = '2026-Q4' WHERE season IN ('2026-11', '2026-12');
