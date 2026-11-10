import { describe, it, expect } from 'bun:test';
import { SocialService, friendCode, type SocialSocket } from './social';
import { MemoryStore } from './ranked_store';
import { MemoryExtra } from './social_store';
import type { LobbyInfo } from './chat';

interface FakeWS extends SocialSocket { sent: Record<string, any>[]; lobby: LobbyInfo<FakeWS> | null }

const A = 'a'.repeat(24), B = 'b'.repeat(24), C = 'c'.repeat(24);
const flush = () => new Promise(r => setTimeout(r, 0));

function sock(): FakeWS {
  return { data: {}, sent: [], lobby: null };
}

function setup() {
  const store = new MemoryStore();
  const clock = { t: Date.UTC(2026, 10, 2, 12) };
  const alive = new Set<string>();
  const svc = new SocialService<FakeWS>(store, {
    send: (ws, d) => { ws.sent.push(d as Record<string, any>); },
    where: () => 'menu',
    inviteTarget: () => null,
    roomPeers: () => [],
    lobby: ws => ws.lobby,
    lobbyAlive: id => alive.has(id),
  }, () => clock.t);
  return { store, clock, svc, alive, extra: svc.extra as MemoryExtra };
}

type Env = ReturnType<typeof setup>;

function last(ws: FakeWS, type: string): any {
  return [...ws.sent].reverse().find(m => m.type === type);
}

function all(ws: FakeWS, type: string) {
  return ws.sent.filter(m => m.type === type);
}

async function send(env: Env, ws: FakeWS, type: string, extra: Record<string, unknown> = {}) {
  env.svc.handle(ws, { type, ...extra });
  await flush();
}

async function hello(env: Env, ws: FakeWS, pkey: string, name: string) {
  await send(env, ws, 'social_hello', { pkey, name });
}

async function befriend(env: Env, a: FakeWS, aKey: string, b: FakeWS, bKey: string) {
  await send(env, a, 'social_add', { code: friendCode(bKey) });
  await send(env, b, 'social_accept', { code: friendCode(aKey) });
}

async function optIn(env: Env, ws: FakeWS, year = 1990) {
  await send(env, ws, 'chat_optin', { enabled: true, birth_year: year });
}

async function pair() {
  const env = setup();
  const a = sock(), b = sock();
  await hello(env, a, A, 'Ann');
  await hello(env, b, B, 'Bob');
  await befriend(env, a, A, b, B);
  await optIn(env, a);
  await optIn(env, b);
  return { env, a, b };
}

function lobbyOf(id: string, members: FakeWS[], matchId: string | null = null) {
  members.forEach((m, i) => { m.lobby = { id, me: i, seats: members.map((s, j) => ({ pid: j, ws: s })), matchId }; });
}

