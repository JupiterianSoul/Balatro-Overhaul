
import type { Server, ServerWebSocket } from 'bun';
import { inflateRawSync } from 'node:zlib';
import { handleCrashRequest, crashSizes } from './crash';
import { memoryHeaders, memorySample, MemoryWatch } from './memory';
import { alertError, alertInfo, installProcessAlerts } from './alerts';
import { nameIsClean } from './filter';
import { ranked, setRanked, RankedService, cleanRecoveryCode, rankOf, CASUAL_RATED, type MatchIn, type Mode, type Result } from './ranked';
import { storeFromEnv, wipeForEpoch } from './ranked_store';
import { UpdateService, updatesFromEnv, ReleaseService, releaseFromEnv, versionNameOf } from './updates';
import { SocialService, SOCIAL_TYPES, type PresenceDetail } from './social';
import type { LobbyInfo } from './chat';
import { partyCfg, PARTY_MAX } from './party_rules';
import { startDraft, draftAction, draftDecks, draftMyDeck, wantsDraft, cancelDraft, resendDraft, type Draft, type DraftDeps } from './draft';
import { startPick, pickAction, wantsPick, cancelPick, resendPick, cleanJokerList, RANDOM_PICK, type Pick, type PickDeps, type PickOpts } from './pick';
import { remaining as draftRemaining } from './draft';
import { raceCleared } from './party_rules';
import { SWAP_TYPES, validateSwap, handleSwapState, handleSwapApplied, handleSwapReady, handleBotSwapState, holdsSnapshot, swapStatus, type SwapMatch, type SwapIO } from './swap';
import { initParty, handlePartyMessage, validateParty, listParties, partyCleanup, partyNameHeld, sweepParties, partyForSocket, partySockets, parties, PARTY_TYPES, findParty, partyIsPvp, partyHumans, partyHostCheck, partyNames, type Party } from './party';
import { initBots, deliverToBots, isBot, listBots, botName, stopBots, BotSocket, BOT_LEVELS, workerPoolStats, type BotLevel } from './bots';
import { roomRoster, seatRoster, noteRank, noteRankResult, whoOf } from './identity';
import { matchlogs, setMatchlogs, MatchLogService, logStoreFor, type LogResult } from './matchlog';
import { notifyMatchDecision } from './notify';
import { rankedRuleset, rankedSettings, dailyRuleset } from './rulesets_server';
import { blockedMods, scoreText } from './integrity';
import { SpectateService, SPECTATE_TYPES, validateSpectate } from './spectate';
import { daily, setDaily, DailyBoard, DAILY_TYPES, validateDaily, dailyStoreFor, dailyHandlers } from './daily_board';
import { SpeedrunService, SPEEDRUN_TYPES, SPEEDRUN_BIG_TYPES, SR_REPLAY_MSG_BYTES, validateSpeedrun } from './speedrun';
import { forgeBoard, setForgeBoard, ForgeBoard, FORGE_TYPES, validateForge, forgeStoreFor, forgeHandlers } from './forge_mods';
import { ForgeRelay, FORGE_ROOM_TYPES, FORGE_ROOM_MAX, validateForgeRoom, validateForgeEntry, isForgeEntry, plainMods, forgeMods } from './forge_relay';
import { traffic, d1Usage } from './traffic';
import { AdminService, type LiveState } from './admin';
import { cleanDeckPool, rollDeck } from './deck_roll';
import { isDevKey, devMark } from './dev';
import { BOOT_ID, BOOT_AT, handoverTiming, handoverStoreFor, MemoryHandoverStore, withBudget, msLeft, type HandoverStore, type HandoverEntry } from './handover';
import { partySnapshot, partyRestore } from './party';
import { rearmPick } from './pick';
import { rearmDraft } from './draft';


interface RateLimiter {
  msgCount: number;
  msgWindowStart: number;
  createCount: number;
  createWindowStart: number;
  actCount?: number;
  actWindowStart?: number;
}

interface ModEntry {
  id: string;
  name: string;
  version: string;
  author?: string;
  size?: number;
}

interface SocketData {
  roomCode: string | null;
  rl: RateLimiter;
  mods?: ModEntry[];
  modsFp?: string;
  modsFpPlain?: string;
  rtt?: number | null;
  gameVersion?: string;
  name?: string;
  nameKey?: string;
  partyCode?: string | null;
  pkey?: string;
  restoreTries?: number[];
  socialKey?: string;
  socialEmoteAt?: number;
  socialInviteAt?: number;
  socialAdds?: number[];
  rankedQueue?: boolean;
  socialWhere?: string;
  socialSearchAt?: number[];
  connectedAt?: number;
}

type BunWS = ServerWebSocket<SocketData>;

interface Player {
  name: string;
  lives: number;
  status: 'active' | 'eliminated';
  score: number | null;
  blindFinished: boolean;
  lastAnte?: number;
  lastBlind?: string;
  lastScore?: number;
  currentAnte?: number;
  currentBlind?: string;
  lostBlinds?: string[];
}

interface PvpResult {
  ante: number;
  blind: string;
  p0Score: number;
  p1Score: number;
  winner: number | null;
}

interface MatchState {
  phase: 'lobby' | 'playing' | 'pvp_pending' | 'finished';
  mode: string;
  startingLives: number;
  pvpStartAnte: number;
  seed: string | null;
  seed2?: string;
  players: Player[];
  currentAnte: number;
  currentBlind: string;
  isPvpBlind: boolean;
  pvpResults: PvpResult[];
  winner: number | null;
  winReason: string | null;
  anteTimer: boolean;
  anteTimerBase: number;
  anteTimerSkips: number;
  timerForgiven: [number, number];
  blindReady?: [boolean, boolean];
  blindReadyAt?: [number, number];
  endReasons?: [string, string];
  pvpStarted?: boolean;
  finalAnte: number;
  suddenDeath: number;
  lifeSteal: boolean;
  id?: string;
}

interface EndJoker {
  k: string;
  ed?: string;
  st?: string[];
}

interface EndCard {
  f: string;
  e?: string;
  ed?: string;
  s?: string;
}

interface EndData {
  jokers: EndJoker[];
  back: string | null;
  cards: EndCard[];
  game: number;
}

interface Snapshot {
  data: string;
  bytes: number;
  ante: number | null;
  blind: string | null;
  seq: number | null;
  at: number;
}

interface EndedSession {
  code: string;
  reason: string;
  result: 'win' | 'lose' | 'draw';
  winner: number | null;
  at: number;
}

interface GameRecord {
  gameNumber: number;
  winner: number | null;
  winReason: string | null;
  pvpResults: PvpResult[];
  p0Lives: number;
  p1Lives: number;
  p0Name: string;
  p1Name: string;
  mode: string;
  seed: string | null;
  timestamp: number;
}

interface Room {
  draft?: Draft | null;
  pick?: Pick | null;
  lastPickPool?: string[];
  botJokerPool?: string[];
  lastPick?: { decks: Record<number, string | null>; picks: Record<number, string[]> } | null;
  code: string;
  sockets: (BunWS | null)[];
  match: MatchState | null;
  settings: Record<string, unknown>;
  gameHistory: GameRecord[];
  lastActivity: number;
  pvpTimer: ReturnType<typeof setTimeout> | null;
  rematchVotes?: [boolean, boolean];
  inLobby?: [boolean, boolean];
  playerNames: [string, string];
  tokens: [string, string];
  holdDeadline: [number | null, number | null];
  dropReason: [string | null, string | null];
  holdTimer: ReturnType<typeof setTimeout> | null;
  pvpPaused: boolean;
  snapshots: [Snapshot | null, Snapshot | null];
  locations: [string | null, string | null];
  decks: [string | null, string | null];
  anteClock: AnteClock | null;
  quick?: boolean;
  endData: [EndData | null, EndData | null];
  id: string;
  visibility: 'public' | 'private';
  mods: ModEntry[];
  modsFp: string;
  gameVersion: string;
  createdAt: number;
  rankedSeats?: { pkey?: string; bot: boolean }[];
  rankedTo?: (BunWS | null)[];
  ranked?: boolean;
  rankedSeed?: string;
  specBoards?: [Record<string, unknown> | null, Record<string, unknown> | null];
  specWatch?: [boolean, boolean];
  pvpEndsAt?: number | null;
  pvpMsLeft?: number | null;
  moved?: boolean[];
}

interface AnteClock {
  target: number;
  endsAt: number;
  remainingMs: number | null;
  handle: ReturnType<typeof setTimeout> | null;
}

interface Settings {
  starting_lives?: number;
  mode?: string;
  pvp_start_round?: number;
  showdown_starting_antes?: number;
  ante_timer?: boolean;
  ante_timer_base?: number;
  [key: string]: unknown;
}

type Handler = (ws: BunWS, msg: Record<string, unknown>, raw: string | Buffer) => void;


const RATE_LIMIT_MSG_PER_SEC    = 30;
const RATE_LIMIT_CREATE_PER_MIN = 5;
const RATE_LIMIT_ACT_PER_SEC    = 60;
const ROOM_TTL_MS               = 30 * 60 * 1000;
const ROOM_CLEANUP_INTERVAL_MS  = 60 * 1000;
const PVP_TIMEOUT_MS            = 180 * 1000;
const MAX_MESSAGE_BYTES         = 4096;
const MAX_FRAME_BYTES           = 1024 * 1024;
const MAX_SETTINGS_BYTES        = 64 * 1024;
const SNAPSHOT_MAX_BYTES        = 512 * 1024;
const SNAPSHOT_B64_MAX          = 4 * Math.ceil(SNAPSHOT_MAX_BYTES / 3);
const TOKEN_RE                  = /^[a-f0-9]{32}$/;
const ROOM_CODE_RE              = /^[A-Z0-9]{4}$/;
const BASE64_RE                 = /^[A-Za-z0-9+/]+={0,2}$/;

const timing = {
  rejoinHoldMs:      Number(process.env.MP_REJOIN_HOLD_SECONDS) > 0 ? Number(process.env.MP_REJOIN_HOLD_SECONDS) * 1000 : 15 * 60 * 1000,
  pvpTimeoutMs:      PVP_TIMEOUT_MS,
  endedSessionTtlMs: 60 * 60 * 1000,
};

function setTimings(t: Partial<typeof timing>): void {
  Object.assign(timing, t);
}
const READY_UNREADY_DEBOUNCE_MS = 900;

const VALID_SCORE_MAX = 1e15;
const VALID_ANTE_MAX  = 999;
const VALID_LIVES_MAX = 20;
const WS_OPEN         = 1;
const VALID_MODES     = ['nemesis', 'faceoff', 'ascension', 'attrition', 'vanilla', 'ruleset', 'race', 'swap'];
const ASC_LIKE = (mode: unknown): boolean => mode === 'ascension' || mode === 'race';


const COMPRESS_THRESHOLD  = 300;
const DECOMPRESS_MAX_BYTES = MAX_FRAME_BYTES;

async function countHttp(path: string, res: Response | Promise<Response>): Promise<Response> {
  const r = await res;
  const len = Number(r.headers.get('content-length'));
  if (Number.isFinite(len) && r.headers.has('content-length')) {
    traffic.served(path, len);
  } else if (r.body) {
    const buf = await r.clone().arrayBuffer();
    traffic.served(path, buf.byteLength);
  } else {
    traffic.served(path, 0);
  }
  return r;
}

function tryCompress(data: string): string {
  if (data.length <= COMPRESS_THRESHOLD) return data;
  try {
    const compressed = Bun.deflateSync(Buffer.from(data, 'utf8'));
    const b64        = Buffer.from(compressed).toString('base64');
    const wrapped    = `{"z":1,"d":"${b64}"}`;
    return wrapped.length < data.length ? wrapped : data;
  } catch {
    return data;
  }
}

function tryDecompress(str: string): string | null {
  if (!str.startsWith('{"z":1')) return null;
  try {
    const parsed = JSON.parse(str) as Record<string, unknown>;
    if (parsed.z !== 1 || typeof parsed.d !== 'string') return null;
    const compressed   = Buffer.from(parsed.d as string, 'base64');
    const decompressed = inflateRawSync(compressed, { maxOutputLength: DECOMPRESS_MAX_BYTES });
    return Buffer.from(decompressed).toString('utf8');
  } catch {
    return null;
  }
}


const LOG_LEVEL = process.env.LOG_LEVEL ?? 'INFO';
const LOG_LEVELS: Record<string, number> = { ERROR: 0, WARN: 1, INFO: 2, DEBUG: 3 };
const currentLevel = LOG_LEVELS[LOG_LEVEL] ?? LOG_LEVELS.INFO;

function log(level: string, tag: string, msg: string, extra?: unknown): void {
  if (level === 'ERROR') alertError(tag, msg + (extra !== undefined ? ' ' + (typeof extra === 'object' ? JSON.stringify(extra) : String(extra)) : ''));
  if ((LOG_LEVELS[level] ?? 99) > currentLevel) return;
  const ts   = new Date().toISOString();
  const base = `${ts} [${level}][${tag}] ${msg}`;
  if (extra !== undefined) {
    console.log(base, typeof extra === 'object' ? JSON.stringify(extra) : extra);
  } else {
    console.log(base);
  }
}


const rooms: Record<string, Room> = {};
const endedSessions = new Map<string, EndedSession>();
let queue: BunWS[] = [];

let server!: Server;
let handover: HandoverStore = new MemoryHandoverStore();
const handoverCodes = new Set<string>();
let movingOut = false;


function generateCode(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  for (;;) {
    const c = Array.from({ length: 4 }, () => chars[Math.floor(Math.random() * chars.length)]).join('');
    if (!handoverCodes.has(c)) return c;
  }
}

function createMatchState(settings?: Settings): MatchState {
  const lives = settings?.starting_lives ?? 4;
  const mode  = settings?.mode ?? 'nemesis';
  return {
    phase: 'lobby',
    mode,
    startingLives: lives,
    pvpStartAnte: mode === 'faceoff'
      ? ((settings?.showdown_starting_antes ?? 1) - 1)
      : ((settings?.pvp_start_round ?? 2) - 1),
    seed: null,
    players: [
      { name: 'Player 1', lives, status: 'active', score: null, blindFinished: false },
      { name: 'Player 2', lives, status: 'active', score: null, blindFinished: false },
    ],
    currentAnte: 1,
    currentBlind: 'S',
    isPvpBlind: false,
    pvpResults: [],
    winner: null,
    winReason: null,
    anteTimer:     timerConfig(settings).on,
    anteTimerBase: timerConfig(settings).baseSeconds,
    anteTimerSkips: 0,
    timerForgiven: [0, 0],
    finalAnte: finalAnteFor(settings),
    suddenDeath: 0,
    lifeSteal: settings?.life_steal === true,
  };
}

export function finalAnteFor(settings?: Settings | Record<string, unknown>): number {
  const w = settings?.win_ante;
  if (isIntInRange(w, 1, VALID_ANTE_MAX)) return w as number;
  const stake = Number(settings?.stake === 'random' ? settings?.rolled_stake : settings?.stake);
  if (Number.isInteger(stake) && stake >= 9 && stake <= 12) return stake + 1;
  return 8;
}

function isFinalPvp(m: MatchState): boolean {
  return m.isPvpBlind && m.currentBlind === 'L' && m.currentAnte >= m.finalAnte;
}

const SEED_CHARS = '123456789ABCDEFGHIJKLMNPQRSTUVWXYZ';

function randomSeed(): string {
  return Array.from({ length: 8 }, () => SEED_CHARS[Math.floor(Math.random() * SEED_CHARS.length)]).join('');
}

function differentSeeds(settings?: Settings | Record<string, unknown>): boolean {
  return !!settings && (settings.different_seeds === true || settings.same_seed === false);
}

function customSeed(settings?: Settings | Record<string, unknown>): string | null {
  if (!settings || differentSeeds(settings)) return null;
  const raw = typeof settings.custom_seed === 'string' ? settings.custom_seed : '';
  const clean = raw.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 8);
  if (clean === '' || clean === 'RANDOM') return null;
  return clean;
}

function assignSeeds(m: MatchState, settings: Record<string, unknown>, hostSeed: string | null): void {
  m.seed = customSeed(settings) ?? (hostSeed && hostSeed.length > 0 ? hostSeed : randomSeed());
  if (differentSeeds(settings) || m.mode === 'vanilla') {
    let s2 = randomSeed();
    while (s2 === m.seed) s2 = randomSeed();
    m.seed2 = s2;
  } else {
    delete m.seed2;
  }
}

function seedFor(m: MatchState, pid: number): string | null {
  return pid === 1 && m.seed2 ? m.seed2 : m.seed;
}

function num(v: unknown, fallback: number): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : fallback;
}

function timerConfig(settings?: Settings | Record<string, unknown>): { on: boolean; baseSeconds: number; incrementSeconds: number; forgiveness: number } {
  const s = settings ?? {};
  const on = s.timer === true || s.ante_timer === true;
  const base = Math.max(0.2, num(s.timer_base_seconds, num(s.ante_timer_base, 120)));
  const inc = Math.max(0, num(s.timer_increment_seconds, 0));
  const forgiveness = Math.max(0, Math.floor(num(s.timer_forgiveness, 0)));
  return { on, baseSeconds: base, incrementSeconds: inc, forgiveness };
}

function isBlindPvp(match: MatchState, ante: number, blindType: string): boolean {
  if (match.mode === 'vanilla') return false;
  if (ASC_LIKE(match.mode)) return false;
  if (match.mode === 'nemesis' || match.mode === 'attrition' || match.mode === 'ruleset' || match.mode === 'swap') {
    return blindType === 'L' && ante > match.pvpStartAnte;
  } else if (match.mode === 'faceoff' || match.mode === 'showdown') {
    return ante > match.pvpStartAnte;
  }
  return false;
}


function createRoom(code: string): Room {
  return {
    code,
    sockets: [],
    match: null,
    settings: { mode: 'attrition', starting_lives: 4 },
    gameHistory: [],
    lastActivity: Date.now(),
    pvpTimer: null,
    playerNames: ['Player 1', 'Player 2'],
    tokens: [newToken(), newToken()],
    holdDeadline: [null, null],
    dropReason: [null, null],
    holdTimer: null,
    pvpPaused: false,
    snapshots: [null, null],
    locations: [null, null],
    decks: [null, null],
    anteClock: null,
    endData: [null, null],
    id: newToken().slice(0, 12),
    visibility: 'private',
    mods: [],
    modsFp: '',
    gameVersion: '',
    createdAt: Date.now(),
  };
}

function newToken(): string {
  return crypto.randomUUID().replace(/-/g, '');
}

function seatSocket(room: Room, pid: number): BunWS | null {
  const s = room.sockets[pid];
  return (s && s.readyState === WS_OPEN) ? s : null;
}

function inMatch(room: Room): boolean {
  return !!room.match && (room.match.phase === 'playing' || room.match.phase === 'pvp_pending');
}

function secondsLeft(room: Room, pid: number): number | null {
  const d = room.holdDeadline[pid];
  return d === null ? null : Math.max(0, Math.ceil((d - Date.now()) / 1000));
}

function holdSeconds(): number {
  return Math.round(timing.rejoinHoldMs / 1000);
}

function resultFor(winner: number | null, pid: number): 'win' | 'lose' | 'draw' {
  return winner === null ? 'draw' : (winner === pid ? 'win' : 'lose');
}

function detachSeat(room: Room, pid: number): BunWS | null {
  const s = room.sockets[pid] ?? null;
  if (pid < room.sockets.length) room.sockets[pid] = null;
  if (s) {
    if (s.data.roomCode === room.code) s.data.roomCode = null;
    if (s.readyState === WS_OPEN) s.unsubscribe(room.code);
  }
  return s;
}

function getPlayerId(room: Room, ws: BunWS): number {
  return room.sockets.indexOf(ws);
}

function getOpponentSocket(room: Room, ws: BunWS): BunWS | null {
  const idx = room.sockets.indexOf(ws);
  if (idx === -1) return null;
  const opp = room.sockets[idx === 0 ? 1 : 0];
  return (opp && opp.readyState === WS_OPEN) ? opp : null;
}

function touchRoom(room: Room): void {
  room.lastActivity = Date.now();
}

function getRoomForSocket(ws: BunWS): Room | null {
  const code = ws.data.roomCode;
  return (code && rooms[code]) ? rooms[code] : null;
}


initParty({
  sendTo: (ws, data) => sendTo(ws as unknown as BunWS, data),
  log: (level, tag, msg) => log(level, tag, msg),
  claimName: (ws, msg) => claimName(ws as unknown as BunWS, msg),
  rememberMods: (ws, msg) => rememberMods(ws as unknown as BunWS, msg),
  sanitizeSettings: (raw) => sanitizeSettings(raw),
  lifeOnRoundLoss: (s) => lifeOnRoundLoss(s),
  finalAnteFor: (s) => finalAnteFor(s),
  rollMatchExtras: (s, seed) => rollMatchExtras(s, seed),
  codeTaken: (code) => !!rooms[code],
  codeClosed: (code) => rememberClosedCode(code),
  holdMs: () => timing.rejoinHoldMs,
  randomSeed: () => randomSeed(),
  onMatchStart: (p) => partyRankedStart(p),
  onMatchOver: (p) => partyRankedOver(p),
});

function sendTo(ws: BunWS, data: object): void {
  if (ws.readyState !== WS_OPEN) return;
  const payload = tryCompress(JSON.stringify(data));
  ws.send(payload);
  traffic.sent((data as { type?: string }).type, payload);
}

function topicCount(topic: string): number {
  return server ? server.subscriberCount(topic) : 0;
}

function sendToRoom(room: Room, data: object): void {
  const payload = tryCompress(JSON.stringify(data));
  server.publish(room.code, payload);
  traffic.sent((data as { type?: string }).type, payload, topicCount(room.code));
  deliverToBots(room.code, payload);
}

function relay(ws: BunWS, raw: string | Buffer): void {
  const code = ws.data.roomCode;
  if (!code) return;
  const str = typeof raw === 'string' ? raw : raw.toString();
  ws.publish(code, str);
  traffic.sent(undefined, str, topicCount(code) - (isBot(ws) ? 0 : 1));
  if (!isBot(ws)) deliverToBots(code, str, ws);
}

function broadcastMatchState(room: Room, extra?: Record<string, unknown>): void {
  if (!room || !room.match) return;
  const m = room.match;
  l1Sync(room, extra?.event);
  for (let i = 0; i < 2; i++) {
    const s = room.sockets[i];
    if (!s || s.readyState !== WS_OPEN) continue;
    const opp = i === 0 ? 1 : 0;
    sendTo(s, {
      type: 'match_state_update',
      ...(extra ?? {}),
      phase: m.phase,
      playerId: i,
      currentAnte: m.currentAnte,
      currentBlind: m.currentBlind,
      isPvpBlind: m.isPvpBlind,
      myLives:          m.players[i].lives,
      myStatus:         m.players[i].status,
      oppName:          m.players[opp].name,
      oppLives:         m.players[opp].lives,
      oppStatus:        m.players[opp].status,
      oppBlindFinished: m.players[opp].blindFinished,
      oppConnected:     !!seatSocket(room, opp),
      oppSecondsLeft:   secondsLeft(room, opp),
      winner:    m.winner,
      winReason: m.endReasons?.[i] ?? m.winReason,
      finalAnte:   m.finalAnte,
      suddenDeath: m.phase === 'finished' ? 0 : m.suddenDeath,
      players: roomRoster(room, true),
    });
  }
}

function matchEndedPayload(m: MatchState, i: number, event: string): Record<string, unknown> {
  const opp = i === 0 ? 1 : 0;
  return {
    type: 'match_ended',
    event,
    match_id: m.id,
    playerId: i,
    result:   resultFor(m.winner, i),
    reason:   m.endReasons?.[i] ?? m.winReason,
    winner:   m.winner,
    myLives:  m.players[i].lives,
    oppLives: m.players[opp].lives,
  };
}

function rememberEnded(room: Room, pid: number): void {
  const m = room.match;
  if (!m) return;
  const token = room.tokens[pid];
  if (endedSessions.has(token)) return;
  endedSessions.set(token, {
    code:   room.code,
    reason: m.endReasons?.[pid] ?? m.winReason ?? 'match_over',
    result: resultFor(m.winner, pid),
    winner: m.winner,
    at:     Date.now(),
  });
}

const CLOSED_CODE_MS = 15 * 60 * 1000;
const closedCodes = new Map<string, number>();

function rememberClosedCode(code: string): void {
  const now = Date.now();
  for (const [c, at] of closedCodes) if (now - at > CLOSED_CODE_MS) closedCodes.delete(c);
  closedCodes.set(code, now);
}

function closedLately(code: string | null): boolean {
  const at = code ? closedCodes.get(code) : undefined;
  return at !== undefined && Date.now() - at <= CLOSED_CODE_MS;
}

function codeNamesOther(id: string, code: string | null): boolean {
  if (!code) return false;
  const other = rooms[code] ?? findParty({ code });
  return !!other && other.id !== id;
}

function clearHoldTimer(room: Room): void {
  if (room.holdTimer) { clearTimeout(room.holdTimer); room.holdTimer = null; }
}

function closeRoom(room: Room, reason: string, postMatch: boolean, legacy?: Record<string, unknown>): void {
  cancelDraft(room, true);
  cancelPick(room);
  for (const s of room.sockets) {
    if (!s || s.readyState !== WS_OPEN) continue;
    if (legacy) sendTo(s, legacy);
    sendTo(s, { type: 'room_closed', reason, post_match: postMatch });
  }
  if (room.match && room.match.phase === 'finished') {
    rememberEnded(room, 0);
    rememberEnded(room, 1);
  }
  clearPvpTimer(room);
  clearHoldTimer(room);
  detachRoomSockets(room);
  if (rooms[room.code] === room) { delete rooms[room.code]; rememberClosedCode(room.code); }
  log('INFO', 'ROOM', `Closed ${room.code}: ${reason}`);
}

