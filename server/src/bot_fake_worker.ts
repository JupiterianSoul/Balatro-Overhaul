const bots = new Map<string, { i: number; chips: number; hands: number; q: string[] | null; seed: string; fresh: boolean }>();
const NEEDS_BOT = new Set(['advance', 'hand', 'save', 'end_data']);
const BL = ['S', 'B', 'L'];
const KEYS = ['bl_small', 'bl_big', 'bl_hook'];
const STOPS = new Set(['shop', 'pack', 'blind_select']);
const ACTS: Record<string, Record<string, unknown>> = {
  cash_out: { cost: -8, from: 'round_eval', phase: 'shop' },
  buy: { key: 'j_joker', cost: 5, from: 'shop', phase: 'shop' },
  open: { key: 'p_buffoon_normal_1', cost: 4, from: 'shop', phase: 'pack' },
  pick: { key: 'j_egg', cost: 0, from: 'pack', phase: 'shop' },
  leave: { cost: 0, from: 'shop', phase: 'blind_select', held: ['j_joker', 'j_egg'] },
  select: { cost: 0, from: 'blind_select', phase: 'play' },
};
let buf = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk: string) => {
  buf += chunk;
  let i: number;
  while ((i = buf.indexOf('\n')) >= 0) {
    const m = JSON.parse(buf.slice(0, i)) as Record<string, unknown>;
    buf = buf.slice(i + 1);
    const b = bots.get(m.bot as string);
    let r: Record<string, unknown> = { ok: true };
    const seed = String(m.seed ?? '');
    if (m.cmd === 'die') process.exit(1);
    if (m.cmd === 'new' && seed.startsWith('NONEW')) r = { ok: false, err: 'no new' };
    else if (m.cmd === 'new') bots.set(m.bot as string, { i: 0, chips: 0, hands: 4, q: null, seed, fresh: true });
    else if (m.cmd === 'resume' && seed.includes('NORESUME')) r = { ok: false, err: 'no resume' };
    else if (m.cmd === 'resume') {
      const i = (Math.max(1, Number(m.ante) || 1) - 1) * 3 + Math.max(1, Number(m.blind_n) || 1) - 1;
      bots.set(m.bot as string, { i, chips: 0, hands: 4, q: null, seed, fresh: false });
      r = { ok: true, ante: Math.floor(i / 3) + 1, blind_n: (i % 3) + 1, had_run: !!m.run };
    } else if (NEEDS_BOT.has(String(m.cmd)) && !b) r = { ok: false, err: 'no bot' };
    else if (m.cmd === 'save' && b) r = { ok: true, run: { i: b.i } };
    else if (m.cmd === 'advance' && b && b.fresh && b.seed.startsWith('DONE') && b.i === 2) r = { ok: true, done: true };
    else if (m.cmd === 'hand' && b && b.fresh && b.seed.startsWith('BADHAND') && b.hands === 3) r = { ok: false, err: 'no action' };
    else if (m.cmd === 'advance' && b) {
      const at = { ante: Math.floor(b.i / 3) + 1, blind: BL[b.i % 3], blind_key: KEYS[b.i % 3] };
      if (m.stops && m.one && !b.q) {
        b.q = b.i === 0 ? ['blind_select', 'select']
          : b.i === 3 ? ['cash_out', 'shop', 'buy', 'open', 'pack', 'pick', 'shop', 'leave', 'blind_select', 'select']
            : ['cash_out', 'shop', 'leave', 'blind_select', 'select'];
      }
      if (m.stops && !b.q) b.q = b.i === 0 ? ['blind_select'] : b.i === 3 ? ['shop', 'pack', 'shop', 'blind_select'] : ['shop', 'blind_select'];
      const stop = m.stops && b.q ? b.q.shift() : undefined;
      const act = stop && ACTS[stop] ? { type: stop, ante: at.ante, money: 10, jokers: 2, ...ACTS[stop] } : undefined;
      if (act && stop !== 'select') r = { ok: true, more: true, act, ante: at.ante };
      else if (stop && !act) r = { ok: true, stop, ...at };
      else {
        if (act) r.act = act;
        r = { ...r, ok: true, ...at, hands: 4, discards: 3, money: 10 };
        b.i++; b.chips = 0; b.hands = 4; b.q = null;
      }
    } else if (m.cmd === 'hand' && b) {
      b.chips += 50; b.hands--;
      r = { ok: true, chips: b.chips, hands_left: b.hands, discards_left: 3, over: b.hands === 0, lost: false };
    } else if (m.cmd === 'spin') {
      const end = Date.now() + Number(m.ms);
      while (Date.now() < end) {  }
    } else if (m.cmd === 'end_data' && b) {
      r = { ok: true, jokers: [{ k: 'j_joker', ed: 'foil' }], deck: { back: 'b_red', cards: [{ f: 'H_A' }, { f: 'S_K', e: 'm_steel', s: 'Red' }] } };
    } else if (m.cmd === 'drop') bots.delete(m.bot as string);
    process.stdout.write(JSON.stringify({ ...r, id: m.id }) + '\n');
  }
});