describe('chat opt-in and age gate', () => {
  it('starts with chat off and the age not asked', async () => {
    const env = setup();
    const a = sock();
    await hello(env, a, A, 'Ann');
    expect(last(a, 'chat_state')).toMatchObject({ enabled: false, allowed: null });
  });

  it('asks for a birth year the first time', async () => {
    const env = setup();
    const a = sock();
    await hello(env, a, A, 'Ann');
    await send(env, a, 'chat_optin', { enabled: true });
    expect(last(a, 'chat_result')).toMatchObject({ action: 'optin', ok: false, reason: 'age_needed' });
    expect(last(a, 'chat_state')).toMatchObject({ enabled: false, allowed: null });
  });

  it('refuses an impossible birth year', async () => {
    const env = setup();
    const a = sock();
    await hello(env, a, A, 'Ann');
    for (const y of [1800, 2099, 'abc', 1990.5]) {
      await send(env, a, 'chat_optin', { enabled: true, birth_year: y });
      expect(last(a, 'chat_result')).toMatchObject({ ok: false, reason: 'bad_year' });
    }
    expect(last(a, 'chat_state')).toMatchObject({ allowed: null });
  });

  it('allows 13 and older and stores only a yes', async () => {
    const env = setup();
    const a = sock();
    await hello(env, a, A, 'Ann');
    await send(env, a, 'chat_optin', { enabled: true, birth_year: 2013 });
    expect(last(a, 'chat_state')).toMatchObject({ enabled: true, allowed: true });
    expect(JSON.stringify([...env.extra.prefs.values()])).not.toContain('2013');
    expect(Object.keys(env.extra.prefs.get(A) ?? {}).sort()).toEqual(['chat_allowed', 'chat_enabled', 'nameKey', 'rp']);
  });

  it('blocks under 13 for good', async () => {
    const env = setup();
    const a = sock();
    await hello(env, a, A, 'Ann');
    await send(env, a, 'chat_optin', { enabled: true, birth_year: 2020 });
    expect(last(a, 'chat_result')).toMatchObject({ ok: false, reason: 'not_allowed' });
    expect(last(a, 'chat_state')).toMatchObject({ enabled: false, allowed: false });
    await send(env, a, 'chat_optin', { enabled: true, birth_year: 1990 });
    expect(last(a, 'chat_state')).toMatchObject({ enabled: false, allowed: false });
    await send(env, a, 'chat_optin', { enabled: true });
    expect(last(a, 'chat_result')).toMatchObject({ ok: false, reason: 'not_allowed' });
  });

  it('can be switched off and on again without a new year', async () => {
    const env = setup();
    const a = sock();
    await hello(env, a, A, 'Ann');
    await optIn(env, a);
    await send(env, a, 'chat_optin', { enabled: false });
    expect(last(a, 'chat_state')).toMatchObject({ enabled: false, allowed: true });
    await send(env, a, 'chat_optin', { enabled: true });
    expect(last(a, 'chat_state')).toMatchObject({ enabled: true, allowed: true });
  });

  it('is remembered on the next connection', async () => {
    const env = setup();
    const a = sock();
    await hello(env, a, A, 'Ann');
    await optIn(env, a);
    env.svc.drop(a);
    const again = sock();
    await hello(env, again, A, 'Ann');
    expect(last(again, 'chat_state')).toMatchObject({ enabled: true, allowed: true });
  });
});