function finishMatch(room: Room, winner: number | null, reasons: [string, string], event: string, closeReason?: string): void {
  const m = room.match;
  if (!m) return;
  m.phase      = 'finished';
  m.winner     = winner;
  m.endReasons = reasons;
  m.winReason  = reasons[winner ?? 0];
  m.pvpStarted = false;
  clearPvpTimer(room);
  clearHoldTimer(room);
  stopAnteClock(room, false);
  room.pvpPaused    = false;
  room.rematchVotes = [false, false];
  room.holdDeadline = [null, null];
  room.dropReason   = [null, null];
  recordGameHistory(room);
  log('INFO', 'MATCH', `Ended ${room.code}: winner=${winner} reasons=${reasons.join('/')} event=${event}`);
  for (let i = 0; i < 2; i++) {
    const s = seatSocket(room, i);
    if (s) sendTo(s, { ...matchEndedPayload(m, i, event), players: roomRoster(room, true) });
  }
  broadcastMatchState(room, { event });
  reportRanked1v1(room);
  const anyGone = !seatSocket(room, 0) || !seatSocket(room, 1);
  if (anyGone || closeReason) closeRoom(room, closeReason ?? 'opponent_disconnected', true);
}

function scheduleHold(room: Room): void {
  clearHoldTimer(room);
  const pending = room.holdDeadline.filter((d): d is number => d !== null);
  if (pending.length === 0) return;
  const wait = Math.max(0, Math.min(...pending) - Date.now());
  room.holdTimer = setTimeout(() => { room.holdTimer = null; onHoldExpired(room); }, wait);
}

function onHoldExpired(room: Room): void {
  if (rooms[room.code] !== room) return;
  const now = Date.now();
  if (!inMatch(room)) {
    const ds = room.holdDeadline.filter((x): x is number => x !== null);
    if (ds.length === 0) return;
    if (Math.min(...ds) > now) { scheduleHold(room); return; }
    log('INFO', 'HOLD', `Guest did not come back to lobby ${room.code} in time`);
    closeRoom(room, 'opponent_timed_out', false);
    return;
  }
  const expired = [0, 1].find(i => { const d = room.holdDeadline[i]; return d !== null && d <= now; });
  if (expired === undefined) { scheduleHold(room); return; }
  const other = expired === 0 ? 1 : 0;
  const reasons: [string, string] = ['', ''];
  reasons[expired] = 'rejoin_expired';
  reasons[other]   = 'opponent_timed_out';
  log('INFO', 'HOLD', `P${expired} did not come back to ${room.code} in time`);
  finishMatch(room, other, reasons, 'opponent_timed_out', 'opponent_timed_out');
}

function dropPlayer(room: Room, pid: number, reason: string): void {
  const m = room.match;
  if (!m) return;
  detachSeat(room, pid);
  room.holdDeadline[pid] = Date.now() + timing.rejoinHoldMs;
  room.dropReason[pid]   = reason;
  const opp = seatSocket(room, pid === 0 ? 1 : 0);
  if (m.blindReady?.[pid]) {
    m.blindReady[pid] = false;
    if (m.blindReadyAt) m.blindReadyAt[pid] = 0;
    if (opp) sendTo(opp, { type: 'opponent_unready_blind', pid });
  }
  if (room.pvpTimer) {
    clearPvpTimer(room);
    room.pvpPaused = true;
    if (opp) sendTo(opp, { type: 'pvp_timer_paused' });
  }
  if (room.anteClock && room.anteClock.target !== pid) stopAnteClock(room);
  else pauseAnteClock(room);
  if (opp) {
    sendTo(opp, {
      type: 'opponent_disconnected',
      held: true,
      reason,
      playerId: pid,
      secondsLeft: secondsLeft(room, pid),
      holdSeconds: holdSeconds(),
    });
  }
  scheduleHold(room);
  log('INFO', 'DISCONNECT', `P${pid} dropped from ${room.code} (${reason}), holding ${holdSeconds()}s`);
}


function clearPvpTimer(room: Room): void {
  if (room.pvpTimer) { clearTimeout(room.pvpTimer); room.pvpTimer = null; }
}

function anteClockMs(room: Room): number {
  const cfg = timerConfig(room.settings);
  const ante = Math.max(1, room.match?.currentAnte ?? 1);
  return Math.round((cfg.baseSeconds + cfg.incrementSeconds * (ante - 1)) * 1000);
}

function anteClockLeft(room: Room): number {
  const c = room.anteClock;
  if (!c) return 0;
  return c.remainingMs !== null ? c.remainingMs : Math.max(0, c.endsAt - Date.now());
}

function sendAnteClock(room: Room, state: string, extra?: Record<string, unknown>): void {
  const c = room.anteClock;
  const m = room.match;
  const target = c ? c.target : (extra?.target as number | undefined);
  const forgiveLeft = m && target !== undefined ? Math.max(0, timerConfig(room.settings).forgiveness - m.timerForgiven[target]) : 0;
  for (let i = 0; i < 2; i++) {
    const s = seatSocket(room, i);
    if (!s) continue;
    sendTo(s, {
      type: 'ante_timer',
      state,
      ...(extra ?? {}),
      target: target === undefined ? null : (target === i ? 'me' : 'opp'),
      msLeft: c ? anteClockLeft(room) : 0,
      forgivenessLeft: forgiveLeft,
      lives: m && target !== undefined ? m.players[target].lives : null,
    });
  }
}

function armAnteClock(room: Room): void {
  const c = room.anteClock;
  if (!c) return;
  if (c.handle) clearTimeout(c.handle);
  c.handle = setTimeout(() => onAnteClockExpired(room), Math.max(0, c.endsAt - Date.now()));
}

function startAnteClock(room: Room, target: number): void {
  const m = room.match;
  if (!m || m.phase === 'finished' || !timerConfig(room.settings).on) return;
  if (room.anteClock && room.anteClock.target === target) return;
  stopAnteClock(room, false);
  const ms = anteClockMs(room);
  const seated = !!seatSocket(room, 0) && !!seatSocket(room, 1);
  room.anteClock = { target, endsAt: Date.now() + ms, remainingMs: seated ? null : ms, handle: null };
  if (seated) armAnteClock(room);
  log('INFO', 'TIMER', `P${target} has ${ms / 1000}s to ready up in ${room.code}`);
  sendAnteClock(room, seated ? 'running' : 'paused');
}

function stopAnteClock(room: Room, notify = true): void {
  const c = room.anteClock;
  if (!c) return;
  if (c.handle) clearTimeout(c.handle);
  room.anteClock = null;
  if (notify) sendAnteClock(room, 'stopped', { target: c.target });
}

function pauseAnteClock(room: Room): void {
  const c = room.anteClock;
  if (!c || c.remainingMs !== null) return;
  if (c.handle) clearTimeout(c.handle);
  c.handle = null;
  c.remainingMs = Math.max(0, c.endsAt - Date.now());
  sendAnteClock(room, 'paused');
}

function resumeAnteClock(room: Room): void {
  const c = room.anteClock;
  if (!c || c.remainingMs === null) return;
  if (!seatSocket(room, 0) || !seatSocket(room, 1)) return;
  c.endsAt = Date.now() + c.remainingMs;
  c.remainingMs = null;
  armAnteClock(room);
  sendAnteClock(room, 'running');
}

function onAnteClockExpired(room: Room): void {
  const m = room.match;
  const c = room.anteClock;
  if (!m || !c || rooms[room.code] !== room || m.phase === 'finished') {
    if (c?.handle) clearTimeout(c.handle);
    room.anteClock = null;
    return;
  }
  c.handle = null;
  const t = c.target;
  const cfg = timerConfig(room.settings);
  if (m.timerForgiven[t] < cfg.forgiveness) {
    m.timerForgiven[t] += 1;
    log('INFO', 'TIMER', `P${t} timer ran out, forgiven (${m.timerForgiven[t]}/${cfg.forgiveness}) in ${room.code}`);
    c.endsAt = Date.now() + anteClockMs(room);
    armAnteClock(room);
    sendAnteClock(room, 'expired', { forgiven: true });
    return;
  }
  m.players[t].lives = Math.max(0, m.players[t].lives - 1);
  log('INFO', 'TIMER', `P${t} timer ran out, loses a life (${m.players[t].lives} left) in ${room.code}`);
  if (m.players[t].lives <= 0) {
    room.anteClock = null;
    sendAnteClock(room, 'expired', { forgiven: false, target: t });
    m.players[t].status = 'eliminated';
    const winner = t === 0 ? 1 : 0;
    const reasons: [string, string] = ['', ''];
    reasons[t] = 'eliminated';
    reasons[winner] = 'opponent_eliminated';
    finishMatch(room, winner, reasons, 'ante_timer');
    return;
  }
  c.endsAt = Date.now() + anteClockMs(room);
  armAnteClock(room);
  sendAnteClock(room, 'expired', { forgiven: false });
  broadcastMatchState(room, { event: 'ante_timer' });
}

function recordGameHistory(room: Room): void {
  const m = room.match;
  if (!m) return;
  room.gameHistory.push({
    gameNumber: room.gameHistory.length + 1,
    winner: m.winner, winReason: m.winReason, pvpResults: m.pvpResults,
    p0Lives: m.players[0].lives, p1Lives: m.players[1].lives,
    p0Name:  m.players[0].name,  p1Name:  m.players[1].name,
    mode: m.mode, seed: m.seed, timestamp: Date.now(),
  });
}

function parseScore(v: unknown): number {
  if (typeof v === 'number') return Number.isFinite(v) && v > 0 ? v : 0;
  if (typeof v !== 'string') return 0;
  if (/^\s*inf/i.test(v)) return Number.MAX_VALUE;
  const n = parseFloat(v);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

export const RANDOM_STAKE_MAX = 8;

export function rollMatchExtras(settings: Record<string, unknown>, seed: string | null, given?: Record<string, unknown> | null): void {
  if (settings.stake === 'random') {
    const g = given?.rolled_stake;
    settings.rolled_stake = isIntInRange(g, 1, RANDOM_STAKE_MAX) ? g : 1 + Math.floor(Math.random() * RANDOM_STAKE_MAX);
  } else {
    delete settings.rolled_stake;
  }
  const roll = given?.match_roll;
  settings.match_roll = typeof roll === 'string' && roll.length > 0 && roll.length <= 64 ? roll : (seed ?? randomSeed());
}

const LIFE_RULE_KEYS = ['gold_on_life_loss', 'comeback_money', 'no_gold_on_round_loss', 'death_on_round_loss', 'non_pvp_life_loss'];

function dropBadLifeRules(s: Record<string, unknown>): void {
  for (const k of LIFE_RULE_KEYS) if (s[k] !== undefined && typeof s[k] !== 'boolean') delete s[k];
}

export function lifeOnRoundLoss(settings: Record<string, unknown> | undefined): boolean {
  const s = settings ?? {};
  if (typeof s.death_on_round_loss === 'boolean') return s.death_on_round_loss;
  if (typeof s.non_pvp_life_loss === 'boolean') return s.non_pvp_life_loss;
  return true;
}

const BOOL_SETTINGS = ['different_seeds', 'different_decks', 'same_seed', 'same_deck', 'life_steal', 'timer', 'ante_timer', 'the_order',
  'balance_enabled', 'multiplayer_jokers', 'allow_advisor', 'allow_hand_optimizer', 'allow_score_preview', 'per_player_jokers', 'deck_draft', 'traps',
  'allow_fast_speed', 'allow_score_speed', 'allow_skip_score', 'show_seed', 'spectate', 'spectate_wait', 'pvp_boss_effect', 'hide_opp_score'];
const INT_SETTINGS: [string, number, number][] = [
  ['pvp_start_round', 1, 39], ['showdown_starting_antes', 1, 39], ['stake', 1, 20], ['rolled_stake', 1, RANDOM_STAKE_MAX], ['pvp_win_money', 0, 10],
  ['timer_forgiveness', 0, 10], ['pvp_countdown_seconds', 0, 10], ['race_target', 1, 12], ['joker_picks', 0, 5],
];
const NUM_SETTINGS: [string, number, number][] = [
  ['timer_base_seconds', 0.2, 3600], ['ante_timer_base', 0.2, 3600], ['timer_increment_seconds', 0, 600],
];
const STR_SETTINGS: [string, number][] = [['custom_seed', 16], ['deck', 40], ['mp_stake', 32], ['rolled_deck', 40], ['match_roll', 64]];
const RULES_MAX_KEYS = 120;
const RULES_MAX_LIST = 300;

function cleanRuleValue(v: unknown): unknown {
  if (typeof v === 'boolean') return v;
  if (typeof v === 'number') return Number.isFinite(v) && Math.abs(v) <= 100000 ? v : undefined;
  if (typeof v === 'string') return v.length <= 64 ? v : undefined;
  if (Array.isArray(v)) {
    if (v.length > RULES_MAX_LIST || !v.every((x) => typeof x === 'string' && x.length <= 64)) return undefined;
    return [...v];
  }
  return undefined;
}

export function cleanRules(raw: unknown): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return out;
  let n = 0;
  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
    if (n >= RULES_MAX_KEYS || k.length > 40 || !/^[a-z0-9_]+$/.test(k)) continue;
    const c = cleanRuleValue(v);
    if (c !== undefined) { out[k] = c; n++; }
  }
  return out;
}

export function sanitizeSettings(raw: unknown): Settings | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const s = { ...(raw as Settings) };
  dropBadLifeRules(s);
  if (s.starting_lives !== undefined && !isIntInRange(s.starting_lives, 1, VALID_LIVES_MAX)) delete s.starting_lives;
  if (s.mode !== undefined && !VALID_MODES.includes(s.mode as string)) delete s.mode;
  for (const k of BOOL_SETTINGS) if (s[k] !== undefined && typeof s[k] !== 'boolean') delete s[k];
  for (const [k, lo, hi] of INT_SETTINGS) {
    if (s[k] === undefined || (k === 'stake' && s[k] === 'random')) continue;
    if (typeof s[k] !== 'number' || !Number.isFinite(s[k] as number)) { delete s[k]; continue; }
    s[k] = Math.min(hi, Math.max(lo, Math.round(s[k] as number)));
  }
  for (const [k, lo, hi] of NUM_SETTINGS) {
    if (s[k] === undefined) continue;
    if (typeof s[k] !== 'number' || !Number.isFinite(s[k] as number)) { delete s[k]; continue; }
    s[k] = Math.min(hi, Math.max(lo, s[k] as number));
  }
  for (const [k, max] of STR_SETTINGS) if (s[k] !== undefined && (typeof s[k] !== 'string' || (s[k] as string).length > max)) delete s[k];
  if (s.win_ante !== undefined && s.win_ante !== false && !isIntInRange(s.win_ante, 1, VALID_ANTE_MAX)) delete s.win_ante;
  if (s.rules !== undefined) s.rules = cleanRules(s.rules);
  if (s.deck_pool !== undefined) { const pool = cleanDeckPool(s.deck_pool); if (pool) s.deck_pool = pool; else delete s.deck_pool; }
  return s;
}

export const SPEC_BOARD_MAX = 12000;

export function duelCanWatch(room: Room, pid: number): boolean {
  const m = room.match;
  return !!m && room.settings.spectate_wait === true && m.phase === 'pvp_pending' && m.isPvpBlind && !!m.players[pid]?.blindFinished;
}

function duelSpecPayload(room: Room, pid: number): Record<string, unknown> {
  return { type: 'spec_board', pid, name: room.playerNames[pid] || '?', alive: true, board: room.specBoards?.[pid] ?? null };
}

function handleDuelSpectate(ws: BunWS, msg: Record<string, unknown>): void {
  const room = getRoomForSocket(ws);
  if (!room || !room.match) return;
  const pid = getPlayerId(room, ws);
  if (pid < 0) return;
  const opp = 1 - pid;
  room.specBoards ??= [null, null];
  room.specWatch ??= [false, false];
  if (msg.type === 'spec_board') {
    if (room.settings.spectate_wait !== true) return;
    const b = msg.board;
    if (!b || typeof b !== 'object' || Array.isArray(b) || JSON.stringify(b).length > SPEC_BOARD_MAX) return;
    room.specBoards[pid] = b as Record<string, unknown>;
    const w = room.sockets[opp];
    if (w && room.specWatch[opp] && duelCanWatch(room, opp)) sendTo(w, duelSpecPayload(room, pid));
    return;
  }
  if (msg.pid === null || msg.pid === undefined) { room.specWatch[pid] = false; return; }
  if (!duelCanWatch(room, pid)) {
    room.specWatch[pid] = false;
    sendTo(ws, { type: 'spec_board', pid: opp, denied: true, board: null });
    return;
  }
  room.specWatch[pid] = true;
  sendTo(ws, duelSpecPayload(room, opp));
}

function noteDuelFinished(room: Room, pid: number): void {
  const m = room.match;
  const ws = room.sockets[pid];
  if (!m || !ws || m.players[1 - pid].blindFinished || !duelCanWatch(room, pid)) return;
  sendTo(ws, { type: 'spec_avail', pid: 1 - pid, name: room.playerNames[1 - pid] || '?' });
}

function resolvePvp(room: Room): void {
  const m = room.match;
  if (!m || m.phase !== 'pvp_pending') return;
  if (!m.players[0].blindFinished || !m.players[1].blindFinished) return;
  room.specWatch = [false, false];

  clearPvpTimer(room);

  const s0 = m.players[0].score ?? 0;
  const s1 = m.players[1].score ?? 0;
  let loserId: number | null = null;
  let winnerId: number | null = null;
  if (s0 > s1) { winnerId = 0; loserId = 1; }
  else if (s1 > s0) { winnerId = 1; loserId = 0; }
  if (loserId !== null) m.players[loserId].lives = Math.max(0, m.players[loserId].lives - 1);
  if (winnerId !== null && loserId !== null && m.lifeSteal && m.players[loserId].lives > 0) {
    m.players[winnerId].lives = Math.min(m.startingLives, m.players[winnerId].lives + 1);
  }

  m.pvpResults.push({ ante: m.currentAnte, blind: m.currentBlind, p0Score: s0, p1Score: s1, winner: winnerId });
  log('INFO', 'PVP', `Ante ${m.currentAnte} => P0=${s0} P1=${s1} winner=${winnerId !== null ? winnerId : 'draw'}`);

  let matchEnded = false;
  let matchWinner: number | null = null;
  const reasons: [string, string] = ['', ''];
  for (let i = 0; i < 2; i++) {
    if (m.players[i].lives <= 0) {
      m.players[i].status = 'eliminated';
      matchWinner = i === 0 ? 1 : 0;
      reasons[i]           = 'eliminated';
      reasons[matchWinner] = 'opponent_eliminated';
      matchEnded  = true;
      log('INFO', 'MATCH', `Player ${i} eliminated. Winner: Player ${matchWinner}`);
    }
  }
  const finalPvp = isFinalPvp(m);
  if (matchEnded && finalPvp && m.suddenDeath > 0 && matchWinner !== null) {
    reasons[matchWinner]               = 'sudden_death_won';
    reasons[matchWinner === 0 ? 1 : 0] = 'sudden_death_lost';
  }
  if (!matchEnded && finalPvp) {
    m.suddenDeath += 1;
    log('INFO', 'MATCH', `Final Nemesis at ante ${m.currentAnte} left both players with lives (${m.players[0].lives}/${m.players[1].lives}), sudden death round ${m.suddenDeath} room=${room.code}`);
  }
  m.pvpStarted = false;

  for (let i = 0; i < 2; i++) {
    const s = room.sockets[i];
    if (!s || s.readyState !== WS_OPEN) continue;
    const opp = i === 0 ? 1 : 0;
    sendTo(s, {
      type: 'pvp_resolved',
      result:   winnerId === null ? 'draw' : (winnerId === i ? 'win' : 'lose'),
      myScore:  m.players[i].score ?? 0,
      oppScore: m.players[opp].score ?? 0,
      myLives:  m.players[i].lives,
      oppLives: m.players[opp].lives,
      matchEnded,
      winner:    matchEnded ? matchWinner : m.winner,
      winReason: matchEnded ? reasons[i] : m.winReason,
      finalPvp,
      finalAnte:   m.finalAnte,
      suddenDeath: matchEnded ? 0 : m.suddenDeath,
    });
  }

  m.players[0].score = null; m.players[0].blindFinished = false;
  m.players[1].score = null; m.players[1].blindFinished = false;
  if (matchEnded) {
    finishMatch(room, matchWinner, reasons, 'pvp_resolved');
    return;
  }
  m.phase = 'playing';
  broadcastMatchState(room, { event: 'pvp_resolved' });
}

function ascensionOrder(ante: number | undefined, blind: string | undefined | null): number {
  return (Number(ante) || 0) * 10 + (blind === 'S' ? 1 : blind === 'B' ? 2 : blind === 'L' ? 3 : 0);
}

function ascensionPassed(room: Room, pid: number): void {
  const m = room.match;
  if (!m || !ASC_LIKE(m.mode) || m.phase === 'finished') return;
  const me = m.players[pid];
  const opp = m.players[pid === 0 ? 1 : 0];
  if (me.status === 'eliminated' || opp.status !== 'eliminated') return;
  const prog = playerProgress(room, pid);
  if (ascensionOrder(prog.ante, prog.blind) <= ascensionOrder(opp.lastAnte, opp.lastBlind)) return;
  me.lastAnte = prog.ante;
  me.lastBlind = prog.blind;
  me.lastScore = me.score ?? 0;
  log('INFO', 'ASCENSION', `P${pid} passed the eliminated opponent at ${opp.lastAnte}:${opp.lastBlind} room=${room.code}`);
  resolveAscension(room);
}

function resolveAscension(room: Room): void {
  const m = room.match;
  if (!m) return;

  const p0 = m.players[0];
  const p1 = m.players[1];

  function blindOrder(b: string | undefined): number {
    if (b === 'S') return 1;
    if (b === 'B') return 2;
    if (b === 'L') return 3;
    return 0;
  }

  const a0 = p0.lastAnte ?? 1;
  const a1 = p1.lastAnte ?? 1;
  const b0 = blindOrder(p0.lastBlind);
  const b1 = blindOrder(p1.lastBlind);
  const prog0 = a0 * 10 + b0;
  const prog1 = a1 * 10 + b1;

  let winnerId: number | null = null;
  let reason = 'ascension_farthest';

  if (prog0 > prog1) {
    winnerId = 0;
  } else if (prog1 > prog0) {
    winnerId = 1;
  } else {
    const s0 = p0.lastScore ?? 0;
    const s1 = p1.lastScore ?? 0;
    if (s0 > s1)      { winnerId = 0; reason = 'ascension_score_tiebreak'; }
    else if (s1 > s0) { winnerId = 1; reason = 'ascension_score_tiebreak'; }
    else               { winnerId = null; reason = 'ascension_draw'; }
  }

  log('INFO', 'ASCENSION', `Resolved: P0 ante=${a0} blind=${p0.lastBlind} score=${p0.lastScore} | P1 ante=${a1} blind=${p1.lastBlind} score=${p1.lastScore} | winner=P${winnerId} reason=${reason} room=${room.code}`);

  for (let i = 0; i < 2; i++) {
    const s = room.sockets[i];
    if (!s || s.readyState !== WS_OPEN) continue;
    const opp = i === 0 ? 1 : 0;
    sendTo(s, {
      type: 'ascension_resolved',
      result: winnerId === null ? 'draw' : (winnerId === i ? 'win' : 'lose'),
      myAnte: m.players[i].lastAnte, myBlind: m.players[i].lastBlind, myScore: m.players[i].lastScore,
      oppAnte: m.players[opp].lastAnte, oppBlind: m.players[opp].lastBlind, oppScore: m.players[opp].lastScore,
      reason,
    });
  }

  finishMatch(room, winnerId, [reason, reason], 'ascension_resolved');
}

function schedulePvpTimeout(room: Room, ms = timing.pvpTimeoutMs): void {
  clearPvpTimer(room);
  room.pvpEndsAt = Date.now() + ms;
  room.pvpTimer = setTimeout(() => {
    const m = room.match;
    if (!m || m.phase !== 'pvp_pending') return;
    log('WARN', 'PVP', `Timeout in room ${room.code}: closing the blind with the scores played so far`);
    if (!m.players[0].blindFinished) { m.players[0].score = m.players[0].score ?? 0; m.players[0].blindFinished = true; }
    if (!m.players[1].blindFinished) { m.players[1].score = m.players[1].score ?? 0; m.players[1].blindFinished = true; }
    resolvePvp(room);
  }, ms);
}


const RANKED_TYPES = ['ranked_profile', 'ranked_leaderboard', 'ranked_history', 'ranked_open_pack', 'ranked_equip', 'ranked_recovery', 'ranked_restore', 'ranked_badges'];
if (process.env.MP_TEST_RANKED_RP) RANKED_TYPES.push('ranked_test_set');

const L1_TYPES = ['match_history', 'contest', 'act', 'replay_get', 'replay_hide', 'daily_get'];
const L5_TYPES = ['menu_info', 'name_check'];

const ALLOWED_TYPES = new Set([
  'create_room', 'join_room', 'find_match', 'cancel_search',
  'room_joined', 'ready_state',
  'match_settings', 'match_start', 'player_name',
  'blind_entered', 'blind_finished', 'game_over', 'match_finished',
  'request_state', 'boss_sync', 'rematch_vote',
  'return_to_lobby', 'leave_lobby', 'return_to_menu',
  'ping',
  'sabotage', 'taunt', 'draft_start', 'draft_action', 'pick_start', 'pick_set',
  'set_location',
  'ready_blind', 'unready_blind',
  'play_hand',
  'version_mismatch',
  'round_end', 'life_lost', 'get_end_game_jokers', 'end_game_data',
  'check_rejoin', 'rejoin_match', 'leave_match', 'save_snapshot',
  'player_deck',
  'list_rooms',
  'add_bot', 'remove_bot', 'live_stat', 'spec_board', 'spectate',
  ...RANKED_TYPES,
  ...PARTY_TYPES,
  ...SOCIAL_TYPES,
  ...L1_TYPES,
  ...SWAP_TYPES,
  ...L5_TYPES,
  ...SPECTATE_TYPES,
  ...DAILY_TYPES,
  ...SPEEDRUN_TYPES,
  ...FORGE_TYPES,
  ...FORGE_ROOM_TYPES,
]);

