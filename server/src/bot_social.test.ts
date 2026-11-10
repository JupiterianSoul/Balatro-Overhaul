import { describe, it, expect, beforeEach } from 'bun:test';
import { botSocial, initBotSocial, resetBotSocial, onHumanEmote, onSituation, onMatchEnd, BOT_LINES, EMOTE_REPLY, SITUATION_LINES, type SocialBot } from './bot_social';

interface Fake extends SocialBot { sent: string[]; lines: string[]; notes: string[]; chatOn: boolean }

let bots: Fake[] = [];
initBotSocial(() => bots);

function fake(name: string, room: string, humans = 1, chatOn = false): Fake {
  const b: Fake = {
    readyState: 1, data: { roomCode: room, partyCode: null, name }, ranked: false, sent: [], lines: [], notes: [], chatOn,
    emote(id) { this.sent.push(id); },
    chat(text) { if (!this.chatOn) return false; this.lines.push(text); return true; },
    humans() { return humans; },
    note(msg) { this.notes.push(msg); },
  };
  bots.push(b);
  return b;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
let seq = 0;
function rng(values: number[]): () => number { let i = 0; return () => values[i++ % values.length]; }
function total(list: Fake[]): number { return list.reduce((n, b) => n + b.sent.length + b.lines.length, 0); }

beforeEach(() => {
  bots = [];
  resetBotSocial();
  botSocial.level = 1;
  botSocial.scale = 0.001;
  botSocial.rand = rng([0.1, 0.5, 0.3, 0.7, 0.2]);
  seq++;
});

describe('bot social', () => {
  it('a 1v1 bot answers a human emote once, after a short delay', async () => {
    const b = fake('Bob', `r${seq}`);
    expect(onHumanEmote(b, 'Ann', 'hi')).toBe(true);
    expect(b.sent.length).toBe(0);
    await sleep(30);
    expect(b.sent).toEqual(['hi']);
  });

  it('never answers itself or another bot', async () => {
    const a = fake('Bob', `r${seq}`, 1);
    fake('Lou', `r${seq}`, 1);
    expect(onHumanEmote(a, 'Lou', 'hi')).toBe(false);
    expect(onHumanEmote(a, 'Bob', 'hi')).toBe(false);
    await sleep(30);
    expect(total(bots)).toBe(0);
  });

  it('a burst of human emotes gets one answer, not one per emote', async () => {
    const b = fake('Bob', `r${seq}`);
    onHumanEmote(b, 'Ann', 'laugh');
    for (let i = 0; i < 4; i++) { await sleep(850); onHumanEmote(b, 'Ann', 'laugh'); }
    await sleep(30);
    expect(b.sent.length).toBe(1);
  });

  it('every bot of a lobby hears the emote but only one or two react', async () => {
    const room = `r${seq}`;
    const crowd = [1, 2, 3, 4, 5, 6, 7].map(i => fake(`Bot${i}`, room, 1));
    botSocial.rand = rng([0.05]);
    for (const b of crowd) onHumanEmote(b, 'Ann', 'fire');
    await sleep(40);
    expect(total(crowd)).toBe(1);
    bots = [];
    resetBotSocial();
    const small = [1, 2, 3].map(i => fake(`Small${i}`, `s${seq}`, 1));
    for (const b of small) onHumanEmote(b, 'Ann', 'fire');
    await sleep(40);
    expect(total(small)).toBe(2);
  });

  it('sometimes does not react at all', async () => {
    const b = fake('Bob', `r${seq}`);
    botSocial.rand = rng([0.95]);
    expect(onHumanEmote(b, 'Ann', 'gg')).toBe(false);
    await sleep(30);
    expect(b.sent.length).toBe(0);
  });

  it('does nothing in ranked or when turned off', async () => {
    const b = fake('Bob', `r${seq}`);
    b.ranked = true;
    expect(onHumanEmote(b, 'Ann', 'hi')).toBe(false);
    expect(onSituation(b, 'big_hand')).toBe(false);
    const c = fake('Lou', `q${seq}`);
    botSocial.level = 0;
    expect(onHumanEmote(c, 'Ann', 'hi')).toBe(false);
    expect(onSituation(c, 'boss')).toBe(false);
    await sleep(30);
    expect(total(bots)).toBe(0);
  });

  it('acts on its own in a 1v1, then waits before the next time', async () => {
    const b = fake('Bob', `r${seq}`);
    expect(onSituation(b, 'life_lost')).toBe(true);
    expect(onSituation(b, 'boss')).toBe(false);
    await sleep(30);
    expect(b.sent.length + b.lines.length).toBe(1);
  });

  it('a big lobby is quieter: one bot act blocks the others for a while', async () => {
    const room = `r${seq}`;
    const crowd = [1, 2, 3, 4, 5, 6].map(i => fake(`Bot${i}`, room, 2));
    botSocial.rand = rng([0.01]);
    const took = crowd.map(b => onSituation(b, 'big_hand'));
    expect(took.filter(Boolean).length).toBe(1);
    botSocial.rand = rng([0.5]);
    const c2 = fake('Solo', `x${seq}`, 7);
    expect(onSituation(c2, 'shop')).toBe(false);
  });

  it('writes a chat line when chat reaches someone, an emote otherwise', async () => {
    botSocial.rand = rng([0.01]);
    const talk = fake('Bob', `r${seq}`, 1, true);
    onSituation(talk, 'waiting');
    const mute = fake('Lou', `q${seq}`, 1, false);
    onSituation(mute, 'waiting');
    await sleep(30);
    expect(talk.lines.length).toBe(1);
    expect(SITUATION_LINES.waiting).toContain(talk.lines[0]);
    expect(mute.lines.length).toBe(0);
    expect(mute.sent.length).toBe(1);
  });

  it('one gg in a 1v1, at most two in a small party, one in a big one', async () => {
    const one = fake('Bob', `r${seq}`, 1);
    onMatchEnd(one);
    onMatchEnd(one);
    const party = [1, 2, 3].map(i => fake(`P${i}`, `p${seq}`, 1));
    for (const b of party) onMatchEnd(b);
    const big = [1, 2, 3, 4, 5, 6].map(i => fake(`B${i}`, `b${seq}`, 2));
    for (const b of big) onMatchEnd(b);
    await sleep(60);
    expect(one.sent).toEqual(['gg']);
    expect(party.reduce((n, b) => n + b.sent.length, 0)).toBe(2);
    expect(big.reduce((n, b) => n + b.sent.length, 0)).toBe(1);
  });

  it('only sends emote ids the server accepts and short lines', () => {
    const ok = new Set(['hi', 'laugh', 'cry', 'nope', 'chips', 'fire', 'money', 'gg', 'think', 'lucky', 'oops', 'hurry']);
    for (const list of Object.values(EMOTE_REPLY)) for (const id of list) expect(ok.has(id)).toBe(true);
    for (const l of BOT_LINES) { expect(l.length).toBeLessThan(30); expect(l.includes(String.fromCharCode(0x2014))).toBe(false); }
  });
});