describe('friend messages', () => {
  it('delivers to both sides with friend codes', async () => {
    const { env, a, b } = await pair();
    await send(env, a, 'chat_dm_send', { to: friendCode(B), text: 'hello there' });
    for (const ws of [a, b]) {
      expect(last(ws, 'chat_dm')).toMatchObject({ from: friendCode(A), to: friendCode(B), text: 'hello there' });
      expect(typeof last(ws, 'chat_dm')?.id).toBe('string');
      expect(typeof last(ws, 'chat_dm')?.at).toBe('number');
    }
  });

  it('needs chat on for the sender', async () => {
    const env = setup();
    const a = sock(), b = sock();
    await hello(env, a, A, 'Ann');
    await hello(env, b, B, 'Bob');
    await befriend(env, a, A, b, B);
    await send(env, a, 'chat_dm_send', { to: friendCode(B), text: 'hi' });
    expect(last(a, 'chat_result')).toMatchObject({ action: 'send', ok: false, reason: 'not_opted_in' });
    await send(env, a, 'chat_optin', { enabled: true, birth_year: 2020 });
    await send(env, a, 'chat_dm_send', { to: friendCode(B), text: 'hi' });
    expect(last(a, 'chat_result')).toMatchObject({ ok: false, reason: 'not_allowed' });
  });

  it('refuses when the other side has chat off', async () => {
    const env = setup();
    const a = sock(), b = sock();
    await hello(env, a, A, 'Ann');
    await hello(env, b, B, 'Bob');
    await befriend(env, a, A, b, B);
    await optIn(env, a);
    await send(env, a, 'chat_dm_send', { to: friendCode(B), text: 'hi' });
    expect(last(a, 'chat_result')).toMatchObject({ ok: false, reason: 'recipient_off' });
    expect(all(b, 'chat_dm')).toHaveLength(0);
  });

  it('refuses people who are not friends', async () => {
    const env = setup();
    const a = sock(), c = sock();
    await hello(env, a, A, 'Ann');
    await hello(env, c, C, 'Cy');
    await optIn(env, a);
    await optIn(env, c);
    await send(env, a, 'chat_dm_send', { to: friendCode(C), text: 'hi' });
    expect(last(a, 'chat_result')).toMatchObject({ ok: false, reason: 'not_friend' });
    await send(env, a, 'chat_dm_send', { to: 'nonsense', text: 'hi' });
    expect(last(a, 'chat_result')).toMatchObject({ ok: false, reason: 'not_friend' });
  });

  it('limits messages to 200 characters', async () => {
    const { env, a, b } = await pair();
    await send(env, a, 'chat_dm_send', { to: friendCode(B), text: 'x'.repeat(201) });
    expect(last(a, 'chat_result')).toMatchObject({ ok: false, reason: 'too_long' });
    await send(env, a, 'chat_dm_send', { to: friendCode(B), text: 'x'.repeat(200) });
    expect(last(b, 'chat_dm')?.text).toHaveLength(200);
  });

  it('counts characters, not UTF-16 units', async () => {
    const { env, a, b } = await pair();
    await send(env, a, 'chat_dm_send', { to: friendCode(B), text: '\u{1F600}'.repeat(200) });
    expect(all(b, 'chat_dm')).toHaveLength(1);
  });

  it('refuses empty and non text messages', async () => {
    const { env, a } = await pair();
    for (const text of ['', '   ', '\n\t', undefined, 5, null]) {
      await send(env, a, 'chat_dm_send', { to: friendCode(B), text });
      expect(last(a, 'chat_result')).toMatchObject({ ok: false, reason: 'empty' });
    }
  });

  it('masks insults and delivers the filtered text', async () => {
    const { env, a, b } = await pair();
    await send(env, a, 'chat_dm_send', { to: friendCode(B), text: 'you are a fucking donkey' });
    expect(last(b, 'chat_dm')?.text).toBe('you are a ####### donkey');
    expect(last(a, 'chat_dm')?.text).toBe('you are a ####### donkey');
  });

  it('blocks slurs, threats and phone numbers without delivering', async () => {
    const { env, a, b } = await pair();
    for (const text of ['you retard', 'kys', 'call me 555 123 4567', 'mail bob@gmail.com']) {
      await send(env, a, 'chat_dm_send', { to: friendCode(B), text });
      expect(last(a, 'chat_result')).toMatchObject({ action: 'send', ok: false, reason: 'blocked' });
      env.clock.t += 6 * 60_000;
    }
    expect(all(b, 'chat_dm')).toHaveLength(0);
    expect(env.extra.dms).toHaveLength(0);
  });

  it('allows about 5 messages in 10 seconds', async () => {
    const { env, a, b } = await pair();
    for (let i = 0; i < 5; i++) await send(env, a, 'chat_dm_send', { to: friendCode(B), text: `m${i}` });
    expect(all(b, 'chat_dm')).toHaveLength(5);
    await send(env, a, 'chat_dm_send', { to: friendCode(B), text: 'one more' });
    expect(last(a, 'chat_result')).toMatchObject({ ok: false, reason: 'rate_limited' });
    env.clock.t += 10_001;
    await send(env, a, 'chat_dm_send', { to: friendCode(B), text: 'later' });
    expect(last(b, 'chat_dm')?.text).toBe('later');
  });

  it('shares the rate limit between direct and lobby messages', async () => {
    const { env, a, b } = await pair();
    lobbyOf('r1', [a, b]);
    for (let i = 0; i < 3; i++) await send(env, a, 'chat_dm_send', { to: friendCode(B), text: `m${i}` });
    for (let i = 0; i < 2; i++) await send(env, a, 'chat_lobby_send', { text: `l${i}` });
    await send(env, a, 'chat_lobby_send', { text: 'too many' });
    expect(last(a, 'chat_result')).toMatchObject({ ok: false, reason: 'rate_limited', scope: 'lobby' });
  });

  it('mutes a sender for a minute after three blocked messages', async () => {
    const { env, a, b } = await pair();
    for (let i = 0; i < 3; i++) {
      await send(env, a, 'chat_dm_send', { to: friendCode(B), text: 'kys' });
      env.clock.t += 1000;
    }
    await send(env, a, 'chat_dm_send', { to: friendCode(B), text: 'sorry' });
    expect(last(a, 'chat_result')).toMatchObject({ ok: false, reason: 'muted' });
    env.clock.t += 61_000;
    await send(env, a, 'chat_dm_send', { to: friendCode(B), text: 'sorry' });
    expect(last(b, 'chat_dm')?.text).toBe('sorry');
  });

  it('counts unread messages per friend and clears them', async () => {
    const { env, a, b } = await pair();
    for (let i = 0; i < 3; i++) { await send(env, a, 'chat_dm_send', { to: friendCode(B), text: `m${i}` }); env.clock.t += 3000; }
    await send(env, b, 'social_list');
    expect(last(b, 'social_list')?.friends[0].unread).toBe(3);
    await send(env, a, 'social_list');
    expect(last(a, 'social_list')?.friends[0].unread).toBe(0);
    await send(env, b, 'chat_dm_read', { with: friendCode(A) });
    expect(last(b, 'chat_result')).toMatchObject({ action: 'read', ok: true });
    await send(env, b, 'social_list');
    expect(last(b, 'social_list')?.friends[0].unread).toBe(0);
  });

  it('keeps the unread count while the friend is offline', async () => {
    const { env, a, b } = await pair();
    env.svc.drop(b);
    await send(env, a, 'chat_dm_send', { to: friendCode(B), text: 'are you there' });
    const again = sock();
    await hello(env, again, B, 'Bob');
    expect(last(again, 'social_list')?.friends[0].unread).toBe(1);
    await send(env, again, 'chat_dm_history', { with: friendCode(A) });
    expect(last(again, 'chat_dm_history')?.items.map((i: any) => i.text)).toEqual(['are you there']);
  });

  it('returns the history oldest first with friend codes', async () => {
    const { env, a, b } = await pair();
    await send(env, a, 'chat_dm_send', { to: friendCode(B), text: 'one' });
    env.clock.t += 3000;
    await send(env, b, 'chat_dm_send', { to: friendCode(A), text: 'two' });
    await send(env, a, 'chat_dm_history', { with: friendCode(B) });
    const h = last(a, 'chat_dm_history');
    expect(h?.with).toBe(friendCode(B));
    expect(h?.items.map((i: any) => [i.from, i.text])).toEqual([[friendCode(A), 'one'], [friendCode(B), 'two']]);
    expect(Object.keys(h?.items[0]).sort()).toEqual(['at', 'from', 'id', 'text']);
  });

  it('pages the history with before', async () => {
    const { env, a } = await pair();
    const times: number[] = [];
    for (let i = 0; i < 4; i++) { times.push(env.clock.t); await send(env, a, 'chat_dm_send', { to: friendCode(B), text: `m${i}` }); env.clock.t += 3000; }
    await send(env, a, 'chat_dm_history', { with: friendCode(B), before: times[2] });
    expect(last(a, 'chat_dm_history')?.items.map((i: any) => i.text)).toEqual(['m0', 'm1']);
  });

  it('keeps the last 100 messages of a conversation', async () => {
    const { env, a } = await pair();
    for (let i = 0; i < 105; i++) { await send(env, a, 'chat_dm_send', { to: friendCode(B), text: `m${i}` }); env.clock.t += 3000; }
    await send(env, a, 'chat_dm_history', { with: friendCode(B) });
    const items = last(a, 'chat_dm_history')?.items;
    expect(items).toHaveLength(100);
    expect(items[0].text).toBe('m5');
    expect(items[99].text).toBe('m104');
    expect(env.extra.dms.length).toBeLessThanOrEqual(105);
  });

  it('prunes old rows from the store every few messages', async () => {
    const { env, a } = await pair();
    for (let i = 0; i < 125; i++) { await send(env, a, 'chat_dm_send', { to: friendCode(B), text: `m${i}` }); env.clock.t += 3000; }
    expect(env.extra.dms.length).toBeLessThanOrEqual(120);
    expect(env.extra.dms.length).toBeGreaterThanOrEqual(100);
  });

  it('does not expose a conversation to a third player', async () => {
    const { env, a } = await pair();
    const c = sock();
    await hello(env, c, C, 'Cy');
    await send(env, a, 'chat_dm_send', { to: friendCode(B), text: 'secret' });
    await send(env, c, 'chat_dm_history', { with: friendCode(A) });
    expect(last(c, 'chat_dm_history')?.items).toEqual([]);
    await send(env, c, 'chat_dm_history', { with: 'nonsense' });
    expect(last(c, 'chat_result')).toMatchObject({ ok: false, reason: 'unknown_player' });
  });

  it('a muted friend cannot message you and you cannot message them', async () => {
    const { env, a, b } = await pair();
    await send(env, b, 'chat_mute', { code: friendCode(A) });
    expect(last(b, 'chat_result')).toMatchObject({ action: 'mute', ok: true });
    await send(env, a, 'chat_dm_send', { to: friendCode(B), text: 'hello?' });
    expect(last(a, 'chat_dm')?.text).toBe('hello?');
    expect(all(b, 'chat_dm')).toHaveLength(0);
    await send(env, b, 'social_list');
    expect(last(b, 'social_list')?.friends[0].unread).toBe(0);
    await send(env, b, 'chat_dm_history', { with: friendCode(A) });
    expect(last(b, 'chat_dm_history')?.items).toEqual([]);
    await send(env, b, 'chat_dm_send', { to: friendCode(A), text: 'hi' });
    expect(last(b, 'chat_result')).toMatchObject({ ok: false, reason: 'muted' });
    await send(env, b, 'chat_unmute', { code: friendCode(A) });
    await send(env, b, 'chat_dm_send', { to: friendCode(A), text: 'hi again' });
    expect(last(a, 'chat_dm')?.text).toBe('hi again');
  });
});

