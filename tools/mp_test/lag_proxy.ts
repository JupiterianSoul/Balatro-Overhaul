const listenPort = Number(process.env.LAG_PORT);
const upstream = process.env.LAG_UPSTREAM ?? '';
const baseMs = Number(process.env.LAG_MS ?? 300);
const jitterMs = process.env.LAG_JITTER_MS ? Number(process.env.LAG_JITTER_MS) : baseMs / 2;

type Side = { ws: WebSocket | null; pending: (string | ArrayBuffer | Uint8Array)[]; last: number };
type Data = { up: Side; down: Side; path: string; peer?: WebSocket };

function later(side: Side, send: (m: string | ArrayBuffer | Uint8Array) => void, msg: string | ArrayBuffer | Uint8Array): void {
  const at = Math.max(side.last, Date.now() + baseMs + Math.random() * jitterMs);
  side.last = at;
  setTimeout(() => send(msg), at - Date.now());
}

let relayed = 0;
const server = Bun.serve<Data>({
  port: listenPort,
  hostname: '127.0.0.1',
  fetch(req, srv) {
    const url = new URL(req.url);
    const ok = srv.upgrade(req, { data: { up: { ws: null, pending: [], last: 0 }, down: { ws: null, pending: [], last: 0 }, path: url.pathname + url.search } });
    return ok ? undefined : new Response('lag proxy', { status: 400 });
  },
  websocket: {
    maxPayloadLength: 64 * 1024 * 1024,
    open(ws) {
      const d = ws.data;
      const peer = new WebSocket(upstream + d.path);
      d.peer = peer;
      peer.binaryType = 'arraybuffer';
      peer.onopen = () => {
        d.up.ws = peer;
        for (const m of d.up.pending) later(d.up, (x) => peer.readyState === 1 && peer.send(x), m);
        d.up.pending = [];
      };
      peer.onmessage = (ev) => {
        relayed++;
        later(d.down, (x) => ws.readyState === 1 && ws.send(x as string), ev.data as string);
      };
      peer.onclose = () => later(d.down, () => ws.close(), '');
      peer.onerror = () => ws.close();
    },
    message(ws, msg) {
      const d = ws.data;
      relayed++;
      if (!d.up.ws) { d.up.pending.push(msg); return; }
      later(d.up, (x) => d.up.ws && d.up.ws.readyState === 1 && d.up.ws.send(x), msg);
    },
    close(ws) {
      const d = ws.data;
      later(d.up, () => d.peer?.close(), '');
    },
  },
});

console.log(`lag proxy on ${server.port} -> ${upstream}, ${baseMs} ms + up to ${jitterMs} ms`);
setInterval(() => console.log(`relayed ${relayed}`), 30000);
