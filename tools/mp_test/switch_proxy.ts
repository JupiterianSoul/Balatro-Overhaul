const listenPort = Number(process.env.SW_PORT);
const targets: Record<string, string> = { A: process.env.SW_A ?? '', B: process.env.SW_B ?? '' };
const lagMs = Number(process.env.SW_LAG_MS ?? 0);
let current = 'A';

type Data = { path: string; peer?: WebSocket; pending: (string | ArrayBuffer | Uint8Array)[]; up: boolean; target: string; id: number };

let nextId = 1;
const live = new Map<number, { target: string }>();

function valid(code: number): number {
  if (code === 1000 || (code >= 3000 && code <= 4999)) return code;
  return 1000;
}

function delay(fn: () => void): void {
  if (lagMs > 0) setTimeout(fn, lagMs); else fn();
}

const server = Bun.serve<Data>({
  port: listenPort,
  hostname: '127.0.0.1',
  fetch(req, srv) {
    const url = new URL(req.url);
    if (url.pathname === '/switch') {
      const to = (url.searchParams.get('to') ?? '').toUpperCase();
      if (!targets[to]) return new Response('unknown target', { status: 400 });
      const from = current;
      current = to;
      console.log(`[proxy] switch ${from} -> ${to} (live: ${[...live.values()].map((v) => v.target).join(',') || 'none'})`);
      return new Response(`current=${current}\n`);
    }
    if (url.pathname === '/status') {
      const counts: Record<string, number> = { A: 0, B: 0 };
      for (const v of live.values()) counts[v.target]++;
      return new Response(JSON.stringify({ current, live: counts }) + '\n');
    }
    const ok = srv.upgrade(req, { data: { path: url.pathname + url.search, pending: [], up: false, target: current, id: nextId++ } });
    return ok ? undefined : new Response('switch proxy', { status: 400 });
  },
  websocket: {
    maxPayloadLength: 64 * 1024 * 1024,
    open(ws) {
      const d = ws.data;
      live.set(d.id, { target: d.target });
      console.log(`[proxy] conn ${d.id} open -> ${d.target}`);
      const peer = new WebSocket(targets[d.target] + d.path);
      d.peer = peer;
      peer.binaryType = 'arraybuffer';
      peer.onopen = () => {
        d.up = true;
        for (const m of d.pending) peer.send(m);
        d.pending = [];
      };
      peer.onmessage = (ev) => delay(() => { if (ws.readyState === 1) ws.send(ev.data as string); });
      peer.onclose = (ev) => {
        console.log(`[proxy] conn ${d.id} upstream ${d.target} closed code=${ev.code} reason=${ev.reason}`);
        delay(() => ws.close(valid(ev.code), ev.reason));
      };
      peer.onerror = () => { if (!d.up) ws.close(1011, 'upstream_unreachable'); };
    },
    message(ws, msg) {
      const d = ws.data;
      if (!d.up || !d.peer) { d.pending.push(msg); return; }
      delay(() => { if (d.peer && d.peer.readyState === 1) d.peer.send(msg); });
    },
    close(ws, code, reason) {
      const d = ws.data;
      live.delete(d.id);
      console.log(`[proxy] conn ${d.id} client closed code=${code} reason=${reason}`);
      try { d.peer?.close(valid(code), reason); } catch {}
    },
  },
});

console.log(`switch proxy on ${server.port} A=${targets.A} B=${targets.B} current=${current}`);
