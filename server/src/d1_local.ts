import { Database } from 'bun:sqlite';
import { readdirSync, readFileSync } from 'fs';
import { join } from 'path';

type Row = Record<string, unknown>;

export function localD1Fetch(file: string, migrations = join(import.meta.dir, '..', 'migrations')) {
  const db = new Database(file, { create: true });
  for (const name of readdirSync(migrations).filter(n => n.endsWith('.sql')).sort()) {
    try {
      db.exec(readFileSync(join(migrations, name), 'utf8'));
    } catch {
      continue;
    }
  }
  return async (_url: string, init?: { body?: string }) => {
    const { sql, params } = JSON.parse(init?.body ?? '{}') as { sql: string; params?: unknown[] };
    try {
      const st = db.prepare(sql);
      const args = (params ?? []) as never[];
      let results: Row[] = [];
      let written = 0;
      if (st.columnNames.length > 0) {
        results = st.all(...args) as Row[];
      } else {
        written = st.run(...args).changes;
      }
      const meta = { rows_read: results.length, rows_written: written, changes: written };
      return new Response(JSON.stringify({ success: true, result: [{ results, meta, success: true }] }), { status: 200 });
    } catch (e) {
      return new Response(JSON.stringify({ success: false, errors: [{ message: String(e) }] }), { status: 400 });
    }
  };
}