describe('lobby chat', () => {
  async function trio() {
    const env = setup();
    const a = sock(), b = sock(), c = sock();
    await hello(env, a, A, 'Ann');
    await hello(env, b, B, 'Bob');
    await hello(env, c, C, 'Cy');
    await optIn(env, a);
    await optIn(env, b);
    await optIn(env, c);
    lobbyOf('room1', [a, b, c], 'match-7');
    return { env, a, b, c };
  }

  it('a bot line reaches only players who turned chat on, marked as a bot', async () => {
    const env = setup();
    const a = sock(), b = sock(), bot = sock();
    await hello(env, a, A, 'Ann');
    await hello(env, b, B, 'Bob');
    await optIn(env, a);
    lobbyOf('room9', [a, bot, b]);
    expect(env.svc.chat.botLine(bot, 'Lou', 'Nice hand!')).toBe(1);
    expect(last(a, 'chat_lobby')).toMatchObject({ pid: 1, name: 'Lou', text: 'Nice hand!', bot: true });
    expect(all(b, 'chat_lobby')).toHaveLength(0);
    expect(all(bot, 'chat_lobby')).toHaveLength(0);
    bot.lobby = null;
    expect(env.svc.chat.botLine(bot, 'Lou', 'Hi!')).toBe(0);
  });

  it('reaches everyone in the room, sender included', async () => {
    const { env, a, b, c } = await trio();
    await send(env, b, 'chat_lobby_send', { text: 'good luck' });
    for (const ws of [a, b, c]) expect(last(ws, 'chat_lobby')).toMatchObject({ pid: 1, name: 'Bob', text: 'good luck' });
    expect(Object.keys(last(a, 'chat_lobby') ?? {}).sort()).toEqual(['at', 'id', 'name', 'pid', 'text', 'type']);
  });

  it('needs a room', async () => {
    const { env, a } = await trio();
    a.lobby = null;
    await send(env, a, 'chat_lobby_send', { text: 'anyone?' });
    expect(last(a, 'chat_result')).toMatchObject({ action: 'send', ok: false, reason: 'no_lobby', scope: 'lobby' });
  });

  it('needs chat on, and skips players with chat off', async () => {
    const { env, a, b, c } = await trio();
    await send(env, c, 'chat_optin', { enabled: false });
    await send(env, a, 'chat_lobby_send', { text: 'hi all' });
    expect(all(b, 'chat_lobby')).toHaveLength(1);
    expect(all(c, 'chat_lobby')).toHaveLength(0);
    await send(env, c, 'chat_lobby_send', { text: 'me too' });
    expect(last(c, 'chat_result')).toMatchObject({ ok: false, reason: 'not_opted_in' });
  });

  it('filters the text and blocks bad messages', async () => {
    const { env, a, b } = await trio();
    await send(env, a, 'chat_lobby_send', { text: 'what the fuck' });
    expect(last(b, 'chat_lobby')?.text).toBe('what the ####');
    env.clock.t += 20_000;
    await send(env, a, 'chat_lobby_send', { text: 'kill yourself' });
    expect(last(a, 'chat_result')).toMatchObject({ ok: false, reason: 'blocked' });
    expect(all(b, 'chat_lobby')).toHaveLength(1);
  });

  it('does not deliver a muted sender, by seat or by code', async () => {
    const { env, a, b, c } = await trio();
    await send(env, b, 'chat_mute', { pid: 0 });
    await send(env, c, 'chat_mute', { code: friendCode(A) });
    await send(env, a, 'chat_lobby_send', { text: 'hello' });
    expect(all(a, 'chat_lobby')).toHaveLength(1);
    expect(all(b, 'chat_lobby')).toHaveLength(0);
    expect(all(c, 'chat_lobby')).toHaveLength(0);
    await send(env, b, 'chat_unmute', { pid: 0 });
    env.clock.t += 20_000;
    await send(env, a, 'chat_lobby_send', { text: 'again' });
    expect(all(b, 'chat_lobby')).toHaveLength(1);
  });

  it('never stores lobby messages and forgets them after the room ends', async () => {
    const { env, a, b } = await trio();
    env.alive.add('room1');
    await send(env, a, 'chat_lobby_send', { text: 'temporary' });
    expect(env.extra.dms).toHaveLength(0);
    expect(env.svc.chat.lobbyLogCount()).toBe(1);
    env.svc.tick();
    expect(env.svc.chat.lobbyLogCount()).toBe(1);
    env.alive.delete('room1');
    env.svc.tick();
    expect(env.svc.chat.lobbyLogCount()).toBe(1);
    env.clock.t += 121_000;
    env.svc.tick();
    expect(env.svc.chat.lobbyLogCount()).toBe(0);
    await send(env, b, 'chat_report', { msg_id: last(b, 'chat_lobby')?.id, reason: 'spam' });
    expect(last(b, 'chat_result')).toMatchObject({ action: 'report', ok: false, reason: 'unknown_message' });
  });
});

