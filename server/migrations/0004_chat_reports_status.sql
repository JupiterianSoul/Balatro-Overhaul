ALTER TABLE chat_reports ADD COLUMN status TEXT NOT NULL DEFAULT 'open';
CREATE INDEX IF NOT EXISTS chat_reports_status ON chat_reports (status, at);
