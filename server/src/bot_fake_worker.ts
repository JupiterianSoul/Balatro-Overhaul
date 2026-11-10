const bots = new Map<string, { i: number; chips: number; hands: number; q: string[] | null }>();
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
    if (m.cmd === 'new') bots.set(m.bot as string, { i: 0, chips: 0, hands: 4, q: null });
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
      while (Date.now() < end) { /* busy */ }
    } else if (m.cmd === 'end_data' && b) {
      r = { ok: true, jokers: [{ k: 'j_joker', ed: 'foil' }], deck: { back: 'b_red', cards: [{ f: 'H_A' }, { f: 'S_K', e: 'm_steel', s: 'Red' }] } };
    } else if (m.cmd === 'drop') bots.delete(m.bot as string);
    process.stdout.write(JSON.stringify({ ...r, id: m.id }) + '\n');
  }
});