function base64DecodedLength(b64: string): number {
  let pad = 0;
  if (b64.endsWith('==')) pad = 2;
  else if (b64.endsWith('=')) pad = 1;
  return (b64.length / 4) * 3 - pad;
}

function validateSession(msg: Record<string, unknown>, label: string): string | null {
  if (typeof msg.code !== 'string' || !ROOM_CODE_RE.test(msg.code)) return `${label}: invalid code`;
  if (typeof msg.token !== 'string' || !TOKEN_RE.test(msg.token))   return `${label}: invalid token`;
  return null;
}

function isIntInRange(v: unknown, min: number, max: number): boolean {
  return typeof v === 'number' && Number.isFinite(v) && Number.isInteger(v) && v >= min && v <= max;
}

function isNonNegativeFinite(v: unknown): boolean {
  return typeof v === 'number' && Number.isFinite(v) && v >= 0;
}

function isStringOfLength(v: unknown, max: number): boolean {
  return typeof v === 'string' && v.length > 0 && v.length <= max;
}

const MODS_MAX      = 100;
const MOD_TEXT_RE   = /^[^\x00-\x1f]{1,64}$/;
const MOD_VERSION_RE = /^[^\x00-\x1f\/\\?#%&<>"'|;$`]{0,32}$/;
export function cleanModVersion(v: unknown): string {
  return typeof v === 'string' && MOD_VERSION_RE.test(v) && !v.includes('..') ? v : '';
}
const ROOM_ID_RE    = /^[a-f0-9]{12}$/;
const ROOM_LIST_MAX = 60;
const MAX_PLAYERS   = 2;
const MODS_TYPES    = new Set(['create_room', 'join_room', 'find_match', 'list_rooms', 'party_create', 'party_join']);

function validateMods(v: unknown, label: string): string | null {
  if (v === undefined) return null;
  if (!Array.isArray(v)) return `${label}: invalid mods`;
  if (v.length > MODS_MAX) return `${label}: invalid mods (too many mods, max ${MODS_MAX})`;
  if (v.filter(m => isForgeEntry(m as { id?: unknown })).length > FORGE_ROOM_MAX) return `${label}: invalid mods (too many forge mods, max ${FORGE_ROOM_MAX})`;
  for (const m of v) {
    if (!m || typeof m !== 'object' || Array.isArray(m)) return `${label}: invalid mods`;
    const e = m as Record<string, unknown>;
    if (isForgeEntry(e)) {
      if (!validateForgeEntry(e) || (e.name !== undefined && (typeof e.name !== 'string' || !MOD_TEXT_RE.test(e.name)))) return `${label}: invalid mods`;
      continue;
    }
    if (typeof e.id !== 'string' || !MOD_TEXT_RE.test(e.id)) return `${label}: invalid mods`;
    if (e.name !== undefined && (typeof e.name !== 'string' || !MOD_TEXT_RE.test(e.name))) return `${label}: invalid mods`;
    if (e.version !== undefined && (typeof e.version !== 'string' || e.version.length > 32 || /[\x00-\x1f]/.test(e.version))) return `${label}: invalid mods`;
  }
  return null;
}

function cleanMods(v: unknown): ModEntry[] {
  if (!Array.isArray(v)) return [];
  const byId = new Map<string, ModEntry>();
  for (const m of v as Record<string, unknown>[]) {
    const id = m.id as string;
    const e: ModEntry = { id, name: typeof m.name === 'string' ? m.name : id, version: cleanModVersion(m.version) };
    if (isForgeEntry(e)) {
      e.author = typeof m.author === 'string' ? m.author : '';
      if (typeof m.size === 'number') e.size = m.size;
    }
    byId.set(id, e);
  }
  return [...byId.values()].sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
}

function modsFingerprint(list: ModEntry[]): string {
  return list.map(m => `${m.id}@${m.version}`).join('|');
}

function rememberMods(ws: BunWS, msg: Record<string, unknown>): void {
  if (typeof msg.version === 'string') ws.data.gameVersion = msg.version;
  ws.data.mods   = cleanMods(msg.mods);
  ws.data.modsFp = modsFingerprint(ws.data.mods);
  ws.data.modsFpPlain = modsFingerprint(plainMods(ws.data.mods));
}

function sentOrPlain(ws: BunWS, msg: Record<string, unknown>): ModEntry[] {
  return Array.isArray(msg.mods) ? ws.data.mods ?? [] : plainMods(ws.data.mods);
}

function joinFp(ws: BunWS, visibility: string): string {
  return (visibility === 'public' ? ws.data.modsFpPlain : ws.data.modsFp) ?? '';
}

const VERSION_RE     = /^[^\x00-\x1f]{1,32}$/;
const DEFAULT_NAME_RE = /^(p\d*|player\s*\d*|m\d|opponent|you)$/i;
const onlineNames    = new Map<string, BunWS>();

export function cleanName(v: unknown): string {
  return typeof v === 'string' ? v.replace(/[\x00-\x1f]/g, '').replace(/\s+/g, ' ').trim() : '';
}

export function isDefaultName(name: string): boolean {
  return name === '' || DEFAULT_NAME_RE.test(name);
}

function nameKey(name: string): string {
  return name.toLowerCase();
}

const nameOwnerKeys = new Map<string, string>();
const PKEY_RE = /^[A-Za-z0-9]{24}$/;

function nameHeldElsewhere(key: string, ws: BunWS, skip?: { room: Room; pid: number }, pkey?: string): boolean {
  if (pkey && nameOwnerKeys.get(key) === pkey) return false;
  const owner = onlineNames.get(key);
  if (owner && owner !== ws && owner.readyState === WS_OPEN) return true;
  if (partyNameHeld(key)) return true;
  for (const room of Object.values(rooms)) {
    for (let i = 0; i < 2; i++) {
      if (!inMatch(room) || room.holdDeadline[i] === null || room.sockets[i]) continue;
      if (skip && skip.room === room && skip.pid === i) continue;
      if (nameKey(room.playerNames[i]) === key) return true;
    }
  }
  return false;
}

function releaseName(ws: BunWS): void {
  const key = ws.data.nameKey;
  if (key && onlineNames.get(key) === ws) onlineNames.delete(key);
  ws.data.nameKey = undefined;
}

function claimName(ws: BunWS, msg: Record<string, unknown>, skip?: { room: Room; pid: number }): boolean {
  if (msg.name === undefined) return true;
  const name = cleanName(msg.name);
  const pkey = typeof msg.pkey === 'string' && PKEY_RE.test(msg.pkey) ? msg.pkey : undefined;
  const refusal = isDefaultName(name) ? 'default' : !nameIsClean(name) ? 'bad_name' : (nameHeldElsewhere(nameKey(name), ws, skip, pkey) ? 'taken' : null);
  if (refusal) {
    sendTo(ws, { type: 'name_refused', reason: refusal, name, for: msg.type });
    log('INFO', 'NAME', `Refused name "${name}" (${refusal}) on ${msg.type}`);
    return false;
  }
  if (ws.data.nameKey !== nameKey(name)) releaseName(ws);
  ws.data.name    = name;
  ws.data.nameKey = nameKey(name);
  onlineNames.set(ws.data.nameKey, ws);
  if (pkey) { nameOwnerKeys.set(ws.data.nameKey, pkey); ws.data.pkey = pkey; ranked.prefetch(pkey, name); }
  return true;
}

const END_KEY_RE       = /^[A-Za-z0-9_.:\-]{1,64}$/;
const END_JOKERS_MAX   = 100;
const END_CARDS_MAX    = 1000;
const END_STICKERS_MAX = 8;

function isEndKey(v: unknown): boolean {
  return typeof v === 'string' && END_KEY_RE.test(v);
}

function optEndKey(v: unknown): boolean {
  return v === undefined || v === null || isEndKey(v);
}

function validateEndGameData(msg: Record<string, unknown>): string | null {
  const jokers = msg.jokers;
  if (!Array.isArray(jokers)) return 'end_game_data: jokers must be a list';
  if (jokers.length > END_JOKERS_MAX) return 'end_game_data: too many jokers';
  for (const j of jokers) {
    if (!j || typeof j !== 'object' || Array.isArray(j)) return 'end_game_data: invalid joker';
    const o = j as Record<string, unknown>;
    if (!isEndKey(o.k) || !optEndKey(o.ed)) return 'end_game_data: invalid joker';
    if (o.st !== undefined && (!Array.isArray(o.st) || o.st.length > END_STICKERS_MAX || !o.st.every(isEndKey)))
      return 'end_game_data: invalid joker';
  }
  const deck = msg.deck;
  if (deck === undefined || deck === null) return null;
  if (typeof deck !== 'object' || Array.isArray(deck)) return 'end_game_data: invalid deck';
  const d = deck as Record<string, unknown>;
  if (!optEndKey(d.back)) return 'end_game_data: invalid deck';
  if (!Array.isArray(d.cards)) return 'end_game_data: invalid deck';
  if (d.cards.length > END_CARDS_MAX) return 'end_game_data: too many cards';
  for (const c of d.cards) {
    if (!c || typeof c !== 'object' || Array.isArray(c)) return 'end_game_data: invalid card';
    const o = c as Record<string, unknown>;
    if (!isEndKey(o.f) || !optEndKey(o.e) || !optEndKey(o.ed) || !optEndKey(o.s)) return 'end_game_data: invalid card';
  }
  return null;
}

function cleanEndData(msg: Record<string, unknown>, game: number): EndData {
  const jokers: EndJoker[] = (msg.jokers as Record<string, unknown>[]).map((o) => {
    const j: EndJoker = { k: o.k as string };
    if (typeof o.ed === 'string') j.ed = o.ed;
    if (Array.isArray(o.st) && o.st.length > 0) j.st = [...(o.st as string[])];
    return j;
  });
  const d = (msg.deck ?? null) as Record<string, unknown> | null;
  const cards: EndCard[] = d ? (d.cards as Record<string, unknown>[]).map((o) => {
    const c: EndCard = { f: o.f as string };
    if (typeof o.e === 'string') c.e = o.e;
    if (typeof o.ed === 'string') c.ed = o.ed;
    if (typeof o.s === 'string') c.s = o.s;
    return c;
  }) : [];
  return { jokers, back: d && typeof d.back === 'string' ? d.back : null, cards, game };
}

function sendEndData(ws: BunWS, owner: number, data: EndData | null, matchId?: string): void {
  sendTo(ws, { type: 'end_game_jokers', playerId: owner, pid: owner, match_id: matchId, available: !!data, jokers: data ? data.jokers : [] });
  if (data) sendTo(ws, { type: 'nemesis_deck_data', playerId: owner, pid: owner, match_id: matchId, available: true, back: data.back, cards: data.cards });
}

function handleEndGameData(ws: BunWS, msg: Record<string, unknown>): void {
  const room = getRoomForSocket(ws);
  if (!room || !room.match || room.match.phase !== 'finished') {
    sendTo(ws, { type: 'error', reason: 'end_game_data: no finished match' });
    return;
  }
  const pid = getPlayerId(room, ws);
  if (pid < 0) return;
  const data = cleanEndData(msg, room.gameHistory.length);
  room.endData[pid] = data;
  touchRoom(room);
  log('INFO', 'END', `P${pid} end data stored: ${data.jokers.length} jokers, ${data.cards.length} cards room=${room.code}`);
  const opp = getOpponentSocket(room, ws);
  if (opp) sendEndData(opp, pid, data, room.match.id);
}

function handleGetEndGameJokers(ws: BunWS): void {
  const room = getRoomForSocket(ws);
  if (!room) return;
  const pid = getPlayerId(room, ws);
  if (pid < 0) return;
  const oid = pid === 0 ? 1 : 0;
  const data = room.match && room.match.phase === 'finished' ? room.endData[oid] : null;
  sendEndData(ws, oid, data, room.match?.id);
}

function validateMessage(msg: Record<string, unknown>, byteLength: number): string | null {
  const maxBytes = !msg ? MAX_MESSAGE_BYTES
    : (msg.type === 'save_snapshot' || msg.type === 'act' || msg.type === 'swap_state' || msg.type === 'forge_publish' || msg.type === 'forge_room_put') ? MAX_FRAME_BYTES
    : (msg.type === 'match_settings' || msg.type === 'match_start' || msg.type === 'end_game_data' || msg.type === 'act' || MODS_TYPES.has(msg.type as string)) ? MAX_SETTINGS_BYTES
    : SPEEDRUN_BIG_TYPES.includes(msg.type as string) ? SR_REPLAY_MSG_BYTES
    : MAX_MESSAGE_BYTES;
  if (byteLength > maxBytes)                   return `oversized: ${byteLength} bytes`;
  if (!msg || typeof msg !== 'object')         return 'not an object';
  if (typeof msg.type !== 'string')            return 'missing type';
  if (!ALLOWED_TYPES.has(msg.type as string))  return `unknown type: ${msg.type}`;

  const partyErr = validateParty(msg);
  if (partyErr) return partyErr;
  const l1Err = l1Validate(msg);
  if (l1Err) return l1Err;
  const specErr = validateSpectate(msg);
  if (specErr) return specErr;
  const dailyErr = validateDaily(msg);
  if (dailyErr) return dailyErr;
  const srErr = validateSpeedrun(msg);
  if (srErr) return srErr;
  const forgeErr = validateForge(msg) ?? validateForgeRoom(msg);
  if (forgeErr) return forgeErr;
  if (msg.type === 'join_room') {
    if (msg.id !== undefined && (typeof msg.id !== 'string' || !ROOM_ID_RE.test(msg.id)))
      return 'join_room: invalid id';
    if (msg.code !== undefined || msg.id === undefined) {
      if (typeof msg.code !== 'string' || !/^[A-Z0-9]{4}$/.test(msg.code.toUpperCase()))
        return 'join_room: invalid code';
    }
  }
  if (MODS_TYPES.has(msg.type as string)) {
    const err = validateMods(msg.mods, msg.type as string);
    if (err) return err;
    if (msg.version !== undefined && (typeof msg.version !== 'string' || !VERSION_RE.test(msg.version)))
      return `${msg.type}: invalid version`;
  }
  if ((msg.type === 'join_room' || msg.type === 'find_match' || msg.type === 'create_room') && msg.name !== undefined
    && (typeof msg.name !== 'string' || msg.name.length > 32))
    return `${msg.type}: invalid name`;
  if (msg.type === 'join_room' && msg.token !== undefined && (typeof msg.token !== 'string' || !TOKEN_RE.test(msg.token)))
    return 'join_room: invalid token';
  if (msg.type === 'create_room') {
    if (msg.visibility !== undefined && msg.visibility !== 'public' && msg.visibility !== 'private')
      return 'create_room: invalid visibility';
  }
  if (msg.type === 'ping' && msg.rtt !== undefined && !isIntInRange(msg.rtt, 0, 60000))
    return 'ping: invalid rtt';
  if (msg.type === 'blind_finished') {
    if (msg.score !== undefined && !isNonNegativeFinite(msg.score))
      return 'blind_finished: invalid score';
    if (typeof msg.score === 'number' && msg.score > VALID_SCORE_MAX)
      return 'blind_finished: score too large';
  }
  if (msg.type === 'blind_entered') {
    if (msg.ante  !== undefined && !isIntInRange(msg.ante, 1, VALID_ANTE_MAX))
      return 'blind_entered: invalid ante';
    if (msg.blind !== undefined && !isStringOfLength(msg.blind, 2))
      return 'blind_entered: invalid blind';
  }
  if (msg.type === 'match_start') {
    if (msg.seed !== undefined && typeof msg.seed !== 'string')
      return 'match_start: seed must be string';
    if (typeof msg.seed === 'string' && msg.seed.length > 64)
      return 'match_start: seed too long';
  }
  if (msg.type === 'match_settings' && msg.settings) {
    const s = msg.settings as Record<string, unknown>;
    if (s.starting_lives !== undefined && !isIntInRange(s.starting_lives, 1, VALID_LIVES_MAX))
      return 'match_settings: invalid starting_lives';
    if (s.mode !== undefined && !VALID_MODES.includes(s.mode as string))
      return 'match_settings: unknown mode';
  }
  if (msg.type === 'player_deck') {
    if (!isStringOfLength(msg.deck, 40)) return 'player_deck: invalid deck';
  }
  if (msg.type === 'player_name') {
    if (msg.name !== undefined && !isStringOfLength(msg.name, 32))
      return 'player_name: invalid name';
  }
  if (msg.type === 'name_check') {
    if (!isStringOfLength(msg.name, 64)) return 'name_check: invalid name';
  }
  if (msg.type === 'draft_action') {
    if (!isStringOfLength(msg.deck, 40)) return 'draft_action: invalid deck';
  }
  if (msg.type === 'sabotage') {
    if (msg.sabotage_id !== undefined && !isStringOfLength(msg.sabotage_id, 64))
      return 'sabotage: invalid sabotage_id';
  }
  if (msg.type === 'taunt') {
    if (msg.title !== undefined && !isStringOfLength(msg.title, 64))
      return 'taunt: invalid title';
  }
  if (msg.type === 'set_location') {
    if (!msg.location || !isStringOfLength(msg.location, 128))
      return 'set_location: invalid location';
  }
  if (msg.type === 'match_finished') {
    if (msg.reason !== undefined && !isStringOfLength(msg.reason, 64))
      return 'match_finished: invalid reason';
  }
  if (msg.type === 'check_rejoin' || msg.type === 'rejoin_match') {
    const err = validateSession(msg, msg.type);
    if (err) return err;
  }
  if (msg.type === 'leave_match' && (msg.code !== undefined || msg.token !== undefined)) {
    const err = validateSession(msg, 'leave_match');
    if (err) return err;
  }
  if (msg.type === 'end_game_data') {
    const err = validateEndGameData(msg);
    if (err) return err;
  }
  if (msg.type === 'save_snapshot') {
    const d = msg.data;
    if (typeof d !== 'string' || d.length === 0)          return 'save_snapshot: missing data';
    if (d.length > SNAPSHOT_B64_MAX)                       return 'save_snapshot: too large';
    if (d.length % 4 !== 0 || !BASE64_RE.test(d))          return 'save_snapshot: data must be base64';
    if (base64DecodedLength(d) > SNAPSHOT_MAX_BYTES)       return 'save_snapshot: too large';
    if (msg.seq !== undefined && !isIntInRange(msg.seq, 0, Number.MAX_SAFE_INTEGER))
      return 'save_snapshot: invalid seq';
    if (msg.ante !== undefined && !isIntInRange(msg.ante, 0, VALID_ANTE_MAX))
      return 'save_snapshot: invalid ante';
    if (msg.blind !== undefined && !isStringOfLength(msg.blind, 32))
      return 'save_snapshot: invalid blind';
  }
  if (SWAP_TYPES.includes(msg.type as string)) {
    const err = validateSwap(msg);
    if (err) return err;
  }
  return null;
}


const MATCH_FLOW_TYPES = new Set([
  'play_hand', 'blind_finished', 'blind_entered', 'game_over', 'match_finished',
  'ready_blind', 'unready_blind', 'set_location', 'rejoin_match', 'check_rejoin',
  'leave_match', 'return_to_menu', 'return_to_lobby', 'leave_lobby', 'ping', 'request_state',
]);

function createRateLimiter(): RateLimiter {
  return { msgCount: 0, msgWindowStart: Date.now(), createCount: 0, createWindowStart: Date.now() };
}

function isRateLimited(rl: RateLimiter, isCreate: boolean): boolean {
  const now = Date.now();
  if (now - rl.msgWindowStart > 1000) { rl.msgCount = 0; rl.msgWindowStart = now; }
  rl.msgCount++;
  if (rl.msgCount > RATE_LIMIT_MSG_PER_SEC) return true;
  if (isCreate) {
    if (now - rl.createWindowStart > 60000) { rl.createCount = 0; rl.createWindowStart = now; }
    rl.createCount++;
    if (rl.createCount > RATE_LIMIT_CREATE_PER_MIN) return true;
  }
  return false;
}

function isActRateLimited(rl: RateLimiter): boolean {
  const now = Date.now();
  if (rl.actWindowStart === undefined || now - rl.actWindowStart > 1000) { rl.actCount = 0; rl.actWindowStart = now; }
  rl.actCount = (rl.actCount ?? 0) + 1;
  return rl.actCount > RATE_LIMIT_ACT_PER_SEC;
}


function detachRoomSockets(room: Room): void {
  for (const s of room.sockets) {
    if (!s) continue;
    if (s.data.roomCode === room.code) s.data.roomCode = null;
    if (s.readyState === WS_OPEN) s.unsubscribe(room.code);
  }
}

function destroyRoom(code: string, reason?: string): void {
  const room = rooms[code];
  if (!room) return;
  const m = room.match;
  if (m && inMatch(room)) {
    m.phase      = 'finished';
    m.winner     = null;
    m.endReasons = ['room_expired', 'room_expired'];
    m.winReason  = 'room_expired';
  }
  const postMatch = !!m && m.phase === 'finished';
  closeRoom(room, 'room_expired', postMatch, { type: 'room_expired', reason: reason ?? 'inactive' });
  log('INFO', 'CLEANUP', `Room ${code} destroyed: ${reason ?? 'inactive'}`);
}

function sweepRooms(now = Date.now()): void {
  for (const code of Object.keys(rooms)) {
    const room = rooms[code];
    if (room.holdDeadline.some(d => d !== null)) continue;
    if (now - room.lastActivity > ROOM_TTL_MS) destroyRoom(code, 'ttl_expired');
  }
  sweepParties(ROOM_TTL_MS, now);
  for (const [token, ended] of endedSessions) {
    if (now - ended.at > timing.endedSessionTtlMs) endedSessions.delete(token);
  }
}

const roomCleanupInterval = setInterval(() => sweepRooms(), ROOM_CLEANUP_INTERVAL_MS);

function hostAlive(host: object): boolean {
  const code = (host as { code?: unknown }).code;
  return typeof code === 'string' && (rooms[code] === host || parties[code] === host);
}

function structureSizes(): Record<string, number> {
  return {
    rooms: Object.keys(rooms).length, parties: Object.keys(parties).length, endedSessions: endedSessions.size, queue: queue.length,
    onlineNames: onlineNames.size, nameOwners: nameOwnerKeys.size, bots: listBots().length, botWorkers: workerPoolStats().length,
    spectators: spectate.watching.size, rankedCache: ranked.cacheSize(), d1Queue: ranked.store.pending(), ...matchlogs.sizes(), ...social.sizes(), ...crashSizes(), ...traffic.sizes(),
  };
}

const memWatch = new MemoryWatch(structureSizes, line => log('WARN', 'MEMORY', line));

function memorySweep(): void {
  try { matchlogs.dropOrphans(hostAlive); } catch (e) { log('WARN', 'MATCHLOG', `orphan sweep failed: ${String(e).slice(0, 120)}`); }
  memWatch.check();
}

const memoryInterval = setInterval(() => memorySweep(), ROOM_CLEANUP_INTERVAL_MS) as unknown as { unref?: () => void };
memoryInterval.unref?.();


const forgeRelay = new ForgeRelay<BunWS>({
  findRoom: (id, code) => {
    const room = id ? findRoomById(id) : (code ? rooms[code] ?? null : null);
    if (room) return { mods: room.mods, host: seatSocket(room, 0) };
    const p = id ? findParty({ id }) : (code ? findParty({ code }) : null);
    if (!p) return null;
    const hs = p.seats[p.hostId]?.ws as unknown as BunWS | undefined;
    return { mods: p.mods as ModEntry[], host: hs && hs.readyState === WS_OPEN ? hs : null };
  },
  send: (ws, data) => sendTo(ws, data),
  log: (level, tag, msg) => log(level, tag, msg),
});

export function botModsRefusal(mods: ModEntry[] | unknown[], settings: Record<string, unknown> | undefined): string | null {
  if (blockedMods(mods as ModEntry[]).length > 0) return 'mods';
  if (settings && settings.forge_room_on === true) return 'forge';
  return null;
}

function cleanupSocket(ws: BunWS): void {
  if (movingOut) return;
  forgeRelay.drop(ws);
  l1Closed(ws);
  spectate.drop(ws);
  queue = queue.filter(s => s !== ws);
  releaseName(ws);
  social.drop(ws);
  partyCleanup(ws as never);
  const room = getRoomForSocket(ws);
  if (!room) return;

  const pid = getPlayerId(room, ws);
  if (pid < 0) return;

  if (inMatch(room)) {
    dropPlayer(room, pid, 'connection_lost');
    return;
  }

  if (guestLeavesLobby(room, pid, 'opponent_disconnected')) return;
  const postMatch = !!room.match && room.match.phase === 'finished';
  detachSeat(room, pid);
  log('INFO', 'DISCONNECT', `P${pid} disconnected from ${room.code} (post_match=${postMatch})`);
  closeRoom(room, 'opponent_disconnected', postMatch, postMatch
    ? { type: 'opponent_left', post_match: true, reason: 'opponent_disconnected' }
    : { type: 'opponent_disconnected', held: false, reason: 'opponent_disconnected' });
}

function guestLeavesLobby(room: Room, pid: number, reason: string): boolean {
  if (pid !== 1 || room.quick) return false;
  if (room.match && room.match.phase !== 'lobby') return false;
  const host = seatSocket(room, 0);
  if (!host) return false;
  const drafting = !!room.draft && room.draft.phase !== 'done';
  cancelDraft(room, drafting);
  if (drafting) sendTo(host, { type: 'draft_cancelled', reason });
  if (cancelPick(room)) sendTo(host, { type: 'pick_cancelled', reason });
  detachSeat(room, 1);
  room.holdDeadline[1] = Date.now() + timing.rejoinHoldMs;
  room.dropReason[1]   = reason;
  room.inLobby         = undefined;
  room.rematchVotes    = [false, false];
  touchRoom(room);
  scheduleHold(room);
  sendTo(host, { type: 'guest_left', reason, code: room.code, held: true, secondsLeft: secondsLeft(room, 1), holdSeconds: holdSeconds() });
  log('INFO', 'LEAVE', `Guest left lobby ${room.code}, seat held ${holdSeconds()}s`);
  return true;
}

function rejoinLobbySeat(room: Room, ws: BunWS): void {
  room.sockets[1]      = ws;
  room.holdDeadline[1] = null;
  room.dropReason[1]   = null;
  ws.data.roomCode     = room.code;
  ws.subscribe(room.code);
  scheduleHold(room);
  touchRoom(room);
  if (ws.data.name) room.playerNames[1] = ws.data.name;
  log('INFO', 'ROOM', `Guest came back to lobby ${room.code}`);
}

function quitRoom(room: Room, pid: number, legacyType: string): void {
  if (guestLeavesLobby(room, pid, 'opponent_left')) return;
  const postMatch = !!room.match && room.match.phase === 'finished';
  detachSeat(room, pid);
  log('INFO', 'LEAVE', `P${pid} left ${room.code} (post_match=${postMatch})`);
  closeRoom(room, 'opponent_left', postMatch, { type: legacyType, post_match: postMatch, reason: 'opponent_left' });
}


function handleCreateRoom(ws: BunWS, msg: Record<string, unknown>): void {
  rememberMods(ws, msg);
  if (getRoomForSocket(ws) || partyForSocket(ws as never)) { sendTo(ws, { type: 'room_error', reason: 'already_in_room' }); return; }
  const pubMods = sentOrPlain(ws, msg);
  if (msg.visibility === 'public' && blockedMods(pubMods).length > 0) { sendTo(ws, { type: 'room_error', reason: 'mods_private_only', mods: blockedMods(pubMods) }); return; }
  if (!claimName(ws, msg)) return;
  let code = generateCode();
  while (rooms[code] || parties[code]) code = generateCode();
  const room = createRoom(code);
  room.sockets.push(ws);
  room.visibility = msg.visibility === 'public' ? 'public' : 'private';
  room.mods       = room.visibility === 'public' ? plainMods(ws.data.mods) : ws.data.mods ?? [];
  room.modsFp     = (room.visibility === 'public' ? ws.data.modsFpPlain : ws.data.modsFp) ?? '';
  room.gameVersion = ws.data.gameVersion ?? '';
  if (ws.data.name) room.playerNames[0] = ws.data.name;
  rooms[code] = room;
  ws.data.roomCode = code;
  ws.subscribe(code);
  sendTo(ws, { type: 'room_created', code, id: room.id, visibility: room.visibility, modded: room.mods.length > 0, forge: forgeMods(room.mods), version: room.gameVersion, playerId: 0, token: room.tokens[0], players: roomRoster(room) });
  log('INFO', 'ROOM', `Created ${code} (${room.visibility}, mods=${room.modsFp || 'none'})`);
}

function findRoomById(id: string): Room | null {
  for (const code of Object.keys(rooms)) if (rooms[code].id === id) return rooms[code];
  return null;
}

function roomRefusal(room: Room): string | null {
  if (!seatSocket(room, 0) && !seatSocket(room, 1)) return 'room_gone';
  if (inMatch(room) || (room.match && room.match.phase === 'finished')) return 'in_match';
  if (room.sockets.length !== 1 || !seatSocket(room, 0)) return 'room_full';
  return null;
}

function mismatchPayload(room: Room, ws: BunWS): Record<string, unknown> {
  return {
    type: 'room_error',
    reason: 'mods_mismatch',
    id: room.id,
    hostModded: room.mods.length > 0,
    hostMods: room.mods,
    yourMods: ws.data.mods ?? [],
  };
}

function heldSeatFor(room: Room, token: unknown): boolean {
  return typeof token === 'string' && !inMatch(room) && room.sockets.length === 2 && !room.sockets[1]
    && room.holdDeadline[1] !== null && room.tokens[1] === token && !!seatSocket(room, 0);
}

function versionPayload(room: Room, ws: BunWS): Record<string, unknown> {
  return { type: 'room_error', reason: 'version_mismatch', id: room.id, hostVersion: room.gameVersion, yourVersion: ws.data.gameVersion ?? '',
    hostVersionName: versionNameOf(room.gameVersion), yourVersionName: versionNameOf(ws.data.gameVersion) };
}

function handleJoinRoom(ws: BunWS, msg: Record<string, unknown>): void {
  rememberMods(ws, msg);
  if (getRoomForSocket(ws) || partyForSocket(ws as never)) { sendTo(ws, { type: 'room_error', reason: 'already_in_room' }); return; }
  const code = typeof msg.code === 'string' ? msg.code.toUpperCase() : null;
  if (typeof msg.id === 'string' && codeNamesOther(msg.id, code)) {
    log('INFO', 'ROOM', `Join by code ${code}: the listed room ${msg.id} is another one`);
    msg = { ...msg, id: undefined };
  }
  const asParty = typeof msg.id === 'string' ? (!findRoomById(msg.id) && findParty({ id: msg.id })) : (code && !rooms[code] && findParty({ code }));
  if (asParty) { handlePartyMessage(ws as never, { ...msg, type: 'party_join' }); return; }
  let room: Room | null = null;
  if (typeof msg.id === 'string') {
    room = findRoomById(msg.id);
    if (!room) { sendTo(ws, { type: 'room_error', reason: 'room_gone' }); return; }
    const rejoin = heldSeatFor(room, msg.token);
    const early = rejoin ? null : roomRefusal(room);
    if (early) { sendTo(ws, { type: 'room_error', reason: early, id: room.id }); return; }
    if (room.visibility === 'private' && code !== room.code) {
      sendTo(ws, { type: 'room_error', reason: code ? 'invalid_code' : 'code_required', id: room.id });
      return;
    }
  } else if (code) {
    room = rooms[code] ?? null;
  }
  if (!room) { sendTo(ws, { type: 'room_error', reason: closedLately(code) ? 'room_gone' : 'invalid_code' }); return; }
  const rejoin = heldSeatFor(room, msg.token);
  const refusal = rejoin ? null : roomRefusal(room);
  if (refusal) { sendTo(ws, { type: 'room_error', reason: refusal, id: room.id }); return; }
  if ((ws.data.gameVersion ?? '') !== room.gameVersion) {
    log('INFO', 'ROOM', `Refused join to ${room.code}: version ${ws.data.gameVersion || 'none'} vs ${room.gameVersion || 'none'}`);
    sendTo(ws, versionPayload(room, ws));
    return;
  }
  if (joinFp(ws, room.visibility) !== room.modsFp) {
    log('INFO', 'ROOM', `Refused join to ${room.code}: mods ${joinFp(ws, room.visibility) || 'none'} vs ${room.modsFp || 'none'}`);
    sendTo(ws, mismatchPayload(room, ws));
    return;
  }
  if (!claimName(ws, msg, rejoin ? { room, pid: 1 } : undefined)) return;
  if (rejoin) {
    rejoinLobbySeat(room, ws);
  } else {
    room.sockets.push(ws);
    ws.data.roomCode = room.code;
    ws.subscribe(room.code);
    touchRoom(room);
    if (ws.data.name) room.playerNames[1] = ws.data.name;
  }
  const c = room.code;
  const base = { code: c, id: room.id, visibility: room.visibility, version: room.gameVersion, rejoined: rejoin, players: roomRoster(room), forge: forgeMods(room.mods) };
  if (room.sockets[0]) sendTo(room.sockets[0], { type: 'room_ready', ...base, host: true,  playerId: 0, token: room.tokens[0], oppBot: isBot(ws) });
  sendTo(ws, { type: 'room_ready', ...base, host: false, playerId: 1, token: room.tokens[1], settings: room.settings, hostName: room.playerNames[0] });
  log('INFO', 'ROOM', `Joined ${c}${rejoin ? ' (back to held seat)' : ''}`);
}

function handleFindMatch(ws: BunWS, msg: Record<string, unknown>): void {
  rememberMods(ws, msg);
  if (getRoomForSocket(ws)) { sendTo(ws, { type: 'room_error', reason: 'already_in_room' }); return; }
  if (!claimName(ws, msg)) return;
  const rankedQ = msg.ranked === true;
  if (rankedQ && !l1RankedGate(ws)) return;
  const qMods = sentOrPlain(ws, msg);
  if (!rankedQ && blockedMods(qMods).length > 0) { sendTo(ws, { type: 'room_error', reason: 'mods_private_only', mods: blockedMods(qMods) }); return; }
  ws.data.rankedQueue = rankedQ;
  queue = queue.filter(s => s.readyState === WS_OPEN && s !== ws);
  const fp = ws.data.modsFpPlain ?? '';
  const ver = ws.data.gameVersion ?? '';
  const idx = queue.findIndex(s => (s.data.rankedQueue === true) === rankedQ && (rankedQ ? s.data.pkey !== ws.data.pkey : (s.data.modsFpPlain ?? '') === fp) && (s.data.gameVersion ?? '') === ver);
  if (idx >= 0) {
    const opp = queue.splice(idx, 1)[0];
    let code = generateCode();
    while (rooms[code]) code = generateCode();
    const room = createRoom(code);
    room.sockets = [opp, ws];
    room.quick   = true;
    room.visibility = 'public';
    room.mods    = plainMods(ws.data.mods);
    room.modsFp  = fp;
    room.gameVersion = ver;
    if (opp.data.name) room.playerNames[0] = opp.data.name;
    if (ws.data.name) room.playerNames[1] = ws.data.name;
    if (rankedQ) { room.ranked = true; room.rankedSeed = randomSeed(); room.settings = rankedRoomSettings(room); }
    rooms[code]  = room;
    ws.data.roomCode  = code;
    opp.data.roomCode = code;
    ws.subscribe(code);
    opp.subscribe(code);
    sendTo(opp, { type: 'room_ready', code, host: true,  playerId: 0, token: room.tokens[0], players: roomRoster(room), ...l1RankedFields(room) });
    sendTo(ws,  { type: 'room_ready', code, host: false, playerId: 1, token: room.tokens[1], players: roomRoster(room), ...l1RankedFields(room) });
    log('INFO', 'MATCH', `${rankedQ ? 'Ranked' : 'Quick'} match ${code}`);
  } else {
    queue.push(ws);
    sendTo(ws, rankedQ ? { type: 'searching', ranked: true } : { type: 'searching' });
  }
}

function roomListEntry(room: Room, fps: { full: string; plain: string }, ver: string): Record<string, unknown> {
  const fp = room.visibility === 'public' ? fps.plain : fps.full;
  const players = room.sockets.filter(s => !!s).length + room.holdDeadline.filter(d => d !== null).length;
  const refusal = roomRefusal(room);
  const host = seatSocket(room, 0);
  return {
    id: room.id,
    name: room.playerNames[0],
    players: Math.min(MAX_PLAYERS, Math.max(players, room.sockets.length)),
    maxPlayers: MAX_PLAYERS,
    seatHeld: inMatch(room) ? room.holdDeadline.some(d => d !== null) : room.sockets.length === 2 && !room.sockets[1] && room.holdDeadline[1] !== null,
    roster: roomRoster(room),
    private: room.visibility === 'private',
    modded: room.mods.length > 0,
    mods: room.mods,
    sameMods: room.modsFp === fp,
    inMatch: refusal === 'in_match',
    full: refusal === 'room_full',
    joinable: refusal === null && room.gameVersion === ver,
    version: room.gameVersion,
    versionName: versionNameOf(room.gameVersion),
    sameVersion: room.gameVersion === ver,
    ping: host && typeof host.data.rtt === 'number' ? host.data.rtt : null,
    mode: typeof room.settings.mode === 'string' ? room.settings.mode : 'attrition',
    lives: typeof room.settings.starting_lives === 'number' ? room.settings.starting_lives : null,
    ante: refusal === 'in_match' && room.match ? room.match.currentAnte : null,
  };
}

function partyListExtras(e: Record<string, unknown>): Record<string, unknown> {
  const p = typeof e.id === 'string' ? findParty({ id: e.id }) : null;
  if (!p) return e;
  const st = p.settings;
  const lives = p.settings.party_kind === 'raid' ? st.raid_lives : st.starting_lives;
  let ante: number | null = null;
  if (p.phase !== 'lobby') for (const s of p.seats) if (s && (ante === null || s.ante > ante)) ante = s.ante;
  return { ...e, lives: typeof lives === 'number' ? lives : null, ante };
}

function handleListRooms(ws: BunWS, msg: Record<string, unknown>): void {
  rememberMods(ws, msg);
  const fp = ws.data.modsFp ?? '';
  const fps = { full: fp, plain: ws.data.modsFpPlain ?? '' };
  const ver = ws.data.gameVersion ?? '';
  const mine = getRoomForSocket(ws);
  const list = Object.values(rooms)
    .filter(r => r !== mine && roomRefusal(r) !== 'room_gone')
    .map(r => ({ r, e: roomListEntry(r, fps, ver) }))
    .sort((a, b) => (Number(b.e.joinable) - Number(a.e.joinable)) || (b.r.createdAt - a.r.createdAt))
    .slice(0, ROOM_LIST_MAX)
    .map(x => x.e)
    .concat(listParties(fp, ver, partyForSocket(ws as never), fps.plain).map(e => partyListExtras(e as Record<string, unknown>)))
    .slice(0, ROOM_LIST_MAX);
  sendTo(ws, { type: 'room_list', rooms: list, total: Object.keys(rooms).length, at: Date.now() });
}

function handlePing(ws: BunWS, msg: Record<string, unknown>): void {
  if (typeof msg.rtt === 'number') ws.data.rtt = msg.rtt;
  sendTo(ws, { type: 'pong', room: !!getRoomForSocket(ws) || !!partyForSocket(ws as never) });
}

function handleCancelSearch(ws: BunWS): void {
  queue = queue.filter(s => s !== ws);
  sendTo(ws, { type: 'search_cancelled' });
}

function handleRoomJoined(ws: BunWS, msg: Record<string, unknown>, raw: string | Buffer): void {
  const room = getRoomForSocket(ws);
  relay(ws, room ? JSON.stringify({ ...msg, pid: getPlayerId(room, ws), players: roomRoster(room) }) : raw);
}
function handleReadyState(ws: BunWS, _msg: Record<string, unknown>, raw: string | Buffer): void  { relay(ws, raw); }

function handleMatchSettings(ws: BunWS, msg: Record<string, unknown>, raw: string | Buffer): void {
  const room = getRoomForSocket(ws);
  if (!room || room.ranked || getPlayerId(room, ws) !== 0 || inMatch(room)) return;
  const incoming = sanitizeSettings(msg.settings);
  touchRoom(room);
  if (!incoming) { relay(ws, raw); return; }
  Object.assign(room.settings, incoming);
  relay(ws, JSON.stringify({ ...msg, settings: incoming }));
}

function handleMatchStart(ws: BunWS, msg: Record<string, unknown>, _raw: string | Buffer): void {
  const room = getRoomForSocket(ws);
  if (!room || room.sockets.length !== 2 || !seatSocket(room, 0) || !seatSocket(room, 1)) return;
  if (getPlayerId(room, ws) !== 0) return;

  cancelDraft(room);
  cancelPick(room);
  const startSettings = sanitizeSettings(msg.settings);
  if (startSettings) Object.assign(room.settings, startSettings);
  if (room.ranked) room.settings = rankedRoomSettings(room);

  const match = createMatchState(room.settings as Settings);
  match.phase = 'playing';
  assignSeeds(match, room.settings, room.ranked ? null : ((msg.seed as string) ?? null));
  if (!room.ranked) {
    rollMatchExtras(room.settings, match.seed, startSettings);
    match.finalAnte = finalAnteFor(room.settings);
    if (room.settings.stake === 'random') log('INFO', 'MATCH', `Random stake for ${room.code}: rolled ${room.settings.rolled_stake}`);
  }

  match.players[0].name = room.playerNames[0];
  match.players[1].name = room.playerNames[1];
  const pid = getPlayerId(room, ws);
  const startName = typeof msg.player_name === 'string' && msg.player_name.length <= 32 ? cleanName(msg.player_name) : '';
  if (pid >= 0 && startName && nameIsClean(startName)) {
    match.players[pid].name = startName;
    room.playerNames[pid] = startName;
  }

  room.match = match;
  resetMatchSession(room);
  touchRoom(room);
  log('INFO', 'MATCH', `Started ${room.code}: mode=${match.mode} lives=${match.startingLives} seed=${match.seed}`);

  const hostPid = pid >= 0 ? pid : 0;
  const hostWs = seatSocket(room, hostPid);
  if (hostWs && seedFor(match, hostPid) !== msg.seed) sendTo(hostWs, { type: 'match_seed', seed: seedFor(match, hostPid) });
  const oppWs = getOpponentSocket(room, ws);
  if (oppWs) {
    const m2 = JSON.parse(JSON.stringify(msg)) as Record<string, unknown>;
    m2.seed = seedFor(match, hostPid === 0 ? 1 : 0);
    if (!room.ranked) {
      const ms = (m2.settings && typeof m2.settings === 'object' ? m2.settings : {}) as Record<string, unknown>;
      ms.match_roll = room.settings.match_roll;
      if (room.settings.stake === 'random') ms.rolled_stake = room.settings.rolled_stake; else delete ms.rolled_stake;
      m2.settings = ms;
    }
    m2.players = roomRoster(room, true);
    l1StartPayload(room, m2);
    const myDeck = draftMyDeck(room, hostPid === 0 ? 1 : 0);
    if (myDeck) m2.myDeck = myDeck;
    sendTo(oppWs, m2);
  }
  broadcastMatchState(room, { event: 'match_started' });
  sendMatchSession(room);
}

function resetMatchSession(room: Room): void {
  clearHoldTimer(room);
  clearPvpTimer(room);
  stopAnteClock(room, false);
  room.holdDeadline = [null, null];
  room.dropReason   = [null, null];
  room.pvpPaused    = false;
  room.snapshots    = [null, null];
  room.rematchVotes = [false, false];
  room.endData      = [null, null];
  room.rankedSeats  = [0, 1].map(i => { const s = room.sockets[i]; return { pkey: s && !isBot(s) ? s.data.pkey : undefined, bot: !!s && isBot(s) }; });
  for (const r of room.rankedSeats) ranked.prefetch(r.pkey);
  l1StartRoom(room);
}

function sendMatchSession(room: Room): void {
  for (let i = 0; i < 2; i++) {
    const s = seatSocket(room, i);
    if (s) sendTo(s, { type: 'match_session', code: room.code, id: room.id, playerId: i, token: room.tokens[i], holdSeconds: holdSeconds(), match_id: room.match?.id, ...l1RankedFields(room) });
  }
}

function handlePlayerDeck(ws: BunWS, msg: Record<string, unknown>): void {
  const room = getRoomForSocket(ws);
  if (!room) return;
  const pid = getPlayerId(room, ws);
  if (pid < 0) return;
  room.decks[pid] = msg.deck as string;
  const opp = getOpponentSocket(room, ws);
  if (opp) sendTo(opp, { type: 'opponent_deck', deck: msg.deck, pid });
}

function handlePlayerName(ws: BunWS, msg: Record<string, unknown>): void {
  const room = getRoomForSocket(ws);
  if (!room) return;
  const pid = getPlayerId(room, ws);
  if (pid < 0) return;
  if (msg.name !== undefined && !claimName(ws, msg)) return;
  const name = ws.data.name || room.playerNames[pid];
  room.playerNames[pid] = name;
  if (room.match) {
    room.match.players[pid].name = name;
    broadcastMatchState(room);
  }
}

function blindLetter(b: unknown): string | null {
  if (typeof b !== 'string' || !b) return null;
  if (b === 'S' || b === 'B' || b === 'L') return b;
  if (b === 'Small') return 'S';
  if (b === 'Big') return 'B';
  if (b === 'Boss') return 'L';
  return null;
}

function playerProgress(room: Room, pid: number): { ante: number; blind: string } {
  const m = room.match;
  const p = m?.players[pid];
  const order = (b: string | null | undefined) => (b === 'S' ? 1 : b === 'B' ? 2 : b === 'L' ? 3 : 0);
  let ante = Number(p?.currentAnte) || 0;
  let blind = blindLetter(p?.currentBlind) ?? (ante > 0 ? 'S' : null);
  const snap = room.snapshots[pid];
  const sAnte = Number(snap?.ante) || 0;
  const sBlind = blindLetter(snap?.blind) ?? 'S';
  if (sAnte > 0 && (sAnte > ante || (sAnte === ante && order(sBlind) > order(blind)))) {
    ante = sAnte;
    blind = sBlind;
  }
  if (ante <= 0) return { ante: m?.currentAnte || 1, blind: m?.currentBlind || 'S' };
  return { ante, blind: blind ?? 'S' };
}

function releaseSwapBot(room: Room, ws: BunWS, ante: number): void {
  if (isBot(ws) || !room.match || room.match.mode !== 'swap') return;
  const pid = getPlayerId(room, ws);
  if (pid < 0) return;
  const ow = seatSocket(room, pid === 0 ? 1 : 0);
  if (!ow || !isBot(ow)) return;
  const seat = (room.match as unknown as SwapMatch).players[pid];
  if (seat && seat.swapData) return;
  ow.humanPassed(ante);
}

function handleBlindEntered(ws: BunWS, msg: Record<string, unknown>, raw: string | Buffer): void {
  const room = getRoomForSocket(ws);
  if (!room || !room.match || room.match.phase === 'finished') return;
  releaseSwapBot(room, ws, Number(msg.ante) || 0);
  const m = room.match;
  const prevAnte    = m.currentAnte;
  const prevBlind   = m.currentBlind;
  const wasPending  = m.phase === 'pvp_pending';
  const pvpRunning  = wasPending && !!m.pvpStarted;

  if (!pvpRunning) {
    m.currentAnte  = (msg.ante  as number) || m.currentAnte;
    m.currentBlind = (msg.blind as string) || m.currentBlind;
    m.isPvpBlind   = isBlindPvp(m, m.currentAnte, m.currentBlind);
  }
  const samePendingBlind = pvpRunning || (wasPending && m.isPvpBlind && prevAnte === m.currentAnte && prevBlind === m.currentBlind);

  {
    const pid = getPlayerId(room, ws);
    if (pid >= 0) {
      m.players[pid].currentAnte  = (msg.ante  as number) || m.players[pid].currentAnte;
      m.players[pid].currentBlind = (msg.blind as string) || m.players[pid].currentBlind;
    }
  }

  if (m.isPvpBlind && !samePendingBlind) {
    m.phase = 'pvp_pending';
    room.pvpPaused = false;
    m.players[0].blindFinished = false; m.players[0].score = null;
    m.players[1].blindFinished = false; m.players[1].score = null;
    m.blindReady   = [false, false];
    m.blindReadyAt = [0, 0];
    room.specBoards = [null, null];
    room.specWatch = [false, false];
  }

  touchRoom(room);
  log('INFO', 'BLIND', `Ante ${m.currentAnte} ${m.currentBlind} PvP=${m.isPvpBlind} room=${room.code}`);
  broadcastMatchState(room, { event: 'blind_entered' });
  relay(ws, raw);
  if (ASC_LIKE(m.mode)) { const pid = getPlayerId(room, ws); if (pid >= 0) ascensionPassed(room, pid); }
  if (m.mode === 'race') raceState(room);
}

function handleBlindFinished(ws: BunWS, msg: Record<string, unknown>): void {
  const room = getRoomForSocket(ws);
  if (!room || !room.match) return;
  const m   = room.match;
  const pid = getPlayerId(room, ws);
  if (pid < 0) return;

  const ownAnte  = m.players[pid].currentAnte  ?? m.currentAnte;
  const ownBlind = m.players[pid].currentBlind ?? m.currentBlind;
  if (msg.ante  !== undefined && Number(msg.ante)   !== Number(ownAnte)) {
    log('DEBUG', 'SCORE', `P${pid} blind_finished stale ante=${msg.ante} vs own=${ownAnte}, ignored`);
    return;
  }
  if (msg.blind !== undefined && msg.blind !== ownBlind) {
    log('DEBUG', 'SCORE', `P${pid} blind_finished stale blind=${msg.blind} vs own=${ownBlind}, ignored`);
    return;
  }
  if (m.isPvpBlind && m.phase !== 'pvp_pending') {
    log('DEBUG', 'SCORE', `P${pid} blind_finished after PvP already resolved (phase=${m.phase}), ignored`);
    return;
  }

  const wasFinished = m.players[pid].blindFinished;
  m.players[pid].score         = (msg.score as number) || 0;
  m.players[pid].blindFinished = true;
  touchRoom(room);
  if (m.mode === 'race' && raceProgress(room, pid, msg)) return;
  log('INFO', 'SCORE', `P${pid} score=${m.players[pid].score} ante=${m.currentAnte} pvp=${m.isPvpBlind}`);

  const opp = getOpponentSocket(room, ws);
  if (opp) {
    sendTo(opp, {
      type:     'opponent_blind_finished',
      ante:     m.currentAnte,
      blind:    m.currentBlind,
      finished: true,
      lives:    m.players[pid].lives,
      score:    m.isPvpBlind ? null : ((msg.score as number) || 0),
    });
  }

  broadcastMatchState(room, { event: 'score_submitted' });
  if (m.isPvpBlind && !wasFinished) noteDuelFinished(room, pid);
  if (m.isPvpBlind && m.players[0].blindFinished && m.players[1].blindFinished) resolvePvp(room);
}

function handleGameOver(ws: BunWS, msg: Record<string, unknown>, raw: string | Buffer): void {
  const room = getRoomForSocket(ws);
  if (!room || !room.match || room.match.phase === 'finished') return;
  const m   = room.match;
  const pid = getPlayerId(room, ws);
  if (pid < 0) return;

  if (ASC_LIKE(m.mode)) {
    const me = m.players[pid];
    if (me.status === 'eliminated') return;
    const ante = isIntInRange(msg.ante, 1, VALID_ANTE_MAX) ? (msg.ante as number) : (me.currentAnte ?? m.currentAnte);
    const blind = blindLetter(msg.blind) ?? blindLetter(me.currentBlind) ?? blindLetter(m.currentBlind) ?? 'S';
    const at = `${ante}:${blind}`;
    if ((me.lostBlinds ?? []).includes(at)) return;
    (me.lostBlinds ??= []).push(at);
    me.lives = Math.max(0, me.lives - 1);
    if (me.lives > 0) {
      log('INFO', 'GAME_OVER', `Ascension P${pid} lost ${at}, lives=${me.lives} room=${room.code}`);
      broadcastMatchState(room, { event: 'life_lost' });
      relay(ws, raw);
      return;
    }
    me.status = 'eliminated';
    me.lastAnte = ante;
    me.lastBlind = blind;
    me.lastScore = parseScore(msg.score);
    log('INFO', 'GAME_OVER', `Ascension P${pid} eliminated ante=${ante} blind=${blind} score=${me.lastScore} room=${room.code}`);
    if (isBot(ws)) ws.halt();
    relay(ws, raw);
    const oppId = pid === 0 ? 1 : 0;
    const opp = m.players[oppId];
    if (opp.status !== 'eliminated') {
      const prog = playerProgress(room, oppId);
      if (seatSocket(room, oppId) && ascensionOrder(prog.ante, prog.blind) <= ascensionOrder(ante, blind)) {
        broadcastMatchState(room, { event: 'ascension_waiting' });
        return;
      }
      opp.lastAnte  = prog.ante;
      opp.lastBlind = prog.blind;
      opp.lastScore = opp.score ?? 0;
    }
    resolveAscension(room);
    return;
  }

  if (m.isPvpBlind) {
    m.players[pid].score         = 0;
    m.players[pid].blindFinished = true;
    log('INFO', 'GAME_OVER', `P${pid} failed PvP blind room=${room.code}`);
    noteDuelFinished(room, pid);
    if (m.players[0].blindFinished && m.players[1].blindFinished) resolvePvp(room);
  } else if (!lifeOnRoundLoss(room.settings)) {
    log('INFO', 'GAME_OVER', `P${pid} lost non-PvP blind room=${room.code} no life lost (death_on_round_loss off) lives=${m.players[pid].lives}`);
    broadcastMatchState(room, { event: 'round_lost' });
  } else if (typeof msg.ante === 'number' && typeof msg.blind === 'string' && (m.players[pid].lostBlinds ?? []).includes(`${msg.ante}:${msg.blind}`)) {
    log('INFO', 'GAME_OVER', `P${pid} lost non-PvP blind ${msg.ante}:${msg.blind} again room=${room.code}, already counted, lives=${m.players[pid].lives}`);
    broadcastMatchState(room, { event: 'round_lost' });
    return;
  } else {
    if (typeof msg.ante === 'number' && typeof msg.blind === 'string') (m.players[pid].lostBlinds ??= []).push(`${msg.ante}:${msg.blind}`);
    m.players[pid].lives = Math.max(0, m.players[pid].lives - 1);
    log('INFO', 'GAME_OVER', `P${pid} lost non-PvP blind room=${room.code} lives=${m.players[pid].lives}`);
    if (m.players[pid].lives <= 0) {
      m.players[pid].status = 'eliminated';
      const winner = pid === 0 ? 1 : 0;
      const reasons: [string, string] = ['', ''];
      reasons[pid]    = 'eliminated';
      reasons[winner] = 'opponent_eliminated';
      log('INFO', 'MATCH', `P${pid} eliminated on a non-PvP blind. Winner: P${winner} room=${room.code}`);
      relay(ws, raw);
      finishMatch(room, winner, reasons, 'life_lost');
      return;
    }
    broadcastMatchState(room, { event: 'life_lost' });
  }
  relay(ws, raw);
}

const MIRROR_REASON: Record<string, string> = {
  opponent_eliminated:   'eliminated',
  eliminated:            'opponent_eliminated',
  opponent_forfeited:    'forfeited',
  forfeited:             'opponent_forfeited',
  opponent_quit:         'quit',
  quit:                  'opponent_quit',
  opponent_disconnected: 'disconnected',
  disconnected:          'opponent_disconnected',
  run_completed:         'opponent_completed',
  opponent_completed:    'run_completed',
};

function handleMatchFinished(ws: BunWS, msg: Record<string, unknown>, raw: string | Buffer): void {
  const room = getRoomForSocket(ws);
  if (!room || !room.match) return;
  const m     = room.match;
  const pid   = getPlayerId(room, ws);
  if (pid < 0) return;
  const oppId = pid === 0 ? 1 : 0;

  if (m.phase !== 'finished' && msg.result === 'win' && msg.reason === 'run_completed' && isBlindPvp(m, m.finalAnte, 'L')) {
    log('INFO', 'MATCH', `P${pid} run_completed claim ignored in ${room.code}: the final Nemesis blind decides (ante ${m.currentAnte}/${m.finalAnte}, sudden death ${m.suddenDeath})`);
    return;
  }
  if (m.phase !== 'finished') {
    let winner = m.winner;
    if (msg.result === 'win')        { winner = pid; }
    else if (msg.result === 'lose')  { winner = oppId; m.players[pid].status = 'eliminated'; }
    const reason = typeof msg.reason === 'string' ? msg.reason : (m.winReason ?? 'match_finished');
    const reasons: [string, string] = ['', ''];
    reasons[pid]   = reason;
    reasons[oppId] = MIRROR_REASON[reason] ?? reason;
    touchRoom(room);
    log('INFO', 'MATCH', `Finished ${room.code}: P${pid} ${msg.result} (${reason}) winner=P${winner}`);
    relay(ws, raw);
    finishMatch(room, winner, reasons, 'match_finished');
    return;
  }
  relay(ws, raw);
}

function handleRequestState(ws: BunWS): void {
  const room = getRoomForSocket(ws);
  if (room && room.match) broadcastMatchState(room, { event: 'state_sync' });
}

function handleRematchVote(ws: BunWS): void {
  const room = getRoomForSocket(ws);
  if (!room) return;
  const pid = getPlayerId(room, ws);
  if (pid < 0) return;
  const m = room.match;
  if (!m || m.phase !== 'finished' || !seatSocket(room, 0) || !seatSocket(room, 1)) {
    sendTo(ws, { type: 'error', reason: 'rematch_unavailable' });
    return;
  }

  if (!room.rematchVotes) room.rematchVotes = [false, false];
  room.rematchVotes[pid] = true;
  touchRoom(room);
  log('INFO', 'REMATCH', `P${pid} voted in ${room.code}`);

  const opp = getOpponentSocket(room, ws);
  if (opp) sendTo(opp, { type: 'rematch_vote' });
  sendToRoom(room, { type: 'rematch_status', votes: [...room.rematchVotes], by: pid });

  if (room.rematchVotes[0] && room.rematchVotes[1]) {
    const match = createMatchState(room.settings as Settings);
    match.phase = 'playing';
    if (room.ranked) { room.rankedSeed = randomSeed(); room.settings = rankedRoomSettings(room); }
    assignSeeds(match, room.settings, randomSeed());
    if (!room.ranked) {
      rollDeck(room.settings);
      rollMatchExtras(room.settings, match.seed);
      match.finalAnte = finalAnteFor(room.settings);
      log('INFO', 'REMATCH', `Roll for ${room.code}: stake=${room.settings.stake} rolled=${room.settings.rolled_stake ?? '-'} deck=${room.settings.rolled_deck ?? '-'}`);
    }
    log('INFO', 'REMATCH', `Both voted, new game seed=${match.seed} seed2=${match.seed2 ?? '-'} room=${room.code}`);
    match.players[0].name = m.players[0].name;
    match.players[1].name = m.players[1].name;
    room.match = match;
    resetMatchSession(room);
    const go = () => rematchGo(room, match);
    if (wantsPick(room) && pickCapable(room)) {
      const pool = room.lastPickPool ?? (Array.isArray(room.settings.deck_pool) ? room.settings.deck_pool : []);
      startPick(room, pickDeps(room), [0, 1], pickPool(room, pool), pickOpts(room, true, go));
    } else go();
  }
}

function rematchGo(room: Room, match: MatchState): void {
  if (room.match !== match) return;
  for (let i = 0; i < 2; i++) {
    const s = seatSocket(room, i);
    if (s) sendTo(s, { type: 'rematch_accepted', seed: seedFor(match, i), settings: room.settings, gameHistory: room.gameHistory, match_id: match.id });
  }
  broadcastMatchState(room, { event: 'rematch_started' });
  sendMatchSession(room);
}

function flipPair<T>(pair: T[]): void {
  const first = pair[0];
  pair[0] = pair[1];
  pair[1] = first;
}

function flipSeat(seat: number | null): number | null {
  return seat === null ? null : (seat === 0 ? 1 : 0);
}

function swapSeats(room: Room): void {
  flipPair(room.sockets);
  flipPair(room.tokens);
  flipPair(room.playerNames);
  flipPair(room.holdDeadline);
  flipPair(room.dropReason);
  flipPair(room.snapshots);
  flipPair(room.locations);
  flipPair(room.decks);
  flipPair(room.endData);
  if (room.inLobby) flipPair(room.inLobby);
  if (room.rematchVotes) flipPair(room.rematchVotes);
  if (room.match) flipPair(room.match.players);
  for (const g of room.gameHistory) {
    g.winner = flipSeat(g.winner);
    [g.p0Lives, g.p1Lives] = [g.p1Lives, g.p0Lives];
    [g.p0Name, g.p1Name] = [g.p1Name, g.p0Name];
    g.pvpResults = g.pvpResults.map(r => ({ ...r, p0Score: r.p1Score, p1Score: r.p0Score, winner: flipSeat(r.winner) }));
  }
}

function handleReturnToLobby(ws: BunWS): void {
  const room = getRoomForSocket(ws);
  if (!room) return;
  const pid = getPlayerId(room, ws);
  if (pid < 0) return;
  const alreadyInLobby = !room.match || room.match.phase === 'lobby';
  if (pid !== 0) {
    if (!alreadyInLobby) sendTo(ws, { type: 'error', reason: 'host_only' });
    return;
  }
  if (inMatch(room)) {
    sendTo(ws, { type: 'error', reason: 'match_in_progress' });
    return;
  }
  log('INFO', 'LOBBY', `Host returned both players to lobby in ${room.code}`);
  touchRoom(room);
  clearPvpTimer(room);

  const rematchCleared = !!room.rematchVotes && (room.rematchVotes[0] || room.rematchVotes[1]);
  room.inLobby = [true, true];
  if (room.quick && room.match?.phase === 'finished' && room.match.winner === 0) {
    swapSeats(room);
    log('INFO', 'LOBBY', `Quick match ${room.code}: loser is the new host`);
  }
  if (room.match) {
    const names = [room.match.players[0].name, room.match.players[1].name];
    room.match = createMatchState(room.settings as Settings);
    room.match.phase = 'lobby';
    room.match.players[0].name = names[0];
    room.match.players[1].name = names[1];
  }
  resetMatchSession(room);
  const by = getPlayerId(room, ws);
  const opp = getOpponentSocket(room, ws);
  if (opp) {
    const oid = getPlayerId(room, opp);
    sendTo(opp, { type: 'opponent_returned_to_lobby', gameHistory: room.gameHistory, code: room.code, host: oid === 0, playerId: oid, token: room.tokens[oid] });
  }
  for (let i = 0; i < 2; i++) {
    const s = seatSocket(room, i);
    if (s) sendTo(s, { type: 'lobby_returned', by, rematchCleared, settings: room.settings, gameHistory: room.gameHistory, code: room.code, host: i === 0, playerId: i, token: room.tokens[i] });
  }
}

function handleLeaveLobby(ws: BunWS): void {
  const room = getRoomForSocket(ws);
  if (!room) return;
  const pid = getPlayerId(room, ws);
  if (pid < 0) return;
  if (inMatch(room)) { dropPlayer(room, pid, 'left_to_menu'); return; }
  quitRoom(room, pid, 'opponent_left');
}

function handleReturnToMenu(ws: BunWS): void {
  const room = getRoomForSocket(ws);
  if (!room) return;
  const pid = getPlayerId(room, ws);
  if (pid < 0) return;
  if (inMatch(room)) { dropPlayer(room, pid, 'left_to_menu'); return; }
  quitRoom(room, pid, 'opponent_returned_to_menu');
}

type SessionLookup =
  | { kind: 'room'; room: Room; pid: number }
  | { kind: 'ended'; ended: EndedSession }
  | { kind: 'none'; reason: string };

function lookupSession(code: string, token: string): SessionLookup {
  const room = rooms[code];
  if (room) {
    const pid = room.tokens.indexOf(token);
    if (pid >= 0) return { kind: 'room', room, pid };
  }
  const ended = endedSessions.get(token);
  if (ended && ended.code === code) return { kind: 'ended', ended };
  return { kind: 'none', reason: room ? 'bad_token' : 'not_found' };
}

function rejoinStatusPayload(type: string, code: string, lk: SessionLookup): Record<string, unknown> {
  if (lk.kind === 'room') {
    const { room, pid } = lk;
    const m   = room.match;
    const oid = pid === 0 ? 1 : 0;
    if (m && inMatch(room)) {
      return {
        type, code, rejoinable: true, matchOver: false, reason: null,
        opponentWaiting: !!seatSocket(room, oid),
        opponentName:    m.players[oid].name,
        secondsLeft:     secondsLeft(room, pid) ?? holdSeconds(),
        mode:            m.mode,
        ante:            m.currentAnte,
      };
    }
    if (m && m.phase === 'finished') {
      return {
        type, code, rejoinable: false, matchOver: true,
        reason: m.endReasons?.[pid] ?? m.winReason ?? 'match_over',
        result: resultFor(m.winner, pid),
        opponentWaiting: false,
      };
    }
    return { type, code, rejoinable: false, matchOver: true, reason: 'no_match', opponentWaiting: false };
  }
  if (lk.kind === 'ended') {
    return { type, code, rejoinable: false, matchOver: true, reason: lk.ended.reason, result: lk.ended.result, opponentWaiting: false };
  }
  return { type, code, rejoinable: false, matchOver: true, reason: lk.reason, opponentWaiting: false };
}

function handleCheckRejoin(ws: BunWS, msg: Record<string, unknown>): void {
  const code = msg.code as string;
  sendTo(ws, rejoinStatusPayload('rejoin_status', code, lookupSession(code, msg.token as string)));
}

function replaceStaleSocket(room: Room, pid: number, ws: BunWS): void {
  const old = room.sockets[pid];
  if (!old || old === ws) return;
  detachSeat(room, pid);
  sendTo(old, { type: 'session_replaced' });
  try {
    old.close(4000, 'session_replaced');
  } catch {
    log('DEBUG', 'REJOIN', `Stale socket for P${pid} in ${room.code} was already closed`);
  }
}

function buildRejoinPayload(room: Room, pid: number): Record<string, unknown> {
  const m    = room.match!;
  const oid  = pid === 0 ? 1 : 0;
  const me   = m.players[pid];
  const op   = m.players[oid];
  const snap = room.snapshots[pid];
  return {
    type:          'rejoin_ok',
    forge:         forgeMods(room.mods),
    match_id:      m.id,
    act_seq:       matchlogs.actSeq(room, pid),
    ...l1RankedFields(room),
    code:          room.code,
    id:            room.id,
    playerId:      pid,
    host:          pid === 0,
    token:         room.tokens[pid],
    settings:      room.settings,
    seed:          seedFor(m, pid),
    myDeck:        room.decks[pid],
    phase:         m.phase,
    mode:          m.mode,
    startingLives: m.startingLives,
    pvpStartAnte:  m.pvpStartAnte,
    finalAnte:     m.finalAnte,
    suddenDeath:   m.suddenDeath,
    currentAnte:   m.currentAnte,
    currentBlind:  m.currentBlind,
    isPvpBlind:    m.isPvpBlind,
    anteTimer:     m.anteTimer,
    anteTimerBase: m.anteTimerBase,
    anteClock:     room.anteClock ? { target: room.anteClock.target === pid ? 'me' : 'opp', msLeft: anteClockLeft(room), paused: room.anteClock.remainingMs !== null } : null,
    me:  { name: me.name, lives: me.lives, status: me.status, location: room.locations[pid] },
    opp: {
      name: op.name, lives: op.lives, status: op.status, location: room.locations[oid],
      connected: !!seatSocket(room, oid), secondsLeft: secondsLeft(room, oid),
    },
    pvp: {
      pending:     m.phase === 'pvp_pending',
      started:     !!m.pvpStarted,
      paused:      room.pvpPaused,
      timerMs:     room.pvpTimer ? timing.pvpTimeoutMs : null,
      myReady:     !!m.blindReady?.[pid],
      oppReady:    !!m.blindReady?.[oid],
      myFinished:  me.blindFinished,
      oppFinished: op.blindFinished,
      myScore:     me.score,
      oppScore:    op.score,
      lastResult:  m.pvpResults[m.pvpResults.length - 1] ?? null,
    },
    pvpResults:  m.pvpResults,
    gameHistory: room.gameHistory,
    snapshot:    snap ? { data: snap.data, bytes: snap.bytes, ante: snap.ante, blind: snap.blind, seq: snap.seq, at: snap.at } : null,
    swap:        swapStatus(m as unknown as SwapMatch, pid),
    ...(room.moved?.[pid] ? { moved: true } : {}),
    boot:        BOOT_ID,
  };
}

function handleRejoinMatch(ws: BunWS, msg: Record<string, unknown>): void {
  const code = msg.code as string;
  const lk   = lookupSession(code, msg.token as string);
  if (lk.kind === 'room' && !inMatch(lk.room) && lk.room.moved?.[lk.pid]) { rejoinMovedLobby(ws, lk.room, lk.pid); return; }
  if (lk.kind !== 'room' || !inMatch(lk.room)) {
    sendTo(ws, rejoinStatusPayload('rejoin_failed', code, lk));
    return;
  }
  const { room, pid } = lk;
  const current = getRoomForSocket(ws);
  if (current && (current !== room || room.sockets[pid] !== ws)) {
    sendTo(ws, { type: 'rejoin_failed', code, rejoinable: false, matchOver: false, reason: 'already_in_room', opponentWaiting: false });
    return;
  }
  queue = queue.filter(s => s !== ws);
  replaceStaleSocket(room, pid, ws);
  room.sockets[pid]      = ws;
  ws.data.roomCode       = room.code;
  ws.subscribe(room.code);
  room.holdDeadline[pid] = null;
  room.dropReason[pid]   = null;
  scheduleHold(room);
  touchRoom(room);
  log('INFO', 'REJOIN', `P${pid} rejoined ${room.code}`);

  const opp = seatSocket(room, pid === 0 ? 1 : 0);
  const resume = room.pvpPaused && !!opp;
  const resumeMs = room.pvpMsLeft ?? timing.pvpTimeoutMs;
  if (resume) {
    room.pvpPaused = false;
    room.pvpMsLeft = null;
    schedulePvpTimeout(room, resumeMs);
  }
  sendTo(ws, buildRejoinPayload(room, pid));
  if (room.moved) room.moved[pid] = false;
  if (room.pick && !room.pick.done) resendPick(room, pid, pickDeps(room));
  if (opp) sendTo(opp, { type: 'opponent_reconnected', playerId: pid });
  if (resume) sendToRoom(room, { type: 'pvp_timer_resumed', ms: resumeMs });
  broadcastMatchState(room, { event: 'player_rejoined', rejoinedPlayer: pid });
  if (room.anteClock) resumeAnteClock(room);
  else if (room.match?.blindReady?.[pid === 0 ? 1 : 0] && !room.match?.blindReady?.[pid]) startAnteClock(room, pid);
}

function handleLeaveMatch(ws: BunWS, msg: Record<string, unknown>): void {
  const room = getRoomForSocket(ws);
  if (room) {
    const pid = getPlayerId(room, ws);
    if (pid < 0) return;
    if (!inMatch(room)) { quitRoom(room, pid, 'opponent_left'); return; }
    const m       = room.match!;
    const oid     = pid === 0 ? 1 : 0;
    const oppGone = !room.sockets[oid];
    const reasons: [string, string] = ['', ''];
    let winner: number;
    if (oppGone) {
      const dropped = room.dropReason[oid] === 'connection_lost';
      winner = pid;
      reasons[pid] = dropped ? 'stopped_waiting_opponent_dropped' : 'stopped_waiting_opponent_left';
      reasons[oid] = dropped ? 'dropped_opponent_stopped_waiting' : 'left_opponent_stopped_waiting';
    }
    else         { winner = oid; reasons[pid] = 'forfeited';             reasons[oid] = 'opponent_forfeited'; }
    detachSeat(room, pid);
    log('INFO', 'LEAVE', `P${pid} left match ${room.code} for good (opponent ${oppGone ? 'away' : 'present'})`);
    finishMatch(room, winner, reasons, oppGone ? 'left_while_waiting' : 'opponent_forfeited', 'opponent_left');
    sendTo(ws, { ...matchEndedPayload(m, pid, 'left_match'), players: roomRoster(room, true) });
    return;
  }
  if (typeof msg.code !== 'string' || typeof msg.token !== 'string') return;
  const code = msg.code;
  const lk   = lookupSession(code, msg.token);
  if (lk.kind === 'room' && inMatch(lk.room)) {
    const { room: r, pid } = lk;
    const oid = pid === 0 ? 1 : 0;
    replaceStaleSocket(r, pid, ws);
    r.rankedTo = [null, null];
    r.rankedTo[pid] = ws;
    const reasons: [string, string] = ['', ''];
    reasons[pid] = 'abandoned';
    reasons[oid] = 'opponent_abandoned';
    log('INFO', 'LEAVE', `P${pid} abandoned held match ${r.code}`);
    finishMatch(r, oid, reasons, 'opponent_abandoned', 'opponent_abandoned');
  }
  sendTo(ws, rejoinStatusPayload('rejoin_status', code, lookupSession(code, msg.token)));
}

function swapIO(room: Room): SwapIO {
  return {
    send: (pid, payload) => { const w = seatSocket(room, pid); if (w) sendTo(w, payload); },
    setSnapshot: (pid, data, ante) => {
      const prev = room.snapshots[pid];
      room.snapshots[pid] = { data, bytes: base64DecodedLength(data), seq: prev?.seq ?? null, ante, blind: 'Small', at: Date.now() };
    },
    names: () => [room.playerNames[0], room.playerNames[1]],
    log: (level, text) => log(level, 'SWAP', `${text} room=${room.code}`),
  };
}

function handleSwap(ws: BunWS, msg: Record<string, unknown>, fn: (m: SwapMatch, pid: number, msg: Record<string, unknown>, io: SwapIO) => void): void {
  const room = getRoomForSocket(ws);
  if (!room || !inMatch(room) || !room.match) return;
  const pid = getPlayerId(room, ws);
  if (pid < 0) return;
  touchRoom(room);
  const io = swapIO(room);
  const oid = pid === 0 ? 1 : 0;
  const ow = seatSocket(room, oid);
  if (ow && isBot(ow)) {
    if (msg.type === 'swap_state' && msg.run && typeof msg.run === 'object') {
      fn(room.match as unknown as SwapMatch, pid, msg, io);
      void botSwap(room, oid, msg, ow);
      return;
    }
    if (msg.type !== 'swap_state') fn(room.match as unknown as SwapMatch, oid, msg, io);
  }
  fn(room.match as unknown as SwapMatch, pid, msg, io);
}

async function botSwap(room: Room, oid: number, msg: Record<string, unknown>, bot: BotSocket): Promise<void> {
  const match = room.match;
  const round = msg.round as number;
  if (bot.swapRound === round) return;
  bot.swapRound = round;
  const r = await bot.swapRun(msg.run as Record<string, unknown>, room.playerNames[oid]);
  if (!room.match || room.match !== match || !inMatch(room)) return;
  const io = swapIO(room);
  const ok = !!r.ok && !!r.run && typeof r.run === 'object';
  if (!ok) io.log('WARN', `bot swap round=${round} failed, the human keeps their run: ${String(r.err ?? 'no run')}`);
  handleBotSwapState(room.match as unknown as SwapMatch, oid, {
    round, data: msg.data as string, hash: typeof msg.hash === 'string' ? msg.hash : null,
    ante: typeof msg.ante === 'number' ? msg.ante : null,
    run: ok ? r.run as Record<string, unknown> : { skip: true },
    facts: (ok && r.facts && typeof r.facts === 'object' ? r.facts : msg.facts ?? {}) as Record<string, unknown>,
  }, io);
}

function handleSaveSnapshot(ws: BunWS, msg: Record<string, unknown>): void {
  const room = getRoomForSocket(ws);
  if (!room || !inMatch(room)) {
    sendTo(ws, { type: 'error', reason: 'save_snapshot: no match in progress' });
    return;
  }
  const pid = getPlayerId(room, ws);
  if (pid < 0) return;
  const seq  = typeof msg.seq === 'number' ? msg.seq : null;
  if (holdsSnapshot(room.match as unknown as SwapMatch, pid)) {
    sendTo(ws, { type: 'snapshot_ack', seq, stale: true });
    return;
  }
  const prev = room.snapshots[pid];
  if (seq !== null && prev && prev.seq !== null && seq < prev.seq) {
    sendTo(ws, { type: 'snapshot_ack', seq, stale: true });
    return;
  }
  const data  = msg.data as string;
  const bytes = base64DecodedLength(data);
  room.snapshots[pid] = {
    data, bytes, seq,
    ante:  typeof msg.ante  === 'number' ? msg.ante  : null,
    blind: typeof msg.blind === 'string' ? msg.blind : null,
    at:    Date.now(),
  };
  sendTo(ws, { type: 'snapshot_ack', seq, bytes, stale: false });
}

const bossSyncSeen = new WeakMap<BunWS, string>();

function bossSyncActivity(ws: BunWS, msg: Record<string, unknown>): void {
  const room = getRoomForSocket(ws);
  const m = room?.match;
  if (!room || !m) return;
  const pid = getPlayerId(room, ws);
  if (pid < 0) return;
  const key = `${m.currentAnte}|${String(msg.hands_left)}|${String(msg.discards_left)}|${String(msg.score)}`;
  const before = bossSyncSeen.get(ws);
  bossSyncSeen.set(ws, key);
  if (before === undefined || before === key) return;
  if (m.isPvpBlind && m.phase === 'pvp_pending' && room.pvpTimer && !m.players[pid].blindFinished) schedulePvpTimeout(room);
}

function handleSetLocation(ws: BunWS, msg: Record<string, unknown>, raw: string | Buffer): void {
  const room = getRoomForSocket(ws);
  if (room) {
    const pid = getPlayerId(room, ws);
    if (pid >= 0) room.locations[pid] = msg.location as string;
    if (pid >= 0) { relay(ws, JSON.stringify({ ...msg, pid })); return; }
  }
  relay(ws, raw);
}

function handlePlayHand(ws: BunWS, msg: Record<string, unknown>): void {
  const room = getRoomForSocket(ws);
  if (!room || !room.match) return;
  const opp = getOpponentSocket(room, ws);
  const pid = getPlayerId(room, ws);

  if (pid >= 0) {
    room.match.players[pid].score = parseScore(msg.score);
  }
  if (opp) {
    sendTo(opp, {
      type:       'enemy_info',
      pid,
      score:      msg.score ?? '0',
      hands_left: msg.hands_left ?? 0,
      discards_left: typeof msg.discards_left === 'number' ? msg.discards_left : undefined,
      lives:      pid >= 0 ? room.match.players[pid].lives : undefined,
    });
  }

  const handsLeft = typeof msg.hands_left === 'number'
    ? msg.hands_left
    : (parseInt(msg.hands_left as string) || 0);
  const m = room.match;
  if (pid >= 0 && m.isPvpBlind && m.phase === 'pvp_pending' && room.pvpTimer && !m.players[pid].blindFinished) {
    schedulePvpTimeout(room);
  }
  if (handsLeft === 0 && pid >= 0 && m.isPvpBlind && m.phase === 'pvp_pending') {
    if (!m.players[pid].blindFinished) {
      m.players[pid].blindFinished = true;
      touchRoom(room);
      log('INFO', 'PVP', `P${pid} blind_finished (via play_hand) score=${m.players[pid].score}`);
      noteDuelFinished(room, pid);
      if (m.players[0].blindFinished && m.players[1].blindFinished) {
        resolvePvp(room);
      }
    }
  }
}

function handleReadyBlind(ws: BunWS): void {
  const room = getRoomForSocket(ws);
  if (!room || !room.match) return;
  const m   = room.match;
  const pid = getPlayerId(room, ws);
  if (pid < 0) return;
  releaseSwapBot(room, ws, Infinity);

  if (m.phase === 'finished') return;
  if (m.pvpStarted) {
    if (!m.players[pid].blindFinished) {
      log('INFO', 'PVP', `P${pid} ready after the PvP blind started in ${room.code}, letting them in`);
      sendTo(ws, { type: 'start_blind' });
    }
    return;
  }

  if (!m.blindReady)   m.blindReady   = [false, false];
  if (!m.blindReadyAt) m.blindReadyAt = [0, 0];
  m.blindReady[pid]   = true;
  m.blindReadyAt[pid] = Date.now();
  touchRoom(room);
  log('INFO', 'PVP', `P${pid} ready for blind in ${room.code}`);

  const opp = getOpponentSocket(room, ws);
  if (opp) sendTo(opp, { type: 'opponent_ready_blind', pid });

  if (room.anteClock && room.anteClock.target === pid) stopAnteClock(room);
  if (!m.blindReady[0] || !m.blindReady[1]) startAnteClock(room, pid === 0 ? 1 : 0);

  if (m.blindReady[0] && m.blindReady[1]) {
    m.blindReady   = [false, false];
    m.blindReadyAt = [0, 0];
    log('INFO', 'PVP', `Both ready - sending start_blind in ${room.code}`);
    m.pvpStarted = true;
    schedulePvpTimeout(room);
    sendToRoom(room, { type: 'start_blind', first: pid === 0 ? 1 : 0 });
  }
}

function handleUnreadyBlind(ws: BunWS): void {
  const room = getRoomForSocket(ws);
  if (!room || !room.match) return;
  const m   = room.match;
  const pid = getPlayerId(room, ws);
  if (pid < 0) return;

  if (!m.blindReady)   m.blindReady   = [false, false];
  if (!m.blindReadyAt) m.blindReadyAt = [0, 0];

  const now = Date.now();
  if (m.blindReady[pid] && m.blindReadyAt[pid] && (now - m.blindReadyAt[pid]) < READY_UNREADY_DEBOUNCE_MS) {
    log('DEBUG', 'PVP', `Ignored fast unready from P${pid} in ${room.code}`);
    sendTo(ws, { type: 'ready_blind_kept' });
    return;
  }

  m.blindReady[pid]   = false;
  m.blindReadyAt[pid] = 0;
  touchRoom(room);
  log('INFO', 'PVP', `P${pid} unready for blind in ${room.code}`);
  if (room.anteClock && room.anteClock.target !== pid) stopAnteClock(room);

  const opp = getOpponentSocket(room, ws);
  if (opp) sendTo(opp, { type: 'opponent_unready_blind', pid });
}


function dispatchMessage(ws: BunWS, msg: Record<string, unknown>, str: string): void {
  if (movingOut) return;
  if (wantsRestore(ws, msg)) { void restoreThenDispatch(ws, msg, str); return; }
  const activeRoom = getRoomForSocket(ws);
  if (activeRoom) touchRoom(activeRoom);
  if (l1Hook(ws, msg)) return;
  if (SPECTATE_TYPES.includes(msg.type as string)) { if (!isBot(ws)) spectate.handle(ws, msg); return; }
  if (SPEEDRUN_TYPES.includes(msg.type as string)) { if (!isBot(ws) && claimName(ws, msg)) void speedruns.handle(ws, msg); return; }
  if (msg.type === 'add_bot') { handleAddBot(ws, msg); return; }
  if (msg.type === 'remove_bot') { handleRemoveBot(ws, msg); return; }
  const rankedHandler = RANKED_HANDLERS[msg.type as string];
  if (rankedHandler) { rankedHandler(ws, msg, str); return; }
  if (SOCIAL_TYPES.includes(msg.type as string)) { if (!isBot(ws) || msg.type === 'social_emote') social.handle(ws, msg); return; }
  if (handlePartyMessage(ws as never, msg)) return;
  if (msg.type === 'spec_board' || msg.type === 'spectate') { handleDuelSpectate(ws, msg); return; }
  if (msg.type === 'live_stat') return;
  const handler = HANDLERS[msg.type as string];
  if (handler) handler(ws, msg, str);
  else relay(ws, str);
}

function handleAddBot(ws: BunWS, msg: Record<string, unknown>): void {
  if (isBot(ws)) return;
  const level: BotLevel = BOT_LEVELS.includes(msg.level as BotLevel) ? msg.level as BotLevel : 'medium';
  const pc = partyHostCheck(ws as never);
  if (pc) {
    if (!pc.host || pc.party.phase !== 'lobby') { sendTo(ws, { type: 'bot_error', reason: 'host_only' }); return; }
    const why = botModsRefusal(pc.party.mods, pc.party.settings);
    if (why) { sendTo(ws, { type: 'bot_error', reason: why }); return; }
    const names = partyNames(pc.party);
    const bot = new BotSocket(level, ws.data as unknown as Record<string, unknown>, true, botName(level, n => names.some(x => x.toLowerCase() === n.toLowerCase())));
    bot.out({ type: 'party_join', code: pc.party.code });
    log('INFO', 'BOT', `${bot.data.name} added to party ${pc.party.code}`);
    return;
  }
  const room = getRoomForSocket(ws);
  if (!room || getPlayerId(room, ws) !== 0 || inMatch(room)) { sendTo(ws, { type: 'bot_error', reason: 'host_only' }); return; }
  if (room.ranked) { sendTo(ws, { type: 'bot_error', reason: 'ranked' }); return; }
  const why = botModsRefusal(room.mods, room.settings);
  if (why) { sendTo(ws, { type: 'bot_error', reason: why }); return; }
  if (seatSocket(room, 1) || room.holdDeadline[1] !== null) { sendTo(ws, { type: 'bot_error', reason: 'room_full' }); return; }
  const bot = new BotSocket(level, ws.data as unknown as Record<string, unknown>, false, botName(level, n => (room.playerNames[0] ?? '').toLowerCase() === n.toLowerCase()));
  bot.out({ type: 'join_room', code: room.code });
  log('INFO', 'BOT', `${bot.data.name} added to room ${room.code}`);
}

function botsWith(ws: BunWS): BotSocket[] {
  const p = partyForSocket(ws as never);
  if (p) return listBots().filter(b => partyForSocket(b as never) === p);
  const room = getRoomForSocket(ws);
  return room ? listBots().filter(b => room.sockets.includes(b as unknown as BunWS)) : [];
}

function handleRemoveBot(ws: BunWS, msg: Record<string, unknown>): void {
  if (isBot(ws)) return;
  const pc = partyHostCheck(ws as never);
  const room = getRoomForSocket(ws);
  const host = pc ? pc.host : (!!room && getPlayerId(room, ws) === 0);
  if (!host) { sendTo(ws, { type: 'bot_error', reason: 'host_only' }); return; }
  const mine = botsWith(ws);
  const bot = typeof msg.name === 'string' ? mine.find(b => b.data.name === msg.name) : mine[mine.length - 1];
  if (!bot) { sendTo(ws, { type: 'bot_error', reason: 'no_bot' }); return; }
  log('INFO', 'BOT', `${bot.data.name} removed`);
  bot.leave();
}

function humansWithBot(b: BotSocket): number {
  const ph = partyHumans(b as never);
  if (ph >= 0) return ph;
  const room = getRoomForSocket(b as unknown as BunWS);
  if (!room) return 0;
  let n = 0;
  const playing = inMatch(room);
  room.sockets.forEach((s, i) => { if ((s && !isBot(s) && (playing || s.readyState === WS_OPEN)) || (!s && room.holdDeadline[i] !== null)) n++; });
  return n;
}

initBots({
  debug: currentLevel >= LOG_LEVELS.DEBUG,
  dispatch: (b, msg) => dispatchMessage(b as unknown as BunWS, msg, JSON.stringify(msg)),
  cleanup: (b) => cleanupSocket(b as unknown as BunWS),
  decode: (raw) => tryDecompress(raw),
  publish: (topic, raw) => {
    if (!server) return;
    server.publish(topic, raw);
    traffic.sent(undefined, raw, topicCount(topic));
  },
  isPvp: (b, ante, blind) => {
    if (partyForSocket(b as never)) return partyIsPvp(b as never, ante, blind);
    const room = getRoomForSocket(b as unknown as BunWS);
    return !!room?.match && isBlindPvp(room.match, ante, blind);
  },
  race: (b) => ASC_LIKE(getRoomForSocket(b as unknown as BunWS)?.match?.mode),
  swapOn: (b) => !partyForSocket(b as never) && getRoomForSocket(b as unknown as BunWS)?.match?.mode === 'swap',
  humansWith: humansWithBot,
  refuse: (b, reason) => {
    const p = partyForSocket(b as never);
    const host = p ? p.seats[p.hostId]?.ws as unknown as BunWS | undefined : (() => { const r = getRoomForSocket(b as unknown as BunWS); return r ? seatSocket(r, 0) : null; })();
    if (host && !isBot(host)) sendTo(host, { type: 'bot_error', reason, name: b.data.name });
  },
  leave: (b) => {
    const ws = b as unknown as BunWS;
    if (partyForSocket(b as never)) { dispatchMessage(ws, { type: b.playing ? 'leave_match' : 'party_leave' }, '{}'); return; }
    const room = getRoomForSocket(ws);
    if (!room) return;
    const pid = getPlayerId(room, ws);
    if (pid < 0) return;
    if (inMatch(room) || pid !== 1) { dispatchMessage(ws, { type: 'leave_match' }, '{}'); return; }
    detachSeat(room, 1);
    room.sockets.length = 1;
    room.holdDeadline[1] = null;
    room.dropReason[1] = null;
    room.playerNames[1] = '';
    room.inLobby = undefined;
    room.rematchVotes = [false, false];
    touchRoom(room);
    const host = seatSocket(room, 0);
    if (host) sendTo(host, { type: 'guest_left', reason: 'opponent_left', code: room.code, held: false, bot: true });
  },
  log: (level, tag, m) => log(level, tag, m),
  chat: (b, text) => social.chat.botLine(b as unknown as BunWS, String(b.data.name ?? ''), text),
});

function rankedSend(ws: { readyState: number } | null | undefined, data: object): void {
  noteRankResult(ws, data);
  if (ws && ws.readyState === WS_OPEN) sendTo(ws as BunWS, data);
  if (ws) social.onRanked((ws as BunWS).data?.pkey, data as Record<string, unknown>);
}

function bestScore1v1(m: MatchState, i: number): number {
  let best = 0;
  for (const r of m.pvpResults) best = Math.max(best, Number(i === 0 ? r.p0Score : r.p1Score) || 0);
  return Math.max(best, Number(m.players[i].lastScore) || 0);
}

function reportRanked1v1(room: Room): void {
  const m = room.match;
  if (!m || !room.rankedSeats) return;
  const seats = room.rankedSeats;
  room.rankedSeats = undefined;
  const socks = [0, 1].map(i => seatSocket(room, i) ?? room.rankedTo?.[i] ?? null);
  room.rankedTo = undefined;
  const match: MatchIn = {
    id: m.id ?? crypto.randomUUID(),
    mode: '1v1',
    at: Date.now(),
    seats: [0, 1].map(i => {
      const p = m.players[i];
      const result = resultFor(m.winner, i) as Result;
      return {
        pid: i, pkey: seats[i].pkey, name: p.name, bot: seats[i].bot, placement: result === 'lose' ? 2 : 1, result,
        ante: Math.max(playerProgress(room, i).ante, Number(p.lastAnte) || 0), score: bestScore1v1(m, i),
      };
    }),
  };
  try { social.onResult1v1(match.seats.map((s, i) => ({ pkey: socks[i]?.data.socialKey ?? s.pkey, bot: s.bot, result: s.result }))); } catch (e) { log('WARN', 'SOCIAL', `head to head: ${String(e).slice(0, 120)}`); }
  const results: LogResult[] = match.seats.map(s => ({ pid: s.pid ?? 0, placement: s.placement, result: s.result, score: scoreText(s.score) }));
  const rated = seats.some(s => s.pkey) && (room.ranked === true || CASUAL_RATED);
  matchlogs.finish(room, { reason: m.winReason ?? 'match_over', results, rate: rated ? match : null }).then(out => {
    if (!rated) return;
    log('INFO', 'RANKED', `1v1 ${room.code} recorded in ${ranked.store.kind}: ${match.seats.map(s => `${s.name}${s.bot ? '(bot)' : ''}=${s.pkey ? (out.get(s.pkey)?.delta ?? 'deferred') : '-'}`).join(' ')}`);
    match.seats.forEach((s, i) => { const r = s.pkey ? out.get(s.pkey) : undefined; if (r) rankedSend(socks[i], { ...r, players: roomRoster(room, true) }); });
  }).catch(e => log('WARN', 'RANKED', `1v1 record failed: ${String(e).slice(0, 160)}`));
}

const partyRanked = new WeakMap<object, { pkey?: string; bot: boolean }[]>();

function partyRankedStart(p: Party): void {
  const caps = p.seats.map(s => {
    const ws = s?.ws as BunWS | null | undefined;
    const bot = !!ws && isBot(ws);
    const pkey = ws && !bot ? ws.data.pkey : undefined;
    ranked.prefetch(pkey);
    return { pkey, bot };
  });
  partyRanked.set(p, caps);
  l1StartParty(p);
}

type PartySeat = NonNullable<Party['seats'][number]>;
type Cap = { pkey?: string; bot: boolean };

function partySeatIn(s: PartySeat, i: number, c?: Cap) {
  const placement = s.placement ?? 1;
  const result: Result = s.result === 'win' || s.result === 'lose' || s.result === 'draw' ? s.result : placement === 1 ? 'win' : 'lose';
  return { pid: i, pkey: c?.pkey, name: s.name, bot: c?.bot ?? false, placement, result, ante: Number(s.ante) || 0, score: Number(s.best) || 0, team: s.team };
}

function partyRankedOver(p: Party): void {
  const caps = partyRanked.get(p);
  partyRanked.delete(p);
  const kind = String(p.settings.party_kind ?? 'br');
  const mode: Mode = kind === 'teams' ? 'teams' : kind === 'raid' ? 'raid' : 'br';
  const all = p.seats.flatMap((s, i) => (s ? [{ s, c: caps?.[i], i }] : []));
  const seated = all.filter(x => x.c);
  const match: MatchIn = { id: p.matchId ?? crypto.randomUUID(), mode, at: Date.now(), seats: seated.map(({ s, c, i }) => partySeatIn(s, i, c)) };
  const results: LogResult[] = all.map(({ s, i }) => { const x = partySeatIn(s, i); return { pid: i, placement: x.placement, result: x.result, score: scoreText(x.score) }; });
  const rated = !!caps && caps.some(c => c.pkey) && CASUAL_RATED;
  matchlogs.finish(p, { reason: 'match_over', results, rate: rated ? match : null }).then(out => {
    if (!rated) return;
    log('INFO', 'RANKED', `${mode} recorded in ${ranked.store.kind}: ${match.seats.map(s => `${s.name}${s.bot ? '(bot)' : ''}#${s.placement}=${s.pkey ? (out.get(s.pkey)?.delta ?? 'deferred') : '-'}`).join(' ')}`);
    seated.forEach(({ s, c }) => { const r = c?.pkey ? out.get(c.pkey) : undefined; if (r) rankedSend(s.ws as BunWS | null, { ...r, party: true, players: seatRoster(p, p.seats) }); });
  }).catch(e => log('WARN', 'RANKED', `party record failed: ${String(e).slice(0, 160)}`));
}

function l1Deps() {
  return {
    record: (m: MatchIn) => ranked.recordMatch(m),
    adjust: (pkey: string, delta: number) => ranked.adjust(pkey, delta),
    log: (level: string, msg: string) => log(level, 'MATCHLOG', msg),
    onDecision: (id: string, status: string, pkeys: string[]) => { void notifyMatchDecision(id, status, pkeys); },
    onAct: (id: string, pid: number, seq: number, entries: unknown[]) => spectate.onAct(id, pid, seq, entries),
    nameOf: async (pkey: string) => (await social.currentName(pkey).catch(() => null)) || ranked.cached(pkey)?.row.name || ((await ranked.store.getPlayer(pkey))?.name ?? null),
  };
}

export const speedruns = new SpeedrunService<BunWS>({
  store: () => ranked.store,
  send: (ws, data) => { if (ws.readyState === WS_OPEN) sendTo(ws, data); },
  keyOf: (ws, msg) => l1Key(ws, msg),
  nameOf: ws => (typeof ws.data.name === 'string' ? ws.data.name : ''),
  log: (level, msg) => log(level, 'SPEEDRUN', msg),
});

export const spectate = new SpectateService<BunWS>({
  logs: () => matchlogs.liveById.values(),
  isLive: id => matchlogs.liveById.has(id),
  send: (ws, d) => sendTo(ws, d),
  keyOf: ws => ws.data.socialKey ?? ws.data.pkey,
  friendKeys: k => social.friendKeys(k),
  byRoom: code => matchlogs.of(rooms[code] ?? parties[code] ?? null),
  log: (level, msg) => log(level, 'SPECTATE', msg),
});

setMatchlogs(new MatchLogService(matchlogs.store, l1Deps()));

function l1Mods(ws: BunWS | null | undefined): { id: string; version: string }[] {
  return (ws?.data.mods ?? []).map(x => ({ id: x.id, version: x.version }));
}

function l1Host(ws: BunWS): { host: object; pid: number } | null {
  const p = partyForSocket(ws as never) as Party | null;
  if (p) { const pid = p.seats.findIndex(s => (s?.ws as unknown) === ws); return pid >= 0 ? { host: p, pid } : null; }
  const room = getRoomForSocket(ws);
  if (!room) return null;
  const pid = getPlayerId(room, ws);
  return pid >= 0 ? { host: room, pid } : null;
}

function l1Lives(host: object): (number | null)[] {
  const h = host as { match?: MatchState | null; seats?: ({ lives: number } | null)[] };
  if (h.match) return h.match.players.map(p => p.lives);
  return (h.seats ?? []).map(s => (s ? s.lives : null));
}

function l1Sync(room: Room, event?: unknown): void {
  matchlogs.sync(room, l1Lives(room), typeof event === 'string' ? event : undefined);
}

function l1Pvp(ws: BunWS): (ante: number, blind: string) => boolean {
  return (ante, blind) => {
    if (partyForSocket(ws as never)) return partyIsPvp(ws as never, ante, blind);
    const room = getRoomForSocket(ws);
    return !!room?.match && isBlindPvp(room.match, ante, blind);
  };
}

function rankedRoomSettings(room: Room): Record<string, unknown> {
  const s = rankedSettings();
  const testLives = process.env.MP_TEST_RANKED_RP ? Number(process.env.MP_TEST_RANKED_LIVES) : NaN;
  if (testLives >= 1) s.starting_lives = Math.floor(testLives);
  if (room.rankedSeed) { s.custom_seed = room.rankedSeed; s.different_seeds = false; }
  Object.assign(s, draftDecks(room));
  return s;
}

function rankedRoomRuleset(room: Room): ReturnType<typeof rankedRuleset> {
  const rs = rankedRuleset();
  rs.settings = { ...(rs.settings ?? {}), ...rankedRoomSettings(room) };
  return rs;
}

function l1RankedFields(room: Room): Record<string, unknown> {
  return room.ranked ? { ranked: true, ruleset: rankedRoomRuleset(room) } : {};
}

function l1StartPayload(room: Room, m2: Record<string, unknown>): void {
  m2.match_id = room.match?.id;
  if (room.ranked) { m2.settings = room.settings; m2.ranked = true; m2.ruleset = rankedRoomRuleset(room); }
}

function socialMet(seats: { ws: BunWS | null | undefined; name: string }[], mode: unknown, isRanked: boolean): void {
  const out: { pkey: string; name: string }[] = [];
  for (const s of seats) {
    const k = s.ws && !isBot(s.ws) ? (s.ws.data.socialKey ?? s.ws.data.pkey) : undefined;
    if (k) out.push({ pkey: k, name: s.name });
  }
  try { social.onMatch(out, mode, isRanked); } catch (e) { log('WARN', 'SOCIAL', `recent players: ${String(e).slice(0, 120)}`); }
}

function l1StartRoom(room: Room): void {
  const m = room.match;
  if (!m) return;
  socialMet([0, 1].map(i => ({ ws: room.sockets[i] ?? null, name: room.playerNames[i] ?? '' })), m.mode, room.ranked === true);
  m.id = crypto.randomUUID();
  const keys: Record<string, string> = {};
  const players = [0, 1].map(i => {
    const s = room.sockets[i] ?? null;
    if (s && !isBot(s) && s.data.pkey) keys[String(i)] = s.data.pkey;
    return { ...whoOf(s, i, room.playerNames[i]), pid: i, version: s?.data.gameVersion ?? '', mods: l1Mods(s) };
  });
  matchlogs.start(room, {
    id: m.id, mode: m.mode, ranked: room.ranked === true, private: room.visibility === 'private', kind: '1v1', settings: { ...room.settings },
    ruleset: room.ranked ? rankedRoomRuleset(room) : null, seeds: [m.seed, m.seed2].filter((x): x is string => !!x), players,
  }, keys);
  l1Sync(room);
}

function l1StartParty(p: Party): void {
  socialMet(p.seats.map(s => ({ ws: (s?.ws ?? null) as BunWS | null, name: s?.name ?? '' })), partyCfg(p.settings).kind, false);
  const id = p.matchId ?? crypto.randomUUID();
  p.matchId = id;
  const keys: Record<string, string> = {};
  const players = p.seats.flatMap((s, i) => {
    if (!s) return [];
    const ws = s.ws as BunWS | null;
    if (ws && !isBot(ws) && ws.data.pkey) keys[String(i)] = ws.data.pkey;
    return [{ ...whoOf(ws, i, s.name), pid: i, version: s.version || ws?.data.gameVersion || '', mods: l1Mods(ws) }];
  });
  matchlogs.start(p, {
    id, mode: String(p.settings.party_kind ?? 'br'), ranked: false, private: p.visibility === 'private', kind: 'party', settings: { ...p.settings },
    ruleset: null, seeds: p.seed ? [p.seed] : [], players,
  }, keys);
  matchlogs.sync(p, l1Lives(p));
}

function l1RankedGate(ws: BunWS): boolean {
  if (!ws.data.pkey) { sendTo(ws, { type: 'ranked_error', reason: 'no_key', code: 'no_key', for: 'find_match' }); return false; }
  const mods = blockedMods(plainMods(ws.data.mods));
  if (mods.length > 0) {
    log('INFO', 'RANKED', `Refused ranked queue: mods ${mods.join(',')}`);
    sendTo(ws, { type: 'ranked_error', reason: 'mods_not_allowed', code: 'mods_not_allowed', mods, for: 'find_match' });
    return false;
  }
  return true;
}

function l1Key(ws: BunWS, msg: Record<string, unknown>): string | undefined {
  return typeof msg.pkey === 'string' && PKEY_RE.test(msg.pkey) ? msg.pkey : ws.data.pkey;
}

function l1Closed(ws: BunWS): void {
  const seat = l1Host(ws);
  if (seat) matchlogs.note(seat.host, seat.pid, 'disconnect');
}

function l1Validate(msg: Record<string, unknown>): string | null {
  const t = msg.type;
  if (t === 'match_history') {
    if (msg.limit !== undefined && !isIntInRange(msg.limit, 1, 50)) return 'match_history: invalid limit';
    if (msg.before !== undefined && !isNonNegativeFinite(msg.before)) return 'match_history: invalid before';
  }
  if (t === 'contest') {
    if (!isStringOfLength(msg.match_id, 64)) return 'contest: invalid match_id';
    if (msg.reason !== undefined && (typeof msg.reason !== 'string' || msg.reason.length > 200)) return 'contest: invalid reason';
  }
  if (t === 'act') {
    if (!isIntInRange(msg.seq, 1, 10_000_000)) return 'act: invalid seq';
    if (!Array.isArray(msg.a) || msg.a.length > 500) return 'act: invalid batch';
  }
  if (t === 'replay_get' && !isStringOfLength(msg.id, 64)) return 'replay_get: invalid id';
  if (t === 'replay_hide' && !isStringOfLength(msg.id, 64)) return 'replay_hide: invalid id';
  if (t === 'daily_get' && msg.kind !== undefined && msg.kind !== 'daily' && msg.kind !== 'weekly') return 'daily_get: invalid kind';
  if (t === 'find_match' && msg.ranked !== undefined && typeof msg.ranked !== 'boolean') return 'find_match: invalid ranked';
  return null;
}

const L1_HANDLERS: Record<string, Handler> = {
  match_history: (ws, msg) => {
    const k = l1Key(ws, msg);
    if (!k || isBot(ws)) { sendTo(ws, { type: 'match_history', items: [] }); return; }
    matchlogs.history(k, typeof msg.limit === 'number' ? msg.limit : 20, typeof msg.before === 'number' ? msg.before : undefined)
      .then(items => rankedSend(ws, { type: 'match_history', items }))
      .catch(() => rankedSend(ws, { type: 'match_history', items: [], error: 'offline' }));
  },
  contest: (ws, msg) => {
    const id = String(msg.match_id);
    matchlogs.contest(id, l1Key(ws, msg), msg.reason).then(r => {
      log('INFO', 'CONTEST', `${id}: ${r.ok ? 'held' : r.reason}`);
      rankedSend(ws, { type: 'contest_result', match_id: id, ...r });
    }).catch(() => rankedSend(ws, { type: 'contest_result', match_id: id, ok: false, reason: 'unavailable' }));
  },
  act: (ws, msg) => {
    const seat = l1Host(ws);
    if (seat) matchlogs.act(seat.host, seat.pid, msg.seq, msg.a, msg.id);
    else matchlogs.actByKey(msg.id, l1Key(ws, msg), msg.seq, msg.a);
  },
  replay_get: (ws, msg) => {
    const id = String(msg.id);
    matchlogs.replay(id, l1Key(ws, msg)).then(r => {
      rankedSend(ws, 'reason' in r ? { type: 'replay_error', id, reason: r.reason } : { type: 'replay_data', ...r });
    }).catch(() => rankedSend(ws, { type: 'replay_error', id, reason: 'unavailable' }));
  },
  replay_hide: (ws, msg) => {
    const id = String(msg.id);
    matchlogs.hide(id, l1Key(ws, msg))
      .then(r => rankedSend(ws, { type: 'replay_hidden', id, ...r }))
      .catch(() => rankedSend(ws, { type: 'replay_hidden', id, ok: false, reason: 'unavailable' }));
  },
  daily_get: (ws, msg) => sendTo(ws, { type: 'daily_ruleset', ...dailyRuleset(msg.kind === 'weekly' ? 'weekly' : 'daily', Date.now()) }),
  ...dailyHandlers({
    keyOf: l1Key, isBot, send: rankedSend, nameFor: dailyName,
    friendsOf: k => social.friendsOf(k),
    onSubmit: (k, r) => social.activity(k, 'daily', { won: r.won, ante: r.ante, rank: r.rank, total: r.total }),
  }),
  ...forgeHandlers({ keyOf: l1Key, isBot, send: rankedSend }),
};

function dailyName(ws: BunWS, msg: Record<string, unknown>): string {
  if (ws.data.name) return ws.data.name;
  const k = l1Key(ws, msg);
  const prof = k ? ranked.cached(k)?.row.name : undefined;
  if (prof) return prof;
  if (msg.name === undefined) return 'Player';
  const n = cleanName(msg.name);
  return isDefaultName(n) || !nameIsClean(n) || nameHeldElsewhere(nameKey(n), ws, undefined, k) ? 'Player' : n;
}

function l1Hook(ws: BunWS, msg: Record<string, unknown>): boolean {
  const t = msg.type as string;
  const own = L1_HANDLERS[t];
  if (own) { own(ws, msg, ''); return true; }
  const seat = l1Host(ws);
  if (seat && matchlogs.observe(seat.host, seat.pid, msg, l1Pvp(ws))) {
    log('WARN', 'INTEGRITY', `Rejected ${t} from P${seat.pid}: impossible state in a ranked match`);
    return true;
  }
  queueMicrotask(() => {
    const after = l1Host(ws);
    if (!after) return;
    if (t === 'rejoin_match') matchlogs.note(after.host, after.pid, 'rejoin');
    matchlogs.sync(after.host, l1Lives(after.host), t);
  });
  return false;
}

let l1Timers = false;

function l1Start(): void {
  const ls = logStoreFor(ranked.store);
  if (ls.kind !== matchlogs.store.kind) setMatchlogs(new MatchLogService(ls, l1Deps()));
  const ds = dailyStoreFor(ranked.store);
  if (ds.kind !== daily.store.kind) setDaily(new DailyBoard(ds, { log }));
  void daily.ensure().catch(e => log('WARN', 'DAILY', `daily table not ready: ${String(e).slice(0, 120)}`));
  const fstore = forgeStoreFor(ranked.store);
  if (fstore.kind !== forgeBoard.store.kind) setForgeBoard(new ForgeBoard(fstore, { log }));
  void forgeBoard.ensure().catch(e => log('WARN', 'FORGE', `forge table not ready: ${String(e).slice(0, 120)}`));
  void matchlogs.ensure().then(() => matchlogs.sweep()).catch(e => log('WARN', 'MATCHLOG', `log tables not ready: ${String(e).slice(0, 120)}`));
  if (l1Timers) return;
  l1Timers = true;
  const sweep = setInterval(() => matchlogs.sweep(), 6 * 3_600_000) as unknown as { unref?: () => void };
  const poll = setInterval(() => { void matchlogs.pollDecisions(); }, 5 * 60_000) as unknown as { unref?: () => void };
  const specSweep = setInterval(() => spectate.sweep(), 5000) as unknown as { unref?: () => void };
  sweep.unref?.();
  poll.unref?.();
  specSweep.unref?.();
}

function rankedKey(ws: BunWS, msg: Record<string, unknown>): string | null {
  const k = typeof msg.pkey === 'string' && PKEY_RE.test(msg.pkey) ? msg.pkey : ws.data.pkey;
  if (!k) { sendTo(ws, { type: 'ranked_error', reason: 'no_key', for: msg.type }); return null; }
  if (!ws.data.pkey) ws.data.pkey = k;
  return k;
}

async function rankedState(ws: BunWS, msg: Record<string, unknown>) {
  const k = rankedKey(ws, msg);
  if (!k) return null;
  try {
    const st = await ranked.load(k, typeof msg.name === 'string' ? cleanName(msg.name) || undefined : ws.data.name);
    noteRank(ws, st.row.rp, st.row.matches > 0);
    return st;
  } catch (e) {
    log('WARN', 'RANKED', `profile load failed: ${String(e).slice(0, 160)}`);
    sendTo(ws, { type: 'ranked_error', reason: 'offline', for: msg.type });
    return null;
  }
}

const RANKED_HANDLERS: Record<string, Handler> = {
  ranked_profile: (ws, msg) => {
    void rankedState(ws, msg).then(async st => {
      if (!st) return;
      await ranked.leaderboard().catch(() => null);
      rankedSend(ws, ranked.profilePayload(st));
    });
  },
  ranked_leaderboard: (ws, msg) => {
    void rankedState(ws, msg).then(async st => {
      if (!st) return;
      const rows = await ranked.leaderboard(50);
      const pos = rows.findIndex(r => r.pkey === st.row.pkey);
      let me = pos >= 0 ? pos + 1 : null;
      if (me === null && st.row.matches > 0) me = await ranked.store.position(st.row.season, st.row.rp).catch(() => null);
      rankedSend(ws, {
        type: 'ranked_leaderboard', season: st.row.season,
        top: rows.map((r, i) => { const ri = rankOf(r.rp); return { pos: i + 1, name: r.name, rp: r.rp, rank: ri.rank, tier: ri.tier, me: r.pkey === st.row.pkey, ...devMark(r.pkey) }; }),
        me: { pos: me, rp: st.row.rp, name: st.row.name, ...devMark(st.row.pkey), ...(() => { const ri = rankOf(st.row.rp); return { rank: ri.rank, tier: ri.tier }; })() },
      });
    });
  },
  ranked_history: (ws, msg) => {
    void rankedState(ws, msg).then(async st => {
      if (!st) return;
      const rows = await ranked.store.history(st.row.pkey, 20).catch(() => []);
      rankedSend(ws, ranked.historyPayload(rows));
    });
  },
  ranked_open_pack: (ws, msg) => {
    void rankedState(ws, msg).then(st => {
      if (!st) return;
      const res = ranked.openPack(st);
      if (!res) { rankedSend(ws, { type: 'ranked_error', reason: 'no_pack', for: 'ranked_open_pack' }); return; }
      rankedSend(ws, { type: 'ranked_pack', items: res.items.map(x => ({ ...x.item, dupe: x.dupe, xp: x.xp })), levelUps: res.levelUps });
      rankedSend(ws, ranked.profilePayload(st));
    });
  },
  ranked_equip: (ws, msg) => {
    void rankedState(ws, msg).then(st => {
      if (!st) return;
      const item = typeof msg.item === 'string' && msg.item.length <= 64 ? msg.item : null;
      if (!ranked.equip(st, String(msg.slot ?? ''), item)) { rankedSend(ws, { type: 'ranked_error', reason: 'bad_item', for: 'ranked_equip' }); return; }
      rankedSend(ws, { type: 'ranked_equipped', equipped: st.equipped });
    });
  },
  ranked_recovery: (ws, msg) => {
    void rankedState(ws, msg).then(st => { if (st) rankedSend(ws, { type: 'ranked_recovery', code: st.row.recovery }); });
  },
  ranked_restore: (ws, msg) => {
    const now = Date.now();
    const tries = (ws.data.restoreTries ?? []).filter(t => now - t < 60_000);
    tries.push(now);
    ws.data.restoreTries = tries;
    if (tries.length > 5) { sendTo(ws, { type: 'ranked_error', reason: 'slow_down', for: 'ranked_restore' }); return; }
    const code = cleanRecoveryCode(msg.code);
    if (!code) { sendTo(ws, { type: 'ranked_error', reason: 'bad_code', for: 'ranked_restore' }); return; }
    ranked.store.findRecovery(code).then(row => {
      if (!row) { rankedSend(ws, { type: 'ranked_error', reason: 'bad_code', for: 'ranked_restore' }); return; }
      ws.data.pkey = row.pkey;
      rankedSend(ws, { type: 'ranked_restored', pkey: row.pkey, name: row.name, rp: row.rp, ...(() => { const ri = rankOf(row.rp); return { rank: ri.rank, tier: ri.tier }; })() });
    }).catch(() => rankedSend(ws, { type: 'ranked_error', reason: 'offline', for: 'ranked_restore' }));
  },
  ranked_badges: (ws, msg) => {
    const names = Array.isArray(msg.names) ? msg.names.filter((n): n is string => typeof n === 'string' && n.length <= 32).slice(0, 16) : [];
    const badges: Record<string, unknown> = {};
    for (const n of names) {
      const key = nameKey(cleanName(n));
      const pk = nameOwnerKeys.get(key) ?? onlineNames.get(key)?.data.pkey;
      const b = ranked.badge(pk);
      if (b) badges[n] = isDevKey(pk) ? { ...b, dev: true } : b;
    }
    sendTo(ws, { type: 'ranked_badges', badges });
  },
};

if (process.env.MP_TEST_RANKED_RP) {
  RANKED_HANDLERS.ranked_test_set = (ws, msg) => {
    void rankedState(ws, msg).then(async st => {
      if (!st) return;
      const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : undefined);
      ranked.testSet(st, { rp: num(msg.rp), packs: num(msg.packs), xp: num(msg.xp), level: num(msg.level), all: msg.all === true }, Date.now());
      log('WARN', 'RANKED', `test set ${st.row.pkey}: rp=${st.row.rp} packs=${st.row.packs}`);
      await ranked.leaderboard().catch(() => null);
      rankedSend(ws, ranked.profilePayload(st));
    });
  };
}

const NAME_CHECK_MAX = 16;
const NAME_CHECK_BAD = /[^\p{L}\p{N}\p{M} _.'!?-]/u;

export function menuInfo(): Record<string, unknown> {
  let online = 0;
  for (const s of onlineNames.values()) if (s.readyState === WS_OPEN) online++;
  const waiting = queue.filter(s => s.readyState === WS_OPEN);
  const rankedWaiting = waiting.filter(s => s.data.rankedQueue === true).length;
  let matches = 0;
  for (const room of Object.values(rooms)) if (inMatch(room)) matches++;
  return { type: 'menu_info', online, ranked_queue: rankedWaiting, queue: waiting.length - rankedWaiting, matches, ruleset: rankedRuleset() };
}

export function nameCheck(ws: BunWS | null, raw: unknown, pkey?: string): { ok: boolean; name: string; reason?: string } {
  const name = cleanName(raw);
  let reason: string | null = null;
  if (name === '') reason = 'empty';
  else if ([...name].length > NAME_CHECK_MAX) reason = 'too_long';
  else if (NAME_CHECK_BAD.test(name)) reason = 'bad_chars';
  else if (isDefaultName(name)) reason = 'default';
  else if (!nameIsClean(name)) reason = 'bad_name';
  else if (ws && nameHeldElsewhere(nameKey(name), ws, undefined, pkey)) reason = 'taken';
  return reason ? { ok: false, name, reason } : { ok: true, name };
}

const L5_HANDLERS: Record<string, Handler> = {
  menu_info: (ws) => { sendTo(ws, menuInfo()); },
  name_check: (ws, msg) => {
    const pkey = typeof msg.pkey === 'string' && PKEY_RE.test(msg.pkey) ? msg.pkey : undefined;
    sendTo(ws, { type: 'name_check', ...nameCheck(ws, msg.name, pkey) });
  },
};

const HANDLERS: Record<string, Handler> = {
  forge_room_get:  (ws, msg)     => { if (!isBot(ws)) forgeRelay.get(ws, msg); },
  forge_room_put:  (ws, msg)     => { if (!isBot(ws)) forgeRelay.put(ws, msg); },
  draft_start:     (ws)          => handleDraftStart(ws),
  draft_action:    (ws, msg)     => handleDraftAction(ws, msg),
  pick_start:      (ws, msg)     => handlePickStart(ws, msg),
  pick_set:        (ws, msg)     => handlePickSet(ws, msg),
  ...RANKED_HANDLERS,
  ...L5_HANDLERS,
  add_bot:         (ws, msg)     => handleAddBot(ws, msg),
  remove_bot:      (ws, msg)     => handleRemoveBot(ws, msg),
  create_room:     (ws, msg)     => handleCreateRoom(ws, msg),
  join_room:       (ws, msg)     => handleJoinRoom(ws, msg),
  find_match:      (ws, msg)     => handleFindMatch(ws, msg),
  list_rooms:      (ws, msg)     => handleListRooms(ws, msg),
  cancel_search:   (ws)          => handleCancelSearch(ws),
  room_joined:     handleRoomJoined,
  ready_state:     handleReadyState,
  match_settings:  handleMatchSettings,
  match_start:     handleMatchStart,
  player_name:     (ws, msg)     => handlePlayerName(ws, msg),
  ping:            (ws, msg)     => handlePing(ws, msg),
  blind_entered:   handleBlindEntered,
  blind_finished:  (ws, msg)     => handleBlindFinished(ws, msg),
  game_over:       handleGameOver,
  match_finished:  handleMatchFinished,
  request_state:   (ws)          => handleRequestState(ws),
  boss_sync:       (ws, m, raw) => { relay(ws, raw); bossSyncActivity(ws, m); },
  sabotage:        (ws, _m, raw) => relay(ws, raw),
  taunt:           (ws, _m, raw) => relay(ws, raw),
  version_mismatch: (ws, _m, raw) => relay(ws, raw),
  round_end:           () => undefined,
  life_lost:           () => undefined,
  get_end_game_jokers: (ws)      => handleGetEndGameJokers(ws),
  end_game_data:   (ws, msg)     => handleEndGameData(ws, msg),
  rematch_vote:    (ws)          => handleRematchVote(ws),
  ready_blind:     (ws)          => handleReadyBlind(ws),
  unready_blind:   (ws)          => handleUnreadyBlind(ws),
  play_hand:       (ws, msg)     => handlePlayHand(ws, msg),
  return_to_lobby: (ws)          => handleReturnToLobby(ws),
  leave_lobby:     (ws)          => handleLeaveLobby(ws),
  return_to_menu:  (ws)          => handleReturnToMenu(ws),
  set_location:    handleSetLocation,
  check_rejoin:    (ws, msg)     => handleCheckRejoin(ws, msg),
  rejoin_match:    (ws, msg)     => handleRejoinMatch(ws, msg),
  leave_match:     (ws, msg)     => handleLeaveMatch(ws, msg),
  save_snapshot:   (ws, msg)     => handleSaveSnapshot(ws, msg),
  swap_state:      (ws, msg)     => handleSwap(ws, msg, handleSwapState),
  swap_applied:    (ws, msg)     => handleSwap(ws, msg, handleSwapApplied),
  swap_ready:      (ws, msg)     => handleSwap(ws, msg, handleSwapReady),
  player_deck:     (ws, msg)     => handlePlayerDeck(ws, msg),
};


function matchIdOf(holder: object): string | null {
  const id = (holder as { matchId?: unknown }).matchId;
  return typeof id === 'string' && id !== '' ? id : null;
}

function socialDetail(ws: BunWS): PresenceDetail | null {
  const party = partyForSocket(ws as never);
  if (party) {
    const seat = party.seats.find(s => !!s && s.ws === (ws as never)) ?? null;
    const playing = party.phase === 'playing';
    const out: PresenceDetail = { where: playing ? 'match' : 'lobby', mode: partyCfg(party.settings).kind };
    if (playing) {
      const live = Number(seat?.live?.ante);
      out.ante = live > 0 ? live : seat?.ante;
      out.opponents = party.seats.filter(s => !!s && s !== seat).map(s => (s as { name: string }).name);
      if (party.settings.spectate !== false && party.visibility !== 'private') out.room = party.code;
    } else if (party.seats.filter(s => !!s && (!!s.ws || s.holdDeadline !== null)).length < PARTY_MAX) out.room = party.code;
    return out;
  }
  const room = getRoomForSocket(ws);
  if (!room) return null;
  const pid = getPlayerId(room, ws);
  const mode = room.match?.mode || (typeof room.settings.mode === 'string' ? room.settings.mode : 'attrition');
  if (inMatch(room)) {
    const mine = pid >= 0 ? room.match?.players[pid] : undefined;
    const out: PresenceDetail = { where: 'match', mode, ante: mine?.currentAnte ?? room.match?.currentAnte, opponents: pid >= 0 ? [room.playerNames[pid === 0 ? 1 : 0]].filter(Boolean) : [] };
    if (room.settings.spectate !== false && room.visibility !== 'private') out.room = room.code;
    return out;
  }
  return { where: 'lobby', mode, room: roomRefusal(room) === null ? room.code : undefined };
}

function socialLobby(ws: BunWS): LobbyInfo<BunWS> | null {
  const party = partyForSocket(ws as never);
  if (party) {
    const me = party.seats.findIndex(s => !!s && s.ws === (ws as never));
    if (me < 0) return null;
    const seats = party.seats.flatMap((s, pid) => (s && s.ws && !isBot(s.ws) ? [{ pid, ws: s.ws as unknown as BunWS }] : []));
    return { id: party.id, me, seats, matchId: matchIdOf(party) };
  }
  const room = getRoomForSocket(ws);
  if (!room) return null;
  const me = getPlayerId(room, ws);
  if (me < 0) return null;
  const seats = room.sockets.flatMap((s, pid) => (s && !isBot(s) ? [{ pid, ws: s }] : []));
  return { id: room.id, me, seats, matchId: matchIdOf(room) };
}

function socialDeps() {
  return {
    detail: socialDetail,
    lobby: socialLobby,
    lobbyAlive: (id: string) => Object.values(rooms).some(r => r.id === id) || Object.values(parties).some(p => p.id === id),
    send: (ws: BunWS, data: object) => sendTo(ws, data),
    where: (ws: BunWS): 'menu' | 'lobby' | 'match' => {
      const party = partyForSocket(ws as never);
      if (party) return party.phase === 'playing' ? 'match' : 'lobby';
      const room = getRoomForSocket(ws);
      if (room) return inMatch(room) ? 'match' : 'lobby';
      return 'menu';
    },
    inviteTarget: (ws: BunWS) => {
      const party = partyForSocket(ws as never);
      if (party) return party.phase === 'lobby' ? { code: party.code, party: true } : null;
      const room = getRoomForSocket(ws);
      return room && !inMatch(room) ? { code: room.code, party: false } : null;
    },
    roomPeers: (ws: BunWS): BunWS[] => {
      const party = partyForSocket(ws as never);
      if (party) return partySockets(party) as unknown as BunWS[];
      const room = getRoomForSocket(ws);
      return room ? room.sockets.filter((s): s is BunWS => !!s) : [];
    },
    log: (level: string, msg: string) => log(level, 'SOCIAL', msg),
  };
}

export let social = new SocialService<BunWS>(ranked.store, socialDeps());

export let updates = new UpdateService(null);
export function setUpdates(u: UpdateService): void { updates = u; }
export let release = new ReleaseService(null);
export function setRelease(r: ReleaseService): void { release = r; }

const liveSockets = new Set<BunWS>();

function adminLive(): LiveState {
  const sockets = [...liveSockets].map(ws => {
    const d = ws.data;
    return {
      name: d.name ?? '', pkey: d.pkey ?? d.socialKey ?? '', version: d.gameVersion ?? '',
      mods: (d.mods ?? []).slice(0, 80).map(m => `${m.name || m.id} ${m.version}`.trim()),
      room: d.roomCode ?? null, party: d.partyCode ?? null, where: d.socialWhere ?? '', queue: d.rankedQueue === true,
      rtt: typeof d.rtt === 'number' ? d.rtt : null, since: d.connectedAt ?? 0,
    };
  });
  const list = Object.values(rooms).map(r => ({
    code: r.code, visibility: r.visibility, ranked: r.ranked === true, quick: r.quick === true,
    mode: r.match?.mode ?? (typeof r.settings.mode === 'string' ? r.settings.mode : ''), phase: r.match?.phase ?? 'lobby',
    ante: r.match?.currentAnte ?? 0, blind: r.match?.currentBlind ?? '',
    players: r.sockets.map((ws, i) => {
      const pl = r.match?.players[i];
      const data = (ws?.data ?? {}) as { name?: string; bot?: boolean };
      const name = pl?.name || r.playerNames[i] || data.name || '';
      return { name: data.bot === true ? `${name} (bot)` : name, lives: pl?.lives ?? 0, score: pl?.score ?? null, status: pl?.status ?? '', here: ws != null };
    }).filter(pl => pl.name !== '' || pl.here),
    mods: r.mods.length, version: r.gameVersion, created: r.createdAt, activity: r.lastActivity,
  }));
  return {
    sockets, rooms: list, bots: listBots().length, conns: traffic.conns, peakConns: traffic.peakConns, totalConns: traffic.totalConns,
    matchesStarted: traffic.inn.get('match_start')?.n ?? 0, roomsMade: traffic.inn.get('create_room')?.n ?? 0,
  };
}

export const admin = new AdminService({
  query: () => {
    const store = ranked.store as unknown as { kind: string; query?: (sql: string, params?: unknown[]) => Promise<Record<string, unknown>[]> };
    return store.kind === 'd1' && typeof store.query === 'function' ? store.query.bind(store) : null;
  },
  live: adminLive,
  build: (process.env.RENDER_GIT_COMMIT ?? 'dev').slice(0, 12),
  started: traffic.started,
  memory: () => ({ ...memorySample() }),
  d1: () => ({ queries: d1Usage.queries, rowsRead: d1Usage.rowsRead, rowsWritten: d1Usage.rowsWritten, failed: d1Usage.failed }),
  log: (l, m) => log(l, 'ADMIN', m),
});

export function startServer(port = parseInt(process.env.PORT ?? '3000', 10)): Server {
  if (process.env.CF_D1_DATABASE_ID && ranked.store.kind === 'memory') setRanked(new RankedService(storeFromEnv(process.env, (l, m) => log(l, 'RANKED', m)), undefined, undefined, (l, m) => log(l, 'RANKED', m)));
  handover = handoverStoreFor(ranked.store);
  void handoverBoot();
  social.stop();
  social = new SocialService<BunWS>(ranked.store, socialDeps());
  social.start();
  void wipeForEpoch(ranked.store as unknown as { kind: string; query?: (sql: string, params?: unknown[]) => Promise<Record<string, unknown>[]> }, undefined, (l, m) => log(l, 'RANKED', m))
    .then(t => { if (t.length) ranked.clearCache(); })
    .catch(e => log('ERROR', 'RANKED', `data epoch wipe failed: ${String(e)}`));
  ranked.onSeasonEnd = (pkey, info) => { social.notify.push(pkey, 'game_info', { what: 'season_end', ...info }).catch(() => undefined); };
  void social.ensure().catch(() => undefined);
  l1Start();
  if (!updates.configured) updates = updatesFromEnv(process.env, (l, m) => log(l, 'UPDATE', m));
  void updates.manifest().catch(() => undefined);
  if (!release.configured) release = releaseFromEnv(process.env, (l, m) => log(l, 'RELEASE', m));
  const bunServer = Bun.serve<SocketData>({
    port,
    hostname: '0.0.0.0',

    fetch(req, srv) {
      const url = new URL(req.url);

      if (url.pathname === '/ping') {
        return new Response('pong', { headers: { 'Content-Type': 'text/plain', 'X-Build': (process.env.RENDER_GIT_COMMIT ?? 'dev').slice(0, 12), 'X-Uptime': String(Math.round(process.uptime())), ...traffic.headers(),
          'X-Rooms': String(Object.keys(rooms).length), 'X-Bots': String(listBots().length), ...memoryHeaders() } });
      }

      if (url.pathname === '/stats') {
        const token = process.env.STATS_TOKEN;
        if (!token || url.searchParams.get('t') !== token) return new Response('Not Found', { status: 404 });
        return Response.json({ ...traffic.snapshot(), memory: memorySample(), sizes: structureSizes() });
      }

      if (url.pathname === '/version') {
        const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || srv.requestIP(req)?.address || 'unknown';
        traffic.checked(ip);
        admin.seen(ip, 'check', url.searchParams.get('platform') ?? 'any', req.headers.get('user-agent') ?? '');
        return countHttp('/version', updates.handle(req, ip));
      }

      if (url.pathname.startsWith('/release/')) {
        const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || srv.requestIP(req)?.address || 'unknown';
        if (req.method === 'GET') traffic.checked(ip, url.pathname.endsWith('.zip'));
        if (req.method === 'GET') admin.seen(ip, url.pathname.endsWith('.zip') ? 'patch' : 'feed', url.pathname.slice('/release/'.length), req.headers.get('user-agent') ?? '');
        return countHttp(url.pathname, release.handle(req, ip));
      }

      if (url.pathname === '/admin' || url.pathname.startsWith('/admin/')) {
        const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || srv.requestIP(req)?.address || 'unknown';
        return admin.handle(req, url, ip);
      }

      if (url.pathname === '/crash') {
        const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || srv.requestIP(req)?.address || 'unknown';
        return countHttp('/crash', handleCrashRequest(req, ip));
      }

      const upgraded = srv.upgrade(req, {
        data: {
          roomCode: null,
          rl: createRateLimiter(),
        } satisfies SocketData,
      });
      if (upgraded) return undefined as unknown as Response;
      return new Response('Not Found', { status: 404 });
    },

    websocket: {
      idleTimeout: 120,

      maxPayloadLength: MAX_FRAME_BYTES,

      open(_ws) {
        traffic.opened();
        _ws.data.connectedAt = Date.now();
        liveSockets.add(_ws);
        sendTo(_ws, { type: 'server_info', boot: BOOT_ID, started: BOOT_AT });
      },

      message(ws, raw) {
        let str = typeof raw === 'string' ? raw : (raw as Buffer).toString();
        const wire = Buffer.byteLength(str, 'utf8');
        const dc = tryDecompress(str);
        if (dc) str = dc;

        const byteLength = Buffer.byteLength(str, 'utf8');

        let msg: Record<string, unknown>;
        try {
          const parsed = JSON.parse(str) as unknown;
          if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
            sendTo(ws, { type: 'error', reason: 'not an object' });
            return;
          }
          msg = parsed as Record<string, unknown>;
        } catch {
          log('WARN', 'MSG', `Malformed JSON (${byteLength} bytes)`);
          return;
        }

        traffic.received(typeof msg.type === 'string' ? msg.type : undefined, wire);
        const validationError = validateMessage(msg, byteLength);
        if (validationError) {
          log('WARN', 'VALIDATE', `Rejected ${msg.type}: ${validationError}`);
          sendTo(ws, { type: 'error', reason: validationError });
          return;
        }

        const isCreate = msg.type === 'create_room' || msg.type === 'find_match';
        const limited = msg.type === 'act' ? isActRateLimited(ws.data.rl)
          : !MATCH_FLOW_TYPES.has(msg.type as string) && isRateLimited(ws.data.rl, isCreate);
        if (limited) {
          log('WARN', 'RATELIMIT', `Socket over quota on type=${msg.type}`);
          sendTo(ws, { type: 'error', reason: 'rate_limited' });
          return;
        }

        dispatchMessage(ws, msg, str);
      },

      close(ws, _code, _reason) {
        traffic.closed();
        liveSockets.delete(ws);
        cleanupSocket(ws);
      },

      drain(_ws) {
      },
    },
  });

  server = bunServer;
  log('INFO', 'SERVER', `Balatro MP server on 0.0.0.0:${port} [Bun ${Bun.version}] [AUTHORITATIVE]`);
  alertInfo('START', `server started, build ${(process.env.RENDER_GIT_COMMIT ?? 'dev').slice(0, 12)}`);
  return bunServer;
}

if (import.meta.main) {
  startServer();
  installProcessAlerts();
  admin.start();

  process.on('SIGTERM', () => {
    if (movingOut) return;
    log('INFO', 'SERVER', 'SIGTERM - moving matches to the next server, then shutting down');
    void moveOut().finally(() => {
      server.stop(true);
      const bye = setTimeout(() => process.exit(0), 3000);
      void admin.stop().finally(() => { clearTimeout(bye); process.exit(0); });
    });
  });
}

export {
  createMatchState,
  isBlindPvp,
  createRoom,
  generateCode,
  validateMessage,
  isRateLimited,
  isActRateLimited,
  rooms,
  server,
  endedSessions,
  setTimings,
  sweepRooms,
  memorySweep,
  structureSizes,
  hostAlive,
  SNAPSHOT_MAX_BYTES,
  parties,
};

function draftDeps(room: Room): DraftDeps {
  return {
    sendTo: (pid, m) => { const w = seatSocket(room, pid); if (w) sendTo(w, m); },
    isBot: (pid) => { const w = seatSocket(room, pid); return !!w && isBot(w); },
    connected: (pid) => !!seatSocket(room, pid),
    log,
  };
}

function handleDraftStart(ws: BunWS): void {
  const room = getRoomForSocket(ws);
  if (!room || (room.match && room.match.phase !== 'finished')) return;
  const pid = getPlayerId(room, ws);
  if (pid < 0) return;
  if (room.draft && room.draft.phase !== 'done') { resendDraft(room, pid, draftDeps(room)); return; }
  if (pid !== 0 || !seatSocket(room, 0) || !seatSocket(room, 1)) { sendTo(ws, { type: 'draft_error', reason: 'not_ready' }); return; }
  if (!wantsDraft(room)) { sendTo(ws, { type: 'draft_error', reason: 'off' }); return; }
  startDraft(room, draftDeps(room), room.rankedSeed ?? null);
}

function pickDeps(room: Room): PickDeps {
  return {
    sendTo: (pid, m) => { const w = seatSocket(room, pid); if (w) sendTo(w, m); },
    isBot: (pid) => { const w = seatSocket(room, pid); return !!w && isBot(w); },
    connected: (pid) => !!seatSocket(room, pid),
    isDev: (pid) => { const w = seatSocket(room, pid); return !!w && !isBot(w) && isDevKey(w.data.pkey); },
    log,
  };
}

function handlePickStart(ws: BunWS, msg: Record<string, unknown>): void {
  const room = getRoomForSocket(ws);
  if (!room || (room.match && room.match.phase !== 'finished')) return;
  const pid = getPlayerId(room, ws);
  if (pid < 0) return;
  if (room.pick && !room.pick.done) { resendPick(room, pid, pickDeps(room)); return; }
  if (pid !== 0) { if (room.pick) resendPick(room, pid, pickDeps(room)); return; }
  if (!seatSocket(room, 0) || !seatSocket(room, 1)) { sendTo(ws, { type: 'pick_error', reason: 'not_ready' }); return; }
  if (!wantsPick(room) || !pickCapable(room)) { sendTo(ws, { type: 'pick_error', reason: 'off' }); return; }
  room.botJokerPool = cleanJokerList(msg.bot_jokers);
  startPick(room, pickDeps(room), [0, 1], pickPool(room, msg.pool), pickOpts(room, false));
}

export const PICK_MIN_BUILD = 64;

export function pickCapable(room: { gameVersion?: string | null }): boolean {
  const b = Number(room.gameVersion);
  return Number.isFinite(b) && b >= PICK_MIN_BUILD;
}

function pickPool(room: Room, sent: unknown): string[] {
  let pool = Array.isArray(sent) ? sent.filter((d): d is string => typeof d === 'string' && d.length > 0 && d.length <= 40).slice(0, 80) : [];
  const d = room.draft;
  if (d && d.phase === 'done') {
    const left = draftRemaining(d);
    pool = [...left, ...(pool.includes(RANDOM_PICK) ? [RANDOM_PICK] : [])];
  }
  room.lastPickPool = pool;
  return pool;
}

function pickOpts(room: Room, rematch: boolean, onDone?: () => void): PickOpts {
  const d = room.draft;
  return {
    rematch,
    botJokers: room.botJokerPool ?? [],
    defaultDeck: d && d.phase === 'done' ? d.deck : null,
    prev: room.lastPick ?? null,
    onDone: (p) => {
      room.lastPick = { decks: { ...p.decks }, picks: Object.fromEntries(Object.entries(p.picks).map(([k, v]) => [k, [...v]])) as Record<number, string[]> };
      for (const pid of p.pids) if (p.rolled[pid]) room.lastPick.decks[pid] = RANDOM_PICK;
      if (onDone) onDone();
    },
  };
}

function handlePickSet(ws: BunWS, msg: Record<string, unknown>): void {
  const room = getRoomForSocket(ws);
  if (!room) return;
  const pid = getPlayerId(room, ws);
  if (pid < 0) return;
  pickAction(room, pid, msg, pickDeps(room));
}

function handleDraftAction(ws: BunWS, msg: Record<string, unknown>): void {
  const room = getRoomForSocket(ws);
  if (!room) return;
  const pid = getPlayerId(room, ws);
  if (pid < 0) return;
  draftAction(room, pid, msg, draftDeps(room));
}

function raceTarget(room: Room): number {
  const t = Number(room.settings.race_target);
  return Number.isFinite(t) && t >= 1 ? Math.min(12, Math.round(t)) : 4;
}

function raceState(room: Room): void {
  const m = room.match;
  if (!m) return;
  const mm = m as unknown as { raceStart?: number };
  mm.raceStart ??= Date.now();
  const target = raceTarget(room);
  const players = [0, 1].map(i => {
    const pr = m.players[i] as unknown as { raceCleared?: number; raceAt?: number; status?: string; lives?: number };
    const prog = playerProgress(room, i);
    return { pid: i, name: room.playerNames[i], ante: prog.ante, blind: prog.blind, cleared: pr.raceCleared ?? 0, at: pr.raceAt ?? 0, alive: pr.status !== 'eliminated', lives: pr.lives ?? 0 };
  });
  for (let i = 0; i < 2; i++) {
    const w = seatSocket(room, i);
    if (w) sendTo(w, { type: 'race_state', target, goal: target * 3, you: i, players });
  }
}

function raceProgress(room: Room, pid: number, msg: Record<string, unknown>): boolean {
  const m = room.match;
  if (!m || m.phase === 'finished') return false;
  const pr = m.players[pid] as unknown as { raceCleared?: number; raceAt?: number; currentAnte?: number; currentBlind?: string };
  const ante = isIntInRange(msg.ante, 1, VALID_ANTE_MAX) ? (msg.ante as number) : (Number(pr.currentAnte) || 1);
  const blind = blindLetter(msg.blind) ?? blindLetter(pr.currentBlind) ?? 'S';
  const c = raceCleared(ante, blind);
  if (c > (pr.raceCleared ?? 0)) {
    pr.raceCleared = c;
    pr.raceAt = Date.now() - ((m as unknown as { raceStart?: number }).raceStart ?? Date.now());
  }
  raceState(room);
  if (c < raceTarget(room) * 3) return false;
  const opp = pid === 0 ? 1 : 0;
  for (let i = 0; i < 2; i++) {
    const w = seatSocket(room, i);
    if (w) sendTo(w, { type: 'race_resolved', result: i === pid ? 'win' : 'lose', winner: pid, target: raceTarget(room), reason: 'race_won' });
  }
  log('INFO', 'RACE', `P${pid} cleared ante ${ante} first in ${room.code}`);
  finishMatch(room, pid, pid === 0 ? ['race_won', 'race_lost'] : ['race_lost', 'race_won'], 'race_resolved');
  void opp;
  return true;
}

export const ROOM_JSON = ['lastPickPool', 'botJokerPool', 'lastPick', 'code', 'match', 'settings', 'gameHistory', 'lastActivity', 'rematchVotes', 'inLobby',
  'playerNames', 'tokens', 'holdDeadline', 'dropReason', 'pvpPaused', 'snapshots', 'locations', 'decks', 'quick', 'endData', 'id', 'visibility', 'mods',
  'modsFp', 'gameVersion', 'createdAt', 'rankedSeats', 'ranked', 'rankedSeed', 'specBoards', 'specWatch', 'pvpMsLeft', 'moved'] as const;
export const ROOM_SPECIAL = ['sockets', 'pvpTimer', 'holdTimer', 'rankedTo', 'anteClock', 'draft', 'pick', 'pvpEndsAt'] as const;

function botSnap(ws: unknown): Record<string, unknown> | null {
  return isBot(ws) ? ws.snapshot() : null;
}

function movesRoom(room: Room): boolean {
  if (inMatch(room)) return true;
  if (room.match && room.match.phase === 'finished') return false;
  return room.sockets.some((s, i) => (s && !isBot(s) && s.readyState === WS_OPEN) || room.holdDeadline[i] !== null);
}

function roomSnapshot(room: Room, now = Date.now()): Record<string, unknown> {
  const body: Record<string, unknown> = {};
  const src = room as unknown as Record<string, unknown>;
  for (const k of ROOM_JSON) if (src[k] !== undefined) body[k] = src[k];
  body.$seats = room.sockets.map(s => (s ? (isBot(s) ? { bot: botSnap(s) } : { human: true, live: s.readyState === WS_OPEN }) : null));
  body.$seatCount = room.sockets.length;
  const c = room.anteClock;
  body.$anteClock = c ? { target: c.target, msLeft: anteClockLeft(room) } : null;
  body.$pvpLeft = room.pvpTimer ? msLeft(room.pvpEndsAt, now) : null;
  body.$draft = room.draft ? { ...room.draft, timer: null, $left: room.draft.timer ? msLeft(room.draft.deadline, now) : null } : null;
  body.$pick = room.pick ? { ...room.pick, timer: null, $left: room.pick.timer ? msLeft(room.pick.deadline, now) : null } : null;
  body.$log = matchlogs.handoverOut(room);
  return body;
}

function restoreBot(snap: Record<string, unknown>): BotSocket {
  const b = BotSocket.restore(snap);
  return b;
}

function roomRestore(body: Record<string, unknown>, now = Date.now()): Room | null {
  const code = String(body.code ?? '');
  if (!code || rooms[code] || parties[code]) return null;
  const room = createRoom(code);
  const dst = room as unknown as Record<string, unknown>;
  for (const k of ROOM_JSON) if (body[k] !== undefined) dst[k] = body[k];
  room.moved = [false, false];
  const hold = now + timing.rejoinHoldMs;
  const seats = (body.$seats as (Record<string, unknown> | null)[] | undefined) ?? [];
  const count = Math.max(Number(body.$seatCount) || 0, seats.length);
  room.sockets = Array.from({ length: count }, () => null);
  rooms[code] = room;
  const bots: BotSocket[] = [];
  seats.forEach((seat, pid) => {
    if (!seat) return;
    if (seat.bot && typeof seat.bot === 'object') {
      const b = restoreBot(seat.bot as Record<string, unknown>);
      b.data.roomCode = code;
      b.subscribe(code);
      room.sockets[pid] = b as unknown as BunWS;
      bots.push(b);
      return;
    }
    if (seat.human) {
      if (seat.live === true || room.holdDeadline[pid] === null) {
        room.holdDeadline[pid] = hold;
        room.dropReason[pid] = 'server_moving';
      }
      room.moved![pid] = true;
    }
  });
  const ac = body.$anteClock as { target: number; msLeft: number } | null;
  room.anteClock = ac ? { target: ac.target, endsAt: now + ac.msLeft, remainingMs: ac.msLeft, handle: null } : null;
  if (typeof body.$pvpLeft === 'number') {
    room.pvpPaused = true;
    room.pvpMsLeft = body.$pvpLeft;
  }
  const dr = body.$draft as Record<string, unknown> | null;
  if (dr) {
    const left = typeof dr.$left === 'number' ? dr.$left : null;
    delete dr.$left;
    room.draft = dr as unknown as Draft;
    rearmDraft(room, draftDeps(room), left);
  }
  const pk = body.$pick as Record<string, unknown> | null;
  if (pk) {
    const left = typeof pk.$left === 'number' ? pk.$left : null;
    delete pk.$left;
    room.pick = pk as unknown as Pick;
    const match = room.match;
    const rematch = room.pick.rematch && !!match && inMatch(room);
    const opts = pickOpts(room, rematch, rematch && match ? () => rematchGo(room, match) : undefined);
    if (room.pick.done) room.pick.timer = null;
    else rearmPick(room, pickDeps(room), left, opts.onDone);
  }
  if (body.$log) matchlogs.handoverIn(room, body.$log);
  scheduleHold(room);
  touchRoom(room);
  log('INFO', 'HANDOVER', `Restored room ${code} (${room.match?.phase ?? 'lobby'}, ante ${room.match?.currentAnte ?? '-'}, bots ${bots.length})`);
  for (const b of bots) b.continueRun();
  return room;
}

function rejoinMovedLobby(ws: BunWS, room: Room, pid: number): void {
  const current = getRoomForSocket(ws);
  if ((current && current !== room) || partyForSocket(ws as never)) {
    sendTo(ws, { type: 'rejoin_failed', code: room.code, rejoinable: false, matchOver: false, reason: 'already_in_room', opponentWaiting: false });
    return;
  }
  replaceStaleSocket(room, pid, ws);
  room.sockets[pid] = ws;
  ws.data.roomCode = room.code;
  ws.subscribe(room.code);
  room.holdDeadline[pid] = null;
  room.dropReason[pid] = null;
  if (room.moved) room.moved[pid] = false;
  if (ws.data.name) room.playerNames[pid] = ws.data.name;
  scheduleHold(room);
  touchRoom(room);
  sendTo(ws, {
    type: 'lobby_rejoined', moved: true, boot: BOOT_ID, code: room.code, id: room.id, playerId: pid, host: pid === 0, token: room.tokens[pid],
    visibility: room.visibility, version: room.gameVersion, settings: room.settings, players: roomRoster(room), forge: forgeMods(room.mods),
    opponentConnected: !!seatSocket(room, pid === 0 ? 1 : 0),
  });
  const other = seatSocket(room, pid === 0 ? 1 : 0);
  if (other) sendTo(other, { type: 'opponent_reconnected', playerId: pid, lobby: true });
  if (room.draft && room.draft.phase !== 'done') resendDraft(room, pid, draftDeps(room));
  if (room.pick) resendPick(room, pid, pickDeps(room));
  log('INFO', 'HANDOVER', `P${pid} back in moved lobby ${room.code}`);
}

function handoverEntries(now = Date.now()): HandoverEntry[] {
  const out: HandoverEntry[] = [];
  for (const room of Object.values(rooms)) {
    if (!movesRoom(room)) continue;
    try {
      out.push({ code: room.code, kind: 'room', tokens: [...room.tokens], at: now, boot: BOOT_ID, body: roomSnapshot(room, now) });
    } catch (e) {
      log('ERROR', 'HANDOVER', `room ${room.code} snapshot failed: ${(e as Error).message}`);
    }
  }
  for (const p of Object.values(parties)) {
    if (p.phase !== 'playing') continue;
    try {
      out.push({ code: p.code, kind: 'party', tokens: p.seats.flatMap(s => (s ? [s.token] : [])), at: now, boot: BOOT_ID, body: partySnapshot(p, botSnap, now) });
    } catch (e) {
      log('ERROR', 'HANDOVER', `party ${p.code} snapshot failed: ${(e as Error).message}`);
    }
  }
  return out;
}

function restoreEntry(e: HandoverEntry): boolean {
  if (e.kind === 'room') return !!roomRestore(e.body);
  if (rooms[e.code] || parties[e.code]) return false;
  partyRestore(e.body, (snap, p) => {
    const b = restoreBot(snap);
    b.data.partyCode = p.code;
    queueMicrotask(() => b.continueRun());
    return b as unknown as never;
  });
  return true;
}

const restoring = new Map<string, Promise<boolean>>();

async function restoreCode(code: string, token: string, retry: boolean): Promise<boolean> {
  const t0 = Date.now();
  for (;;) {
    if (rooms[code] || parties[code]) return true;
    let e: HandoverEntry | null = null;
    try { e = await handover.find(code); } catch (err) { log('WARN', 'HANDOVER', `read ${code} failed: ${String(err).slice(0, 120)}`); }
    if (rooms[code] || parties[code]) return true;
    if (e) {
      if (e.boot === BOOT_ID) return false;
      if (!e.tokens.includes(token)) return false;
      const ok = restoreEntry(e);
      handoverCodes.delete(code);
      void handover.drop(code).catch(() => undefined);
      if (ok) log('INFO', 'HANDOVER', `${e.kind} ${code} moved here from server ${e.boot} (written ${Date.now() - e.at} ms ago)`);
      return ok;
    }
    if (!retry || Date.now() - t0 >= handoverTiming.retryMs) return false;
    await new Promise(r => setTimeout(r, handoverTiming.retryStepMs));
  }
}

function wantsRestore(ws: BunWS, msg: Record<string, unknown>): boolean {
  if (msg.type !== 'rejoin_match' && msg.type !== 'check_rejoin') return false;
  if (msg.$restored === true || isBot(ws)) return false;
  const code = msg.code;
  const token = msg.token;
  if (typeof code !== 'string' || typeof token !== 'string' || !TOKEN_RE.test(token) || code.length > 16) return false;
  if (rooms[code] || parties[code]) return false;
  if (endedSessions.has(token) || closedLately(code)) return false;
  return true;
}

async function restoreThenDispatch(ws: BunWS, msg: Record<string, unknown>, str: string): Promise<void> {
  const code = msg.code as string;
  const retry = msg.type === 'rejoin_match' && Date.now() - BOOT_AT < handoverTiming.retryWindowMs;
  let p = restoring.get(code);
  if (!p) {
    p = restoreCode(code, msg.token as string, retry).finally(() => restoring.delete(code));
    restoring.set(code, p);
  }
  try { await p; } catch { }
  if (ws.readyState !== WS_OPEN || movingOut) return;
  dispatchMessage(ws, { ...msg, $restored: true }, str);
}

async function moveOut(): Promise<number> {
  movingOut = true;
  clearInterval(roomCleanupInterval);
  const entries = handoverEntries();
  const moving = new Set(entries.map(e => e.code));
  const socks = [...liveSockets];
  for (const ws of socks) {
    const code = ws.data.roomCode ?? ws.data.partyCode ?? null;
    const mine = code && moving.has(code) ? code : null;
    try { ws.send(JSON.stringify(mine ? { type: 'server_moving', code: mine, party: !!parties[mine] } : { type: 'server_moving' })); } catch { }
  }
  stopBots();
  const t0 = Date.now();
  const writing = withBudget(handover.put(entries), handoverTiming.writeBudgetMs, -1);
  await new Promise(r => setTimeout(r, handoverTiming.closeDelayMs));
  for (const ws of socks) { try { ws.close(4100, 'server_moving'); } catch { } }
  const n = await writing;
  log(n === entries.length ? 'INFO' : 'ERROR', 'HANDOVER', `wrote ${n < 0 ? 'nothing (timed out)' : n}/${entries.length} rooms and parties to ${handover.kind} in ${Date.now() - t0} ms: ${[...moving].join(' ') || '-'}`);
  return n;
}

async function handoverBoot(): Promise<void> {
  try {
    await handover.init();
    for (const c of await handover.codes()) handoverCodes.add(c);
    if (handoverCodes.size) log('INFO', 'HANDOVER', `${handoverCodes.size} rooms or parties waiting to move here: ${[...handoverCodes].join(' ')}`);
  } catch (e) {
    log('WARN', 'HANDOVER', `table not ready: ${String(e).slice(0, 120)}`);
  }
}

export const handoverApi = {
  entries: handoverEntries,
  restore: restoreEntry,
  restoreCode,
  moveOut,
  roomSnapshot,
  roomRestore,
  setStore: (s: HandoverStore) => { handover = s; },
  store: () => handover,
  reset: () => { movingOut = false; },
};
