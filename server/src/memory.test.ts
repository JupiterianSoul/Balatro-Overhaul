import { describe, it, expect } from 'bun:test';
import { memorySample, memoryHeaders, MemoryWatch, childPidsOf, type MemorySample } from './memory';
import { botMemory, roomForWorker, maxWorkers } from './bots';
import { Traffic, TRAFFIC_MAX_KEYS } from './traffic';
import { crashAllowed, crashSizes, pruneIpHits, resetCrashState, CRASH_MAX_IPS, CRASH_PER_IP_PER_HOUR } from './crash';
import { MatchLogService, MemoryLogStore, CAPS, type LogHeader } from './matchlog';

const sample = (totalMB: number): MemorySample => ({ rssMB: totalMB, heapMB: totalMB / 2, childMB: 0, children: 0, totalMB });

function header(id: string): Omit<LogHeader, 'v' | 'started_at'> {
  return {
    id, mode: 'nemesis', ranked: false, kind: '1v1', settings: {}, ruleset: null, seeds: ['S'],
    players: [{ pid: 0, name: 'Ann', is_bot: false, version: '1', mods: [] }, { pid: 1, name: 'Ben', is_bot: false, version: '1', mods: [] }],
  };
}

describe('memory numbers', () => {
  it('reads the server RSS and heap and puts them in the ping headers', () => {
    const s = memorySample();
    expect(s.rssMB).toBeGreaterThan(5);
    expect(s.heapMB).toBeGreaterThan(0);
    expect(s.totalMB).toBeGreaterThanOrEqual(s.rssMB);
    const h = memoryHeaders(s);
    expect(Number(h['X-RSS-MB'])).toBeCloseTo(s.rssMB, 0);
    expect(Number(h['X-Heap-MB'])).toBeCloseTo(s.heapMB, 0);
    expect(Object.keys(h)).toEqual(['X-RSS-MB', 'X-Heap-MB', 'X-Workers-MB', 'X-Workers', 'X-Total-MB']);
  });

  it('counts child processes such as bot workers', async () => {
    const p = Bun.spawn(['sleep', '5']);
    try {
      await Bun.sleep(50);
      expect(childPidsOf(process.pid)).toContain(p.pid);
    } finally { p.kill(); }
  });

  it('logs one line with the structure sizes when memory passes the threshold, then waits until it drops', () => {
    let total = 100;
    const lines: string[] = [];
    const w = new MemoryWatch(() => ({ rooms: 7, logsLive: 3 }), l => lines.push(l), 400, () => sample(total));
    expect(w.check()).toBe(false);
    total = 420;
    expect(w.check()).toBe(true);
    expect(w.check()).toBe(false);
    total = 390;
    expect(w.check()).toBe(false);
    total = 300;
    w.check();
    total = 450;
    expect(w.check()).toBe(true);
    expect(lines.length).toBe(2);
    expect(lines[0]).toContain('total=420MB');
    expect(lines[0]).toContain('rooms=7 logsLive=3');
  });
});

describe('bot workers stay inside the memory budget', () => {
  it('runs at most 3 worker processes by default', () => {
    expect(maxWorkers('')).toBe(3);
  });

  it('always allows the first worker, then only while the budget has room', () => {
    const keep = botMemory.totalMB;
    try {
      botMemory.totalMB = () => 1000;
      expect(roomForWorker(0, 3)).toBe(true);
      expect(roomForWorker(1, 3)).toBe(false);
      botMemory.totalMB = () => botMemory.budgetMB - botMemory.workerMB;
      expect(roomForWorker(1, 3)).toBe(true);
      expect(roomForWorker(3, 3)).toBe(false);
    } finally { botMemory.totalMB = keep; }
  });
});

describe('long lived maps are bounded', () => {
  it('traffic tables fold unknown keys into other past the cap', () => {
    const t = new Traffic();
    for (let i = 0; i < TRAFFIC_MAX_KEYS + 500; i++) {
      t.served(`/release/patchset-${i}.zip`, 10);
      t.received(`junk_${i}`, 10);
    }
    expect(t.http.size).toBe(TRAFFIC_MAX_KEYS + 1);
    expect(t.inn.size).toBe(TRAFFIC_MAX_KEYS + 1);
    expect(t.http.get('other')?.n).toBe(500);
    t.served('/release/patchset-0.zip', 10);
    expect(t.http.get('/release/patchset-0.zip')?.n).toBe(2);
  });

  it('crash rate limit forgets IPs after an hour and never holds more than the cap', () => {
    resetCrashState();
    const t0 = 1_000_000_000;
    for (let i = 0; i < 250; i++) expect(crashAllowed(`10.0.${i >> 8}.${i & 255}`, t0 + i)).toBe(true);
    expect(crashSizes().ips).toBe(250);
    pruneIpHits(t0 + 3_600_000 + 1000);
    expect(crashSizes().ips).toBe(0);
    for (let h = 0; h < 12; h++) {
      for (let i = 0; i < 250; i++) crashAllowed(`10.${h}.${i >> 8}.${i & 255}`, t0 + h * 3_600_000 + i);
    }
    expect(crashSizes().ips).toBeLessThanOrEqual(CRASH_MAX_IPS);
    resetCrashState();
  });

  it('the crash limit per IP still holds after pruning', () => {
    resetCrashState();
    const t0 = 2_000_000_000;
    for (let i = 0; i < CRASH_PER_IP_PER_HOUR; i++) expect(crashAllowed('1.2.3.4', t0 + i)).toBe(true);
    pruneIpHits(t0 + 10);
    expect(crashAllowed('1.2.3.4', t0 + 20)).toBe(false);
    resetCrashState();
  });

  it('a match log whose room is gone is finished and dropped instead of waiting hours', async () => {
    let now = 1_000_000;
    const store = new MemoryLogStore();
    const svc = new MatchLogService(store, { now: () => now });
    const kept = { code: 'KEEP' }, gone = { code: 'GONE' };
    svc.start(kept, header('kept'));
    svc.start(gone, header('gone'));
    svc.act(gone, 0, 1, Array.from({ length: 200 }, (_, i) => ({ k: 'pl', c: [i] })));
    const alive = (h: object) => h === kept;
    expect(svc.dropOrphans(alive)).toBe(0);
    now += CAPS.orphanMs + 1;
    expect(svc.dropOrphans(alive)).toBe(1);
    expect(svc.sizes().logsLive).toBe(1);
    expect(svc.of(kept)?.id).toBe('kept');
    expect(svc.of(gone)).toBeNull();
    await Bun.sleep(0);
    const row = await store.get('gone');
    expect(row).toBeTruthy();
    now += CAPS.lateMs + 1;
    svc.dropOrphans(alive);
    expect(svc.sizes().logsLate).toBe(0);
  });
});