describe('mute list', () => {
  it('lists the muted players and survives a reconnect', async () => {
    const { env, a, b } = await pair();
    await send(env, a, 'chat_mute', { code: friendCode(B) });
    await send(env, a, 'chat_mute_list');
    expect(last(a, 'chat_mute_list')?.items).toEqual([{ code: friendCode(B), name: 'Bob' }]);
    env.svc.drop(a);
    const again = sock();
    await hello(env, again, A, 'Ann');
    await send(env, again, 'chat_mute_list');
    expect(last(again, 'chat_mute_list')?.items).toHaveLength(1);
    await send(env, again, 'chat_unmute', { code: friendCode(B) });
    await send(env, again, 'chat_mute_list');
    expect(last(again, 'chat_mute_list')?.items).toEqual([]);
    expect(b.sent.length).toBeGreaterThan(0);
  });

  it('refuses yourself, strangers and bots', async () => {
    const { env, a } = await pair();
    await send(env, a, 'chat_mute', { code: friendCode(A) });
    expect(last(a, 'chat_result')).toMatchObject({ action: 'mute', ok: false, reason: 'self' });
    await send(env, a, 'chat_mute', { code: 'ZZZZ-ZZZZ' });
    expect(last(a, 'chat_result')).toMatchObject({ ok: false, reason: 'unknown_player' });
    await send(env, a, 'chat_mute', { pid: 9 });
    expect(last(a, 'chat_result')).toMatchObject({ ok: false, reason: 'unknown_player' });
    await send(env, a, 'chat_mute', {});
    expect(last(a, 'chat_result')).toMatchObject({ ok: false, reason: 'unknown_player' });
  });
});

