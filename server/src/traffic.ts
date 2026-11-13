type Tally = { n: number; bytes: number };

export const TRAFFIC_MAX_KEYS = 300;

const TYPE_RE = /"type"\s*:\s*"([^"]{1,48})"/;

export class Traffic {
  readonly out = new Map<string, Tally>();
  readonly inn = new Map<string, Tally>();
  readonly http = new Map<string, Tally>();
  conns = 0;
  peakConns = 0;
  totalConns = 0;
  readonly started = Date.now();
  checks = 0;
  patchDownloads = 0;
  private day = '';
  private seen = new Set<number>();
  private seenAll = new Set<number>();

  sizes(): Record<string, number> {
    return { trafficKeys: this.out.size + this.inn.size + this.http.size, installsToday: this.seen.size, installsSeen: this.seenAll.size };
  }

  checked(ip: string, patch = false): void {
    const d = new Date().toISOString().slice(0, 10);
    if (d !== this.day) {
      this.day = d;
      this.seen.clear();
    }
    const h = Number(Bun.hash(ip) % 4294967296n);
    if (this.seen.size < 200000) this.seen.add(h);
    if (this.seenAll.size < 200000) this.seenAll.add(h);
    if (patch) this.patchDownloads++;
    else this.checks++;
  }

  private add(map: Map<string, Tally>, key: string, bytes: number, n = 1): void {
    if (map.size >= TRAFFIC_MAX_KEYS && !map.has(key)) key = 'other';
    const t = map.get(key);
    if (t) {
      t.n += n;
      t.bytes += bytes * n;
    } else {
      map.set(key, { n, bytes: bytes * n });
    }
  }

  static typeOf(raw: string): string {
    if (raw.startsWith('{"z":1')) return 'compressed';
    const m = TYPE_RE.exec(raw.length > 240 ? raw.slice(0, 240) : raw);
    return m ? m[1] : 'unknown';
  }

  sent(type: string | undefined, payload: string, copies = 1): void {
    if (copies <= 0) return;
    this.add(this.out, type ?? Traffic.typeOf(payload), Buffer.byteLength(payload, 'utf8'), copies);
  }

  received(type: string | undefined, bytes: number): void {
    this.add(this.inn, type ?? 'unknown', bytes);
  }

  served(path: string, bytes: number): void {
    this.add(this.http, path, bytes);
  }

  opened(): void {
    this.conns++;
    this.totalConns++;
    if (this.conns > this.peakConns) this.peakConns = this.conns;
  }

  closed(): void {
    if (this.conns > 0) this.conns--;
  }

  private static sum(map: Map<string, Tally>): number {
    let b = 0;
    for (const t of map.values()) b += t.bytes;
    return b;
  }

  headers(): Record<string, string> {
    const mb = (b: number) => (b / 1048576).toFixed(3);
    return {
      'X-Out-MB': mb(Traffic.sum(this.out) + Traffic.sum(this.http)),
      'X-In-MB': mb(Traffic.sum(this.inn)),
      'X-Conns': String(this.conns),
      'X-Peak-Conns': String(this.peakConns),
      'X-Up-S': String(Math.round((Date.now() - this.started) / 1000)),
      'X-D1-Read': String(d1Usage.rowsRead),
      'X-D1-Written': String(d1Usage.rowsWritten),
      'X-Total-Conns': String(this.totalConns),
      'X-Checks': String(this.checks),
      'X-Installs-Today': String(this.seen.size),
      'X-Installs-Seen': String(this.seenAll.size),
      'X-Patch-Dl': String(this.patchDownloads),
      'X-Matches': String(this.inn.get('match_start')?.n ?? 0),
      'X-Rooms-Made': String(this.inn.get('create_room')?.n ?? 0),
    };
  }

  snapshot(): Record<string, unknown> {
    const table = (map: Map<string, Tally>) =>
      Object.fromEntries([...map.entries()].sort((a, b) => b[1].bytes - a[1].bytes));
    const cpu = process.cpuUsage();
    const mem = process.memoryUsage();
    return {
      upSeconds: (Date.now() - this.started) / 1000,
      conns: this.conns,
      peakConns: this.peakConns,
      totalConns: this.totalConns,
      outBytes: Traffic.sum(this.out),
      httpBytes: Traffic.sum(this.http),
      inBytes: Traffic.sum(this.inn),
      cpuUserMs: cpu.user / 1000,
      cpuSystemMs: cpu.system / 1000,
      rssMB: mem.rss / 1048576,
      heapMB: mem.heapUsed / 1048576,
      d1: { queries: d1Usage.queries, rowsRead: d1Usage.rowsRead, rowsWritten: d1Usage.rowsWritten, failed: d1Usage.failed, byTable: Object.fromEntries(d1Usage.byTable) },
      out: table(this.out),
      in: table(this.inn),
      http: table(this.http),
    };
  }
}

export const traffic = new Traffic();

export const d1Usage = { queries: 0, rowsRead: 0, rowsWritten: 0, failed: 0, byTable: new Map<string, { q: number; read: number; written: number }>() };

const TABLE_RE = /\b(?:FROM|INTO|UPDATE|TABLE(?: IF NOT EXISTS)?)\s+([A-Za-z_][A-Za-z0-9_]*)/i;

export function countD1(sql: string, meta: { rows_read?: number; rows_written?: number } | undefined, ok: boolean): void {
  d1Usage.queries++;
  if (!ok) {
    d1Usage.failed++;
    return;
  }
  const read = Number(meta?.rows_read ?? 0) || 0;
  const written = Number(meta?.rows_written ?? 0) || 0;
  d1Usage.rowsRead += read;
  d1Usage.rowsWritten += written;
  const table = (TABLE_RE.exec(sql)?.[1] ?? '?').toLowerCase();
  const t = d1Usage.byTable.get(table) ?? { q: 0, read: 0, written: 0 };
  t.q++;
  t.read += read;
  t.written += written;
  d1Usage.byTable.set(table, t);
}
