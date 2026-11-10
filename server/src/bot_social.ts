export interface SocialBot {
  readyState: number;
  data: { roomCode: string | null; partyCode?: string | null; name?: string };
  ranked: boolean;
  emote(id: string): void;
  chat(text: string): boolean;
  humans(): number;
  note(msg: string): void;
}

export type Situation = 'big_hand' | 'boss' | 'life_lost' | 'pvp_win' | 'shop' | 'waiting' | 'lobby';

const ENV_LEVEL = Number(process.env.BOT_SOCIAL);
export const botSocial = {
  level: process.env.BOT_SOCIAL !== undefined && Number.isFinite(ENV_LEVEL) ? Math.max(0, ENV_LEVEL) : 1,
  scale: 1,
  rand: Math.random as () => number,
  botGapMs: 45000,
  replyGapMs: [6000, 10000, 15000] as [number, number, number],
  roomGapMs: [20000, 30000, 60000] as [number, number, number],
  replyDelay: [1200, 4500] as [number, number],
  actDelay: [800, 3000] as [number, number],
};

export const SITUATION_CHANCE: Record<Situation, number> = {
  big_hand: 0.35, boss: 0.4, life_lost: 0.5, pvp_win: 0.3, shop: 0.08, waiting: 0.3, lobby: 0.25,
};

export const SITUATION_EMOTES: Record<Situation, string[]> = {
  big_hand: ['fire', 'chips', 'money'], boss: ['fire', 'lucky', 'gg'], life_lost: ['cry', 'oops', 'nope'],
  pvp_win: ['laugh', 'fire', 'lucky'], shop: ['money', 'think'], waiting: ['hurry', 'think'], lobby: ['hi'],
};

export const SITUATION_LINES: Record<Situation, string[]> = {
  big_hand: ['Nice hand!', 'Big one!', 'That felt good', 'Look at that score'],
  boss: ['Boss down', 'Got past the boss', 'That boss was rough'],
  life_lost: ['Ouch', 'Next time', 'That hurt', 'Unlucky'],
  pvp_win: ['Close one', 'Phew', 'Got that one'],
  shop: ['Shopping time', 'Nothing good in here', 'Need more money'],
  waiting: ['Take your time', 'No rush', 'Waiting on you'],
  lobby: ['Hi!', 'Good luck', 'Ready when you are'],
};

export const EMOTE_REPLY: Record<string, string[]> = {
  hi: ['hi'], laugh: ['laugh', 'chips'], cry: ['laugh', 'think', 'oops'], nope: ['laugh', 'think'],
  chips: ['fire', 'money', 'chips'], fire: ['fire', 'lucky'], money: ['money', 'chips'], gg: ['gg'],
  think: ['think', 'hurry'], lucky: ['lucky', 'nope'], oops: ['laugh', 'oops'], hurry: ['hurry', 'think', 'nope'],
};

export const REPLY_LINES: Record<string, string[]> = {
  hi: ['Hi!', 'Hey!'], gg: ['GG', 'GG, well played'], laugh: ['Haha'], cry: ['Oof'], oops: ['Oops'],
  fire: ['On fire'], hurry: ['Coming!', 'Almost done'], lucky: ['Lucky!'], think: ['Hmm'],
};

export const BOT_LINES: string[] = [...new Set([...Object.values(SITUATION_LINES).flat(), ...Object.values(REPLY_LINES).flat()])];

interface Crowd { lastAct: number; lastHuman: number; lastReply: number; lastGg: number }
const crowds = new Map<string, Crowd>();
const lastBotAct = new WeakMap<SocialBot, number>();
let source: () => Iterable<SocialBot> = () => [];

export function initBotSocial(bots: () => Iterable<SocialBot>): void { source = bots; }

export function resetBotSocial(): void { crowds.clear(); }

function keyOf(b: SocialBot): string | null {
  const k = b.data.partyCode ?? b.data.roomCode;
  return k ? String(k) : null;
}

export function crowdBots(b: SocialBot): SocialBot[] {
  const k = keyOf(b);
  if (!k) return [b];
  const out: SocialBot[] = [];
  for (const x of source()) if (x.readyState === 1 && keyOf(x) === k) out.push(x);
  if (!out.includes(b)) out.push(b);
  return out;
}

export function tier(players: number): 0 | 1 | 2 {
  if (players <= 2) return 0;
  if (players <= 4) return 1;
  return 2;
}

