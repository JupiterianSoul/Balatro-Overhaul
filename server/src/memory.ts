import { readFileSync, readdirSync } from 'node:fs';

const MB = 1048576;

export function rssOfPid(pid: number): number {
  try {
    const m = /VmRSS:\s+(\d+)\s*kB/.exec(readFileSync(`/proc/${pid}/status`, 'utf8'));
    return m ? Number(m[1]) * 1024 : 0;
  } catch {
    return 0;
  }
}

export function childPidsOf(pid: number): number[] {
  const out: number[] = [];
  let tasks: string[] = [];
  try { tasks = readdirSync(`/proc/${pid}/task`); } catch { return out; }
  for (const t of tasks) {
    let kids = '';
    try { kids = readFileSync(`/proc/${pid}/task/${t}/children`, 'utf8').trim(); } catch { continue; }
    if (!kids) continue;
    for (const k of kids.split(/\s+/)) {
      const n = Number(k);
      if (!Number.isInteger(n) || n <= 0) continue;
      out.push(n, ...childPidsOf(n));
    }
  }
  return out;
}

export interface MemorySample { rssMB: number; heapMB: number; childMB: number; children: number; totalMB: number }

export function memorySample(): MemorySample {
  const mem = process.memoryUsage();
  const kids = childPidsOf(process.pid);
  const childBytes = kids.reduce((s, k) => s + rssOfPid(k), 0);
  const rssMB = mem.rss / MB;
  const childMB = childBytes / MB;
  return { rssMB, heapMB: mem.heapUsed / MB, childMB, children: kids.length, totalMB: rssMB + childMB };
}

export function memoryHeaders(s: MemorySample = memorySample()): Record<string, string> {
  return {
    'X-RSS-MB': s.rssMB.toFixed(1),
    'X-Heap-MB': s.heapMB.toFixed(1),
    'X-Workers-MB': s.childMB.toFixed(1),
    'X-Workers': String(s.children),
    'X-Total-MB': s.totalMB.toFixed(1),
  };
}

export const MEM_WARN_MB = Number(process.env.MEM_WARN_MB) > 0 ? Number(process.env.MEM_WARN_MB) : 380;

export class MemoryWatch {
  private armed = true;

  constructor(private sizes: () => Record<string, number>, private say: (line: string) => void,
    private warnMB = MEM_WARN_MB, private sample: () => MemorySample = memorySample) {}

  check(): boolean {
    const s = this.sample();
    if (s.totalMB < this.warnMB * 0.85) { this.armed = true; return false; }
    if (s.totalMB < this.warnMB || !this.armed) return false;
    this.armed = false;
    let sizes: Record<string, number> = {};
    try { sizes = this.sizes(); } catch { sizes = {}; }
    const parts = Object.entries(sizes).map(([k, v]) => `${k}=${v}`).join(' ');
    this.say(`memory high: total=${s.totalMB.toFixed(0)}MB rss=${s.rssMB.toFixed(0)}MB heap=${s.heapMB.toFixed(0)}MB workers=${s.children}/${s.childMB.toFixed(0)}MB ${parts}`);
    return true;
  }
}