describe('reports', () => {
  it('stores a reported direct message with its context', async () => {
    const { env, a, b } = await pair();
    for (const t of ['first', 'second', 'third']) { await send(env, a, 'chat_dm_send', { to: friendCode(B), text: t }); env.clock.t += 3000; }
    const id = last(b, 'chat_dm')?.id;
    await send(env, b, 'chat_report', { msg_id: id, reason: 'harassment' });
    expect(last(b, 'chat_result')).toMatchObject({ action: 'report', ok: true });
    expect(env.extra.reports).toHaveLength(1);
    const r = env.extra.reports[0];
    expect(r).toMatchObject({ reporter: B, reported: A, kind: 'dm', msg_id: id, text: 'third', reason: 'harassment', match_id: null });
    expect(JSON.parse(r.context).map((c: any) => c.text)).toEqual(['first', 'second']);
  });

  it('stores a reported lobby message with the match log id', async () => {
    const env = setup();
    const a = sock(), b = sock();
    await hello(env, a, A, 'Ann');
    await hello(env, b, B, 'Bob');
    await optIn(env, a);
    await optIn(env, b);
    lobbyOf('room9', [a, b], 'm-123');
    env.alive.add('room9');
    await send(env, a, 'chat_lobby_send', { text: 'you are slow' });
    await send(env, b, 'chat_report', { msg_id: last(b, 'chat_lobby')?.id, reason: 'bullying' });
    expect(env.extra.reports[0]).toMatchObject({ reporter: B, reported: A, kind: 'lobby', text: 'you are slow', match_id: 'm-123' });
  });

  it('stores a null match id when the room has none', async () => {
    const env = setup();
    const a = sock(), b = sock();
    await hello(env, a, A, 'Ann');
    await hello(env, b, B, 'Bob');
    await optIn(env, a);
    await optIn(env, b);
    lobbyOf('room8', [a, b]);
    await send(env, a, 'chat_lobby_send', { text: 'hello' });
    await send(env, b, 'chat_report', { msg_id: last(b, 'chat_lobby')?.id, reason: 'spam' });
    expect(env.extra.reports[0].match_id).toBeNull();
  });

  it('refuses your own messages, other conversations and bad requests', async () => {
    const { env, a, b } = await pair();
    const c = sock();
    await hello(env, c, C, 'Cy');
    await send(env, a, 'chat_dm_send', { to: friendCode(B), text: 'mine' });
    const id = last(a, 'chat_dm')?.id;
    await send(env, a, 'chat_report', { msg_id: id, reason: 'x' });
    expect(last(a, 'chat_result')).toMatchObject({ ok: false, reason: 'unknown_message' });
    await send(env, c, 'chat_report', { msg_id: id, reason: 'x' });
    expect(last(c, 'chat_result')).toMatchObject({ ok: false, reason: 'unknown_message' });
    await send(env, b, 'chat_report', { msg_id: id });
    expect(last(b, 'chat_result')).toMatchObject({ ok: false, reason: 'bad_request' });
    await send(env, b, 'chat_report', { reason: 'x' });
    expect(last(b, 'chat_result')).toMatchObject({ ok: false, reason: 'bad_request' });
    expect(env.extra.reports).toHaveLength(0);
  });

  it('counts a repeated report once', async () => {
    const { env, a, b } = await pair();
    await send(env, a, 'chat_dm_send', { to: friendCode(B), text: 'rude' });
    const id = last(b, 'chat_dm')?.id;
    await send(env, b, 'chat_report', { msg_id: id, reason: 'rude' });
    await send(env, b, 'chat_report', { msg_id: id, reason: 'rude' });
    expect(env.extra.reports).toHaveLength(1);
  });

  it('allows 5 reports in 10 minutes', async () => {
    const { env, a, b } = await pair();
    const ids: string[] = [];
    for (let i = 0; i < 7; i++) {
      await send(env, a, 'chat_dm_send', { to: friendCode(B), text: `m${i}` });
      ids.push(last(b, 'chat_dm')?.id);
      env.clock.t += 3000;
    }
    for (const id of ids.slice(0, 5)) {
      await send(env, b, 'chat_report', { msg_id: id, reason: 'spam' });
      expect(last(b, 'chat_result')).toMatchObject({ ok: true });
    }
    await send(env, b, 'chat_report', { msg_id: ids[5], reason: 'spam' });
    expect(last(b, 'chat_result')).toMatchObject({ ok: false, reason: 'rate_limited' });
    env.clock.t += 10 * 60_000;
    await send(env, b, 'chat_report', { msg_id: ids[5], reason: 'spam' });
    expect(last(b, 'chat_result')).toMatchObject({ ok: true });
  });
});

describe('chat before hello', () => {
  it('answers no_key', async () => {
    const env = setup();
    const a = sock();
    await send(env, a, 'chat_dm_send', { to: friendCode(B), text: 'hi' });
    expect(last(a, 'social_result')).toMatchObject({ action: 'chat_dm_send', ok: false, reason: 'no_key' });
  });
});