export function lively(players: number): number {
  if (players <= 2) return 1;
  if (players <= 4) return 0.6;
  if (players <= 6) return 0.3;
  return 0.15;
}

export function replyChance(players: number): number {
  if (players <= 2) return 0.8;
  if (players <= 4) return 0.6;
  return 0.35;
}

function crowd(b: SocialBot): Crowd {
  const k = keyOf(b) ?? '';
  let c = crowds.get(k);
  if (!c) { c = { lastAct: 0, lastHuman: 0, lastReply: 0, lastGg: 0 }; crowds.set(k, c); }
  return c;
}

function pick<T>(list: T[]): T { return list[Math.min(list.length - 1, Math.floor(botSocial.rand() * list.length))]; }

function delay(range: [number, number]): number {
  return Math.round((range[0] + botSocial.rand() * (range[1] - range[0])) * botSocial.scale);
}

function players(b: SocialBot, bots: SocialBot[]): number { return Math.max(1, b.humans()) + bots.length; }

function act(b: SocialBot, why: string, emotes: string[], lines: string[] | undefined, chatChance: number): void {
  if (b.readyState !== 1 || b.ranked) return;
  const useChat = lines && lines.length > 0 && botSocial.rand() < chatChance;
  if (useChat) {
    const text = pick(lines);
    if (b.chat(text)) { b.note(`social ${why} chat "${text}"`); return; }
  }
  const id = pick(emotes);
  b.emote(id);
  b.note(`social ${why} emote ${id}`);
}

export function onHumanEmote(b: SocialBot, from: string, id: string): boolean {
  if (botSocial.level <= 0 || b.ranked) return false;
  const bots = crowdBots(b);
  if (bots.some(x => String(x.data.name ?? '') === from)) return false;
  const now = Date.now();
  const c = crowd(b);
  if (now - c.lastHuman < 800) return false;
  c.lastHuman = now;
  const n = players(b, bots);
  const t = tier(n);
  if (now - c.lastReply < botSocial.replyGapMs[t]) { b.note(`social reply skipped (cooldown) n=${n}`); return false; }
  if (botSocial.rand() >= Math.min(1, replyChance(n) * botSocial.level)) { b.note(`social reply skipped (chance) n=${n}`); return false; }
  c.lastReply = now;
  c.lastAct = now;
  const first = pick(bots);
  const emotes = EMOTE_REPLY[id] ?? ['think'];
  setTimeout(() => act(first, `reply ${id} n=${n}`, emotes, REPLY_LINES[id], 0.3), delay(botSocial.replyDelay));
  if (t <= 1 && bots.length > 1 && botSocial.rand() < 0.2) {
    const second = pick(bots.filter(x => x !== first));
    setTimeout(() => act(second, `reply2 ${id} n=${n}`, emotes, REPLY_LINES[id], 0.3), delay(botSocial.replyDelay) + 2500 * botSocial.scale);
  }
  return true;
}

export function onSituation(b: SocialBot, what: Situation, alive: () => boolean = () => true): boolean {
  if (botSocial.level <= 0 || b.ranked || b.readyState !== 1) return false;
  const now = Date.now();
  if (now - (lastBotAct.get(b) ?? 0) < botSocial.botGapMs) return false;
  const bots = crowdBots(b);
  const n = players(b, bots);
  const c = crowd(b);
  if (now - c.lastAct < botSocial.roomGapMs[tier(n)]) return false;
  if (botSocial.rand() >= Math.min(1, SITUATION_CHANCE[what] * lively(n) * botSocial.level)) return false;
  c.lastAct = now;
  lastBotAct.set(b, now);
  setTimeout(() => { if (alive()) act(b, `${what} n=${n}`, SITUATION_EMOTES[what], SITUATION_LINES[what], 0.35); }, delay(botSocial.actDelay));
  return true;
}

export function onMatchEnd(b: SocialBot): void {
  const c = crowd(b);
  const now = Date.now();
  if (now - c.lastGg < 5000) return;
  c.lastGg = now;
  const bots = crowdBots(b);
  const n = players(b, bots);
  const takers = n <= 2 ? [b] : [...bots].sort(() => botSocial.rand() - 0.5).slice(0, n <= 4 ? 2 : 1);
  takers.forEach((x, i) => setTimeout(() => {
    if (x.readyState !== 1) return;
    x.emote('gg');
    x.note(`social gg n=${n}`);
  }, Math.round((600 + botSocial.rand() * 1400 + i * 1500) * botSocial.scale)));
}
