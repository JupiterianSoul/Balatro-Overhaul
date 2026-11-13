const URL_ENV = 'ERROR_ALERT_URL';
const SAME_MS = 10 * 60 * 1000;
const MAX_PER_HOUR = 30;

const seen = new Map<string, { at: number; skipped: number }>();
let hour: number[] = [];

export function shouldAlert(key: string, now = Date.now()): { send: boolean; skipped: number } {
  hour = hour.filter(t => now - t < 3600_000);
  const prev = seen.get(key);
  if (prev && now - prev.at < SAME_MS) {
    prev.skipped++;
    return { send: false, skipped: 0 };
  }
  if (hour.length >= MAX_PER_HOUR) return { send: false, skipped: 0 };
  hour.push(now);
  seen.set(key, { at: now, skipped: 0 });
  if (seen.size > 500) seen.delete(seen.keys().next().value as string);
  return { send: true, skipped: prev?.skipped ?? 0 };
}

export function alertError(tag: string, msg: string, now = Date.now()): void {
  const url = process.env[URL_ENV];
  if (!url) return;
  const key = `${tag}:${msg.replace(/\d+/g, '#').slice(0, 120)}`;
  const r = shouldAlert(key, now);
  if (!r.send) return;
  const body = `${msg.slice(0, 900)}${r.skipped ? `\n(${r.skipped} more like this since the last alert)` : ''}`;
  fetch(url, {
    method: 'POST',
    headers: { Title: `Overhaul server error [${tag}]`, Priority: 'high', Tags: 'rotating_light' },
    body,
  }).catch(() => {});
}

export function alertInfo(tag: string, msg: string): void {
  const url = process.env[URL_ENV];
  if (!url) return;
  fetch(url, { method: 'POST', headers: { Title: `Overhaul server [${tag}]`, Priority: 'default', Tags: 'information_source' }, body: msg }).catch(() => {});
}

export function installProcessAlerts(): void {
  process.on('uncaughtException', e => {
    alertError('CRASH', `uncaught: ${e instanceof Error ? (e.stack ?? e.message) : String(e)}`);
    console.error('uncaughtException', e);
  });
  process.on('unhandledRejection', e => {
    alertError('REJECTION', `unhandled rejection: ${e instanceof Error ? (e.stack ?? e.message) : String(e)}`);
    console.error('unhandledRejection', e);
  });
}
