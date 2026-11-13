import { S3Client } from 'bun';
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dir, '../..');
const file = resolve(process.argv[2] ?? `${root}/dist/BalatroOverhaul-linux-install.sh`);
const days = Math.min(7, Math.max(1, Number(process.argv[3] ?? 7)));
const KEEP = 2;

const e = process.env;
if (!e.R2_ACCOUNT_ID || !e.R2_ACCESS_KEY_ID || !e.R2_SECRET_ACCESS_KEY || !e.R2_BUCKET) {
  throw new Error('R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY and R2_BUCKET must be set (~/.config/balatro-overhaul/release.env)');
}
if (!existsSync(file)) throw new Error(`missing ${file}: run tools/release/linux_installer.sh first`);

const client = new S3Client({
  accessKeyId: e.R2_ACCESS_KEY_ID, secretAccessKey: e.R2_SECRET_ACCESS_KEY, bucket: e.R2_BUCKET,
  endpoint: `https://${e.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
});

const stamp = new Date().toISOString().replace(/[-:]/g, '').replace('T', '-').slice(0, 13);
const key = `friends/BalatroOverhaul-linux-install-${stamp}.sh`;
const size = Bun.file(file).size;
const writer = client.file(key).writer({ type: 'application/x-sh', partSize: 16 * 1048576, queueSize: 4, retry: 3 });
let sent = 0, shown = -1;
for await (const chunk of Bun.file(file).stream()) {
  writer.write(chunk);
  await writer.flush();
  sent += chunk.byteLength;
  const pct = Math.floor(sent * 100 / size);
  if (pct >= shown + 20 || sent === size) { shown = pct; console.log(`  ${key}: ${pct}% of ${(size / 1048576).toFixed(0)} MB`); }
}
await writer.end();

const listed = await client.list({ prefix: 'friends/' });
const old = (listed.contents ?? []).map(c => c.key).filter(k => k !== key).sort().reverse().slice(KEEP - 1);
for (const k of old) { await client.delete(k); console.log(`  removed old ${k}`); }

const url = client.presign(key, { expiresIn: days * 86400, method: 'GET' });
console.log(`\nLink valid for ${days} days. Command for the friend:\n`);
console.log(`curl -fL '${url}' -o /tmp/balatro-overhaul-install.sh && bash /tmp/balatro-overhaul-install.sh; rm -f /tmp/balatro-overhaul-install.sh`);
