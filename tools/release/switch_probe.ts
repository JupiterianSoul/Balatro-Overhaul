const url = "wss://balatro-overhaul-muliplayer.onrender.com/ws";
const t0 = Date.now();
const stamp = () => new Date().toTimeString().slice(0, 8);
const ws = new WebSocket(url);
const keep = setInterval(() => { try { ws.send(JSON.stringify({ type: "ping" })); } catch {} }, 20000);
ws.onopen = () => console.log(`${stamp()} watching the live server`);
ws.onclose = () => {
  clearInterval(keep);
  console.log(`${stamp()} old server closed the connection after ${Math.round((Date.now() - t0) / 1000)} s`);
  setTimeout(() => {
    const w2 = new WebSocket(url);
    w2.onopen = () => w2.send(JSON.stringify({ type: "ping" }));
    w2.onmessage = (ev) => {
      if (String(ev.data).includes("pong")) { console.log(`${stamp()} new server answers`); process.exit(0); }
    };
    setTimeout(() => { console.log(`${stamp()} no answer after the switch`); process.exit(1); }, 30000);
  }, 5000);
};
setTimeout(() => { console.log(`${stamp()} no switch within 25 minutes`); process.exit(2); }, 25 * 60 * 1000);
