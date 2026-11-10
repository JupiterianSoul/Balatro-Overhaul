import { readFileSync, writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { join } from 'node:path';

const repo = join(import.meta.dir, '..', '..');
const ts = require(join(repo, 'server', 'node_modules', 'typescript'));
const write = process.argv.includes('--write');
const keep = /^\s*(\/\/|\/\*)\s*(eslint|@ts-|prettier|istanbul|webpack|<reference|#region|#endregion)/i;

const files = execSync('git ls-files', { cwd: repo, encoding: 'utf8' }).split('\n')
  .filter(f => /\.(ts|js)$/.test(f) && !/node_modules|^assets\/smods|resources\/workshop|^smali|^res\/|^lib\/|^original\//.test(f) && !f.endsWith('.d.ts'));

function ranges(src: string, path: string): [number, number][] {
  const sf = ts.createSourceFile(path, src, ts.ScriptTarget.Latest, true);
  const seen = new Set<number>();
  const out: [number, number][] = [];
  const add = (list: { pos: number; end: number }[] | undefined) => {
    for (const c of list ?? []) if (!seen.has(c.pos)) { seen.add(c.pos); out.push([c.pos, c.end]); }
  };
  const visit = (n: any) => {
    add(ts.getLeadingCommentRanges(src, n.pos));
    add(ts.getTrailingCommentRanges(src, n.end));
    for (const c of n.getChildren(sf)) visit(c);
  };
  visit(sf);
  add(ts.getLeadingCommentRanges(src, sf.endOfFileToken.pos));
  return out;
}

function strip(src: string, path: string): string {
  const crlf = src.includes('\r\n');
  const text = src.replace(/\r\n/g, '\n');
  const spans = ranges(text, path).filter(([a, b]) => !keep.test(text.slice(a, b)) && !(text.startsWith('#!') && a === 0));
  const mask = new Array(text.length).fill(true);
  for (const [a, b] of spans) for (let i = a; i < b; i++) if (text[i] !== '\n') mask[i] = false;
  const lines = text.split('\n');
  const out: string[] = [];
  let pos = 0;
  for (const ln of lines) {
    const seg = mask.slice(pos, pos + ln.length);
    pos += ln.length + 1;
    if (seg.every(Boolean)) { out.push(ln); continue; }
    const nl = [...ln].filter((_, i) => seg[i]).join('').replace(/\s+$/, '');
    if (nl.trim() === '') continue;
    out.push(nl);
  }
  const res = out.join('\n');
  return crlf ? res.replace(/\n/g, '\r\n') : res;
}

function norm(src: string, path: string): string {
  const sf = ts.createSourceFile(path, src, ts.ScriptTarget.Latest, true);
  return ts.createPrinter({ removeComments: true }).printFile(sf);
}

let changed = 0, same = 0, removed = 0;
const failed: string[] = [];
for (const rel of files) {
  const path = join(repo, rel);
  let raw: string;
  try { raw = readFileSync(path, 'utf8'); } catch { continue; }
  const bom = raw.charCodeAt(0) === 0xfeff;
  if (bom) raw = raw.slice(1);
  const head = raw.split('\n').slice(0, 25).filter(l => /^\s*(\/\/|\/\*|\*)/.test(l)).join('\n');
  if (/Copyright|SPDX|GNU General|Permission is hereby/.test(head)) continue;
  const next = strip(raw, rel);
  if (next === raw) { same++; continue; }
  if (norm(raw, rel) !== norm(next, rel)) { failed.push(rel); continue; }
  changed++;
  removed += raw.split('\n').length - next.split('\n').length;
  if (write) writeFileSync(path, (bom ? '\ufeff' : '') + next);
}
console.log(JSON.stringify({ changed, same, removed, failed: failed.length }));
for (const f of failed.slice(0, 20)) console.log('FAILED', f);
