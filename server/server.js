
const http = require('http');
const { WebSocketServer } = require('ws');

const server = http.createServer((req, res) => {
  if (req.url === '/ping') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('pong');
    return;
  }
  res.writeHead(404);
  res.end();
});

const wss = new WebSocketServer({ server });


const LOG_LEVEL = process.env.LOG_LEVEL || 'INFO';
const LOG_LEVELS = { ERROR: 0, WARN: 1, INFO: 2, DEBUG: 3 };
const currentLevel = LOG_LEVELS[LOG_LEVEL] ?? LOG_LEVELS.INFO;

function log(level, tag, msg, extra) {
  if ((LOG_LEVELS[level] ?? 99) > currentLevel) return;
  const ts = new Date().toISOString();
  const base = `${ts} [${level}][${tag}] ${msg}`;
  if (extra !== undefined) {
    console.log(base, typeof extra === 'object' ? JSON.stringify(extra) : extra);
  } else {
    console.log(base);
  }
}


const RATE_LIMIT_MSG_PER_SEC    = 60;
const RATE_LIMIT_CREATE_PER_MIN = 5;
const ROOM_TTL_MS               = 30 * 60 * 1000;
const ROOM_CLEANUP_INTERVAL_MS  = 60 * 1000;
const PVP_TIMEOUT_MS            = 180 * 1000;
const MAX_MESSAGE_BYTES         = 4096;
const READY_UNREADY_DEBOUNCE_MS = 900;

const VALID_SCORE_MAX = 1e15;
const VALID_ANTE_MAX  = 20;
const VALID_LIVES_MAX = 20;

const MAX_GAME_HISTORY = 50;

const SERVER_PROTOCOL_VERSION = 1;


const rooms = {};
let queue = [];

function generateCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return Array.from({ length: 4 }, () => chars[Math.floor(Math.random() * chars.length)]).join('');
}


function createMatchState(settings) {
  const lives = (settings && settings.starting_lives) || 4;
  const mode  = (settings && settings.mode) || 'attrition';
  return {
    phase: 'lobby',
    mode,
    startingLives: lives,
    pvpStartAnte: mode === 'showdown'
      ? (((settings && settings.showdown_starting_antes) || 3) - 1)
      : (((settings && settings.pvp_start_round) || 2) - 1),
    seed: null,
    players: {
      0: { name: 'Player 1', lives, status: 'active', score: null, blindFinished: false },
      1: { name: 'Player 2', lives, status: 'active', score: null, blindFinished: false },
    },
    currentAnte: 1,
    currentBlind: 'S',
    isPvpBlind: false,
    pvpResults: [],
    winner: null,
    winReason: null,
    anteTimer:     (settings && settings.ante_timer)      || false,
    anteTimerBase: (settings && settings.ante_timer_base) || 120,
    anteTimerSkips: 0,
  };
}

function isBlindPvp(match, ante, blindType) {
  if (match.mode === 'vanilla') return false;
  if (match.mode === 'attrition' || match.mode === 'ruleset') {
    return blindType === 'L' && ante > match.pvpStartAnte;
  } else if (match.mode === 'showdown') {
    return ante > match.pvpStartAnte;
  }
  return false;
}


function createRoom(code) {
  return {
    code,
    sockets: [],
    match: null,
    settings: { mode: 'attrition', starting_lives: 4 },
    gameHistory: [],
    lastActivity: Date.now(),
    pvpTimer: null,
  };
}

function getPlayerId(room, socket) {
  return room.sockets.indexOf(socket);
}

function getOpponentSocket(room, socket) {
  const idx = room.sockets.indexOf(socket);
  if (idx === -1) return null;
  const opp = room.sockets[idx === 0 ? 1 : 0];
  return (opp && opp.readyState === 1) ? opp : null;
}

function sendTo(socket, data) {
  if (socket && socket.readyState === 1) {
    socket.send(JSON.stringify(data));
  }
}

function sendToRoom(room, data) {
  room.sockets.forEach(s => sendTo(s, data));
}

function relay(socket, raw) {
  const code = socket.roomCode;
  const room = rooms[code];
  if (!room) return;
  const msg = typeof raw === 'string' ? raw : raw.toString();
  room.sockets.forEach(s => {
    if (s !== socket && s.readyState === 1) s.send(msg);
  });
}

const RELAYABLE_TYPES = new Set([
  'sabotage', 'taunt', 'set_location',
]);
function safeRelay(socket, msg, raw) {
  if (!msg || !RELAYABLE_TYPES.has(msg.type)) return;
  relay(socket, raw);
}

function touchRoom(room) {
  room.lastActivity = Date.now();
}


function broadcastMatchState(room, extra) {
  if (!room || !room.match) return;
  const m = room.match;
  for (let i = 0; i < 2; i++) {
    const s = room.sockets[i];
    if (!s || s.readyState !== 1) continue;
    const opp = i === 0 ? 1 : 0;
    sendTo(s, {
      type: 'match_state_update',
      ...(extra || {}),
      phase: m.phase,
      playerId: i,
      currentAnte: m.currentAnte,
      currentBlind: m.currentBlind,
      isPvpBlind: m.isPvpBlind,
      myLives: m.players[i].lives,
      myStatus: m.players[i].status,
      myScore: m.players[i].score,
      myBlindFinished: m.players[i].blindFinished,
      oppName: m.players[opp].name,
      oppLives: m.players[opp].lives,
      oppStatus: m.players[opp].status,
      oppScore: m.isPvpBlind ? null : m.players[opp].score,
      oppBlindFinished: m.players[opp].blindFinished,
      winner: m.winner,
      winReason: m.winReason,
    });
  }
}


function clearPvpTimer(room) {
  if (room.pvpTimer) { clearTimeout(room.pvpTimer); room.pvpTimer = null; }
}

function resolvePvp(room) {
  const m = room.match;
  if (!m || m.phase !== 'pvp_pending') return;
  if (!m.players[0].blindFinished || !m.players[1].blindFinished) return;

  clearPvpTimer(room);

  const s0 = m.players[0].score || 0;
  const s1 = m.players[1].score || 0;
  let loserId = null;
  let winnerId = null;
  if (s0 > s1) { winnerId = 0; loserId = 1; }
  else if (s1 > s0) { winnerId = 1; loserId = 0; }
  if (loserId !== null) m.players[loserId].lives = Math.max(0, m.players[loserId].lives - 1);

  m.pvpResults.push({ ante: m.currentAnte, blind: m.currentBlind, p0Score: s0, p1Score: s1, winner: winnerId });
  log('INFO', 'PVP', `Ante ${m.currentAnte} => P0=${s0} P1=${s1} winner=${winnerId !== null ? winnerId : 'draw'}`);

  let matchEnded = false;
  for (let i = 0; i < 2; i++) {
    if (m.players[i].lives <= 0) {
      m.players[i].status = 'eliminated';
      m.winner = i === 0 ? 1 : 0;
      m.winReason = 'opponent_eliminated';
      m.phase = 'finished';
      matchEnded = true;
      log('INFO', 'MATCH', `Player ${i} eliminated. Winner: Player ${m.winner}`);
    }
  }

  for (let i = 0; i < 2; i++) {
    const s = room.sockets[i];
    if (!s || s.readyState !== 1) continue;
    const opp = i === 0 ? 1 : 0;
    sendTo(s, {
      type: 'pvp_resolved',
      result: winnerId === null ? 'draw' : (winnerId === i ? 'win' : 'lose'),
      myScore: m.players[i].score || 0,
      oppScore: m.players[opp].score || 0,
      myLives: m.players[i].lives,
      oppLives: m.players[opp].lives,
      matchEnded,
      winner: m.winner,
      winReason: m.winReason,
    });
  }

  m.players[0].score = null; m.players[0].blindFinished = false;
  m.players[1].score = null; m.players[1].blindFinished = false;
  m.blindReady = [false, false];
  m.blindReadyAt = [0, 0];
  if (!matchEnded) m.phase = 'playing';
}

function schedulePvpTimeout(room) {
  clearPvpTimer(room);
  room.pvpTimer = setTimeout(() => {
    const m = room.match;
    if (!m || m.phase !== 'pvp_pending') return;
    log('WARN', 'PVP', `Timeout in room ${room.code} � forcing score 0 for idle player(s)`);
    if (!m.players[0].blindFinished) { m.players[0].score = 0; m.players[0].blindFinished = true; }
    if (!m.players[1].blindFinished) { m.players[1].score = 0; m.players[1].blindFinished = true; }
    resolvePvp(room);
  }, PVP_TIMEOUT_MS);
}

function extendPvpTimeoutOnActivity(room) {
  if (!room || !room.match || room.match.phase !== 'pvp_pending') return;
  if (!room.pvpTimer) return;
  schedulePvpTimeout(room);
}


const ALLOWED_TYPES = new Set([
  'create_room', 'join_room', 'find_match', 'cancel_search',
  'room_joined', 'ready_state',
  'match_settings', 'match_start', 'player_name',
  'blind_entered', 'blind_finished', 'game_over', 'life_lost', 'match_finished',
  'request_state', 'boss_sync', 'rematch_vote',
  'return_to_lobby', 'leave_lobby', 'return_to_menu',
  'ping',
  'sabotage', 'taunt',
  'set_location',
  'ready_blind', 'unready_blind',
  'play_hand',
]);

function isIntInRange(v, min, max) {
  return typeof v === 'number' && Number.isFinite(v) && Number.isInteger(v) && v >= min && v <= max;
}

function isNonNegativeFinite(v) {
  return typeof v === 'number' && Number.isFinite(v) && v >= 0;
}

function isStringOfLength(v, max) {
  return typeof v === 'string' && v.length > 0 && v.length <= max;
}

function validateMessage(msg, byteLength) {
  if (byteLength > MAX_MESSAGE_BYTES)      return `oversized: ${byteLength} bytes`;
  if (!msg || typeof msg !== 'object')     return 'not an object';
  if (typeof msg.type !== 'string')        return 'missing type';
  if (!ALLOWED_TYPES.has(msg.type))        return `unknown type: ${msg.type}`;

  if (msg.type === 'join_room') {
    if (typeof msg.code !== 'string' || !/^[A-Z0-9]{4}$/.test(msg.code))
      return 'join_room: invalid code';
  }
  if (msg.type === 'blind_finished') {
    if (msg.score !== undefined && !isNonNegativeFinite(msg.score))
      return 'blind_finished: invalid score';
    if (typeof msg.score === 'number' && msg.score > VALID_SCORE_MAX)
      return `blind_finished: score too large`;
  }
  if (msg.type === 'blind_entered') {
    if (msg.ante  !== undefined && !isIntInRange(msg.ante, 1, VALID_ANTE_MAX))
      return `blind_entered: invalid ante`;
    if (msg.blind !== undefined && !isStringOfLength(msg.blind, 1))
      return 'blind_entered: invalid blind';
  }
  if (msg.type === 'match_start') {
    if (msg.seed !== undefined && typeof msg.seed !== 'string')
      return 'match_start: seed must be string';
    if (typeof msg.seed === 'string' && msg.seed.length > 64)
      return 'match_start: seed too long';
  }
  if (msg.type === 'match_settings' && msg.settings) {
    const s = msg.settings;
    if (s.starting_lives !== undefined && !isIntInRange(s.starting_lives, 1, VALID_LIVES_MAX))
      return `match_settings: invalid starting_lives`;
    if (s.mode !== undefined && !['attrition', 'vanilla', 'ruleset', 'showdown', 'faceoff'].includes(s.mode))
      return `match_settings: unknown mode`;
    if (s.pvp_start_round !== undefined && !isIntInRange(s.pvp_start_round, 1, VALID_ANTE_MAX))
      return 'match_settings: invalid pvp_start_round';
    if (s.showdown_starting_antes !== undefined && !isIntInRange(s.showdown_starting_antes, 1, VALID_ANTE_MAX))
      return 'match_settings: invalid showdown_starting_antes';
    if (s.ante_timer !== undefined && typeof s.ante_timer !== 'boolean')
      return 'match_settings: ante_timer must be boolean';
    if (s.ante_timer_base !== undefined && !isIntInRange(s.ante_timer_base, 10, 3600))
      return 'match_settings: invalid ante_timer_base';
  }
  if (msg.type === 'play_hand') {
    if (msg.score !== undefined) {
      const sc = (typeof msg.score === 'number') ? msg.score : parseFloat(msg.score);
      if (!Number.isFinite(sc) || sc < 0 || sc > VALID_SCORE_MAX)
        return 'play_hand: invalid score';
    }
    if (msg.hands_left !== undefined) {
      const h = (typeof msg.hands_left === 'number') ? msg.hands_left : parseInt(msg.hands_left);
      if (!Number.isFinite(h) || h < 0 || h > 100)
        return 'play_hand: invalid hands_left';
    }
  }
  if (msg.type === 'player_name') {
    if (msg.name !== undefined && !isStringOfLength(msg.name, 32))
      return 'player_name: invalid name';
  }
  if ((msg.type === 'room_joined' || msg.type === 'ready_state') && msg.mp_version !== undefined) {
    if (typeof msg.mp_version !== 'number' || msg.mp_version !== SERVER_PROTOCOL_VERSION) {
      return `protocol_version_mismatch: server=${SERVER_PROTOCOL_VERSION} client=${msg.mp_version}`;
    }
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

  return null;
}


function createRateLimiter() {
  return { msgCount: 0, msgWindowStart: Date.now(), createCount: 0, createWindowStart: Date.now() };
}

function isRateLimited(rl, isCreate) {
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


function destroyRoom(code, reason) {
  const room = rooms[code];
  if (!room) return;
  clearPvpTimer(room);
  sendToRoom(room, { type: 'room_expired', reason: reason || 'inactive' });
  delete rooms[code];
  log('INFO', 'CLEANUP', `Room ${code} destroyed: ${reason || 'inactive'}`);
}

const roomCleanupInterval = setInterval(() => {
  const now = Date.now();
  for (const code of Object.keys(rooms)) {
    if (now - rooms[code].lastActivity > ROOM_TTL_MS) destroyRoom(code, 'ttl_expired');
  }
}, ROOM_CLEANUP_INTERVAL_MS);


function cleanupSocket(socket) {
  queue = queue.filter(s => s !== socket);
  const code = socket.roomCode;
  if (!code || !rooms[code]) return;

  const room  = rooms[code];
  const pid   = getPlayerId(room, socket);

  if (room.match && room.match.phase !== 'finished') {
    const oppId = pid === 0 ? 1 : 0;
    if (room.match.currentAnte < 2) {
      room.match.phase     = 'finished';
      room.match.winReason = 'disconnect_cancelled';
      log('INFO', 'DISCONNECT', `P${pid} left before Ante 2 � match cancelled`);
      room.sockets.forEach(s => {
        if (s !== socket && s.readyState === 1)
          sendTo(s, { type: 'match_cancelled', reason: 'opponent_disconnected_early' });
      });
    } else {
      room.match.winner    = oppId;
      room.match.winReason = 'opponent_disconnected';
      room.match.phase     = 'finished';
      log('INFO', 'DISCONNECT', `P${pid} left after Ante 2. Winner: P${oppId}`);
      room.sockets.forEach(s => {
        if (s !== socket && s.readyState === 1) {
          sendTo(s, { type: 'opponent_disconnected' });
          if (room.match) broadcastMatchState(room);
        }
      });
    }
  } else {
    room.sockets.forEach(s => {
      if (s !== socket && s.readyState === 1) {
        sendTo(s, { type: 'opponent_disconnected' });
        if (room.match) broadcastMatchState(room);
      }
    });
  }

  clearPvpTimer(room);
  delete rooms[code];
}


function handleCreateRoom(socket) {
  let code = generateCode();
  while (rooms[code]) code = generateCode();
  const room = createRoom(code);
  room.sockets.push(socket);
  rooms[code] = room;
  socket.roomCode = code;
  sendTo(socket, { type: 'room_created', code });
  log('INFO', 'ROOM', `Created ${code}`);
}

function handleJoinRoom(socket, msg) {
  const code = (msg.code || '').toUpperCase();
  const room = rooms[code];
  if (!room || room.sockets.length !== 1) {
    sendTo(socket, { type: 'room_error', reason: 'invalid_code' });
    return;
  }
  room.sockets.push(socket);
  socket.roomCode = code;
  touchRoom(room);
  sendTo(room.sockets[0], { type: 'room_ready', code, host: true });
  sendTo(room.sockets[1], { type: 'room_ready', code, host: false });
  log('INFO', 'ROOM', `Joined ${code}`);
}

function handleFindMatch(socket) {
  queue = queue.filter(s => s.readyState === 1);
  if (queue.length > 0) {
    const opp = queue.shift();
    let code = generateCode();
    while (rooms[code]) code = generateCode();
    const room = createRoom(code);
    room.sockets = [opp, socket];
    rooms[code]  = room;
    socket.roomCode = code;
    opp.roomCode    = code;
    sendTo(room.sockets[0], { type: 'room_ready', code, host: true });
    sendTo(room.sockets[1], { type: 'room_ready', code, host: false });
    log('INFO', 'MATCH', `Quick match ${code}`);
  } else {
    queue.push(socket);
    sendTo(socket, { type: 'searching' });
  }
}

function handleCancelSearch(socket) {
  queue = queue.filter(s => s !== socket);
  sendTo(socket, { type: 'search_cancelled' });
}

function handleRoomJoined(socket, msg) {
  const room = rooms[socket.roomCode];
  if (!room) return;
  const opp = getOpponentSocket(room, socket);
  if (!opp) return;
  const safe = { ...msg };
  delete safe.host;
  delete safe.code;
  sendTo(opp, safe);
}
function handleReadyState(socket, msg) {
  const room = rooms[socket.roomCode];
  if (!room) return;
  const opp = getOpponentSocket(room, socket);
  if (!opp) return;
  const safe = { ...msg };
  delete safe.host;
  delete safe.code;
  sendTo(opp, safe);
}

function handleMatchSettings(socket, msg, raw) {
  const room = rooms[socket.roomCode];
  if (!room) return;
  if (msg.settings) Object.assign(room.settings, msg.settings);
  touchRoom(room);
  relay(socket, raw);
}

function handleMatchStart(socket, msg, raw) {
  const room = rooms[socket.roomCode];
  if (!room || room.sockets.length !== 2) return;

  const match = createMatchState(room.settings);
  match.phase       = 'playing';
  match.seed        = msg.seed || null;

  if (match.mode === 'vanilla') match.seed2 = (msg.seed || '') + '_P2';

  const pid = getPlayerId(room, socket);
  if (pid >= 0 && msg.player_name) match.players[pid].name = msg.player_name;

  room.match = match;
  touchRoom(room);
  log('INFO', 'MATCH', `Started ${room.code}: mode=${match.mode} lives=${match.startingLives} seed=${match.seed}`);

  if (match.mode === 'vanilla') {
    const opp = getOpponentSocket(room, socket);
    if (opp) { const m2 = JSON.parse(JSON.stringify(msg)); m2.seed = match.seed2; sendTo(opp, m2); }
  } else {
    relay(socket, raw);
  }
  broadcastMatchState(room, { event: 'match_started' });
}

function handlePlayerName(socket, msg) {
  const room = rooms[socket.roomCode];
  if (!room || !room.match) return;
  const pid = getPlayerId(room, socket);
  if (pid >= 0) room.match.players[pid].name = msg.name || ('Player ' + (pid + 1));
}

function handleBlindEntered(socket, msg, raw) {
  const room = rooms[socket.roomCode];
  if (!room || !room.match || room.match.phase === 'finished') return;
  const m = room.match;

  const newAnte  = msg.ante  || m.currentAnte;
  const newBlind = msg.blind || m.currentBlind;

  if (newAnte === m.currentAnte && newBlind === m.currentBlind && m.phase !== 'lobby') {
    log('DEBUG', 'BLIND', `Duplicate blind_entered ignored ante=${newAnte} blind=${newBlind} room=${room.code}`);
    relay(socket, raw);
    return;
  }

  m.currentAnte  = newAnte;
  m.currentBlind = newBlind;
  m.isPvpBlind   = isBlindPvp(m, m.currentAnte, m.currentBlind);

  m.blindReady = [false, false];
  m.blindReadyAt = [0, 0];

  if (m.isPvpBlind) {
    m.phase = 'pvp_pending';
    m.players[0].blindFinished = false; m.players[0].score = null;
    m.players[1].blindFinished = false; m.players[1].score = null;
  }

  touchRoom(room);
  log('INFO', 'BLIND', `Ante ${m.currentAnte} ${m.currentBlind} PvP=${m.isPvpBlind} room=${room.code}`);
  broadcastMatchState(room, { event: 'blind_entered' });
  relay(socket, raw);
}

function handleBlindFinished(socket, msg) {
  const room = rooms[socket.roomCode];
  if (!room || !room.match) return;
  const m   = room.match;
  const pid = getPlayerId(room, socket);
  if (pid < 0) return;

  if (msg.ante !== undefined && Number(msg.ante) !== Number(m.currentAnte)) {
    log('DEBUG', 'SCORE', `P${pid} blind_finished stale ante=${msg.ante} vs current=${m.currentAnte}, ignored`);
    return;
  }
  if (msg.blind !== undefined && msg.blind !== m.currentBlind) {
    log('DEBUG', 'SCORE', `P${pid} blind_finished stale blind=${msg.blind} vs current=${m.currentBlind}, ignored`);
    return;
  }

  m.players[pid].score        = msg.score || 0;
  m.players[pid].blindFinished = true;
  touchRoom(room);
  log('INFO', 'SCORE', `P${pid} score=${m.players[pid].score} ante=${m.currentAnte} pvp=${m.isPvpBlind}`);

  const opp = getOpponentSocket(room, socket);
  if (opp) {
    sendTo(opp, {
      type: 'opponent_blind_finished',
      ante: m.currentAnte, blind: m.currentBlind, finished: true,
      lives: m.players[pid].lives,
      score: m.isPvpBlind ? null : (msg.score || 0),
    });
  }

  broadcastMatchState(room, { event: 'score_submitted' });
  if (m.isPvpBlind && m.players[0].blindFinished && m.players[1].blindFinished) resolvePvp(room);
}

function handleGameOver(socket, msg, raw) {
  const room = rooms[socket.roomCode];
  if (!room || !room.match || room.match.phase === 'finished') return;
  const m   = room.match;
  const pid = getPlayerId(room, socket);
  if (pid < 0) return;

  if (m.isPvpBlind) {
    m.players[pid].score        = 0;
    m.players[pid].blindFinished = true;
    log('INFO', 'GAME_OVER', `P${pid} failed PvP blind room=${room.code}`);
    if (m.players[0].blindFinished && m.players[1].blindFinished) resolvePvp(room);
  }
  relay(socket, raw);
}

function handleLifeLost(socket, msg, raw) {
  const room = rooms[socket.roomCode];
  if (!room || !room.match || room.match.phase === 'finished') return;
  const m   = room.match;
  const pid = getPlayerId(room, socket);
  if (pid < 0) return;

  const cur     = m.players[pid].lives;
  const claimed = Number(msg && msg.lives);
  let accepted  = false;

  if (!m.isPvpBlind
      && Number.isFinite(claimed)
      && Number.isInteger(claimed)
      && claimed >= 0
      && claimed === cur - 1) {
    m.players[pid].lives = claimed;
    accepted = true;
    log('INFO', 'LIFE_LOST', `P${pid} non-PvP life decrement accepted: ${cur} -> ${claimed} room=${room.code}`);

    if (m.players[pid].lives <= 0 && m.phase !== 'finished') {
      m.players[pid].status = 'eliminated';
      m.winner    = pid === 0 ? 1 : 0;
      m.winReason = 'opponent_eliminated';
      m.phase     = 'finished';
      log('INFO', 'MATCH', `P${pid} eliminated (non-PvP). Winner: P${m.winner} room=${room.code}`);
    }
  } else {
    log('WARN', 'LIFE_LOST', `P${pid} life_lost rejected: claimed=${claimed} cur=${cur} pvp=${m.isPvpBlind} room=${room.code}`);
  }

  touchRoom(room);
  broadcastMatchState(room, { event: 'life_lost', accepted });
}

function handleMatchFinished(socket, msg, raw) {
  const room = rooms[socket.roomCode];
  if (!room || !room.match) return;
  const m     = room.match;
  const pid   = getPlayerId(room, socket);
  if (pid < 0) return;
  const oppId = pid === 0 ? 1 : 0;

  if (m.phase !== 'finished') {
    if (msg.result === 'win')        { m.winner = pid; }
    else if (msg.result === 'lose')  { m.winner = oppId; m.players[pid].status = 'eliminated'; }
    m.winReason = msg.reason || m.winReason || 'match_finished';
    m.phase     = 'finished';
    touchRoom(room);
    log('INFO', 'MATCH', `Finished ${room.code}: P${pid} ${msg.result} (${m.winReason}) winner=P${m.winner}`);
    broadcastMatchState(room, { event: 'match_finished' });
    room.gameHistory.push({
      gameNumber: room.gameHistory.length + 1,
      winner: m.winner, winReason: m.winReason, pvpResults: m.pvpResults,
      p0Lives: m.players[0].lives, p1Lives: m.players[1].lives,
      p0Name: m.players[0].name,   p1Name: m.players[1].name,
      mode: m.mode, seed: m.seed, timestamp: Date.now(),
    });
    log('DEBUG', 'HISTORY', `Game ${room.gameHistory.length} recorded for ${room.code}`);
  }
  relay(socket, raw);
}

function handleRequestState(socket) {
  const room = rooms[socket.roomCode];
  if (room && room.match) broadcastMatchState(room, { event: 'state_sync' });
}

function handleRematchVote(socket) {
  const room = rooms[socket.roomCode];
  if (!room) return;
  const pid = getPlayerId(room, socket);
  if (pid < 0) return;

  if (!room.match || room.match.phase !== 'finished') {
    log('WARN', 'REMATCH', `P${pid} rematch_vote rejected — match not finished (phase=${room.match && room.match.phase})`);
    return;
  }

  if (!room.rematchVotes) room.rematchVotes = [false, false];
  room.rematchVotes[pid] = true;
  touchRoom(room);
  log('INFO', 'REMATCH', `P${pid} voted in ${room.code}`);

  const opp = getOpponentSocket(room, socket);
  if (opp) sendTo(opp, { type: 'rematch_vote' });

  if (room.rematchVotes[0] && room.rematchVotes[1]) {
    const newSeed = Date.now().toString(36).toUpperCase() + Math.random().toString(36).substring(2, 6).toUpperCase();
    log('INFO', 'REMATCH', `Both voted � new game seed=${newSeed} room=${room.code}`);
    const match = createMatchState(room.settings);
    match.phase        = 'playing';
    match.seed         = newSeed;
    if (room.match) {
      match.players[0].name = room.match.players[0].name;
      match.players[1].name = room.match.players[1].name;
    }
    room.match        = match;
    room.rematchVotes = [false, false];
    room.inLobby      = [false, false];
    if (room.gameHistory && room.gameHistory.length > MAX_GAME_HISTORY) {
      room.gameHistory = room.gameHistory.slice(-MAX_GAME_HISTORY);
    }
    sendToRoom(room, { type: 'rematch_accepted', seed: newSeed, settings: room.settings, gameHistory: room.gameHistory });
    broadcastMatchState(room, { event: 'rematch_started' });
  }
}

function handleReturnToLobby(socket) {
  const room = rooms[socket.roomCode];
  if (!room) return;
  const pid = getPlayerId(room, socket);
  log('INFO', 'LOBBY', `P${pid} returned to lobby in ${room.code}`);
  touchRoom(room);
  clearPvpTimer(room);

  if (!room.inLobby) room.inLobby = [false, false];
  room.inLobby[pid] = true;

  if (room.match) {
    const names = [room.match.players[0].name, room.match.players[1].name];
    room.match          = createMatchState(room.settings);
    room.match.phase    = 'lobby';
    room.match.players[0].name = names[0];
    room.match.players[1].name = names[1];
  }
  room.rematchVotes = [false, false];
  const opp = getOpponentSocket(room, socket);
  if (opp) sendTo(opp, { type: 'opponent_returned_to_lobby', gameHistory: room.gameHistory });
}

function handleLeaveLobby(socket) {
  const room = rooms[socket.roomCode];
  if (!room) return;
  const pid       = getPlayerId(room, socket);
  const postMatch = room.match && room.match.phase === 'finished';
  log('INFO', 'LEAVE', `P${pid} left lobby in ${room.code}`);
  clearPvpTimer(room);

  if (room.match && room.match.phase !== 'finished' && room.match.phase !== 'lobby') {
    const oppId = pid === 0 ? 1 : 0;
    room.match.winner    = oppId;
    room.match.winReason = 'opponent_quit';
    room.match.phase     = 'finished';
  }
  const opp = getOpponentSocket(room, socket);
  if (opp) {
    sendTo(opp, { type: 'opponent_left', post_match: postMatch });
    if (room.match) broadcastMatchState(room, { event: 'opponent_left' });
  }
  delete rooms[socket.roomCode];
  socket.roomCode = null;
}

function handleSabotage(socket, msg, raw) { safeRelay(socket, msg, raw); }
function handleTaunt(socket, msg, raw)    { safeRelay(socket, msg, raw); }

function handlePlayHand(socket, msg) {
  const room = rooms[socket.roomCode];
  if (!room || !room.match) return;
  const opp = getOpponentSocket(room, socket);
  const pid = getPlayerId(room, socket);
  if (pid >= 0 && room.match.players[pid] && !room.match.players[pid].blindFinished) {
    room.match.players[pid].score = parseFloat(msg.score) || 0;
  }
  extendPvpTimeoutOnActivity(room);
  if (opp) {
    sendTo(opp, {
      type: 'enemy_info',
      score: parseFloat(msg.score) || 0,
      hands_left: (typeof msg.hands_left === 'number') ? msg.hands_left
                : (parseInt(msg.hands_left) || 0),
      lives: pid >= 0 ? room.match.players[pid].lives : undefined,
    });
  }

  const handsLeft = (typeof msg.hands_left === 'number') ? msg.hands_left
                  : (parseInt(msg.hands_left) || 0);
  const m = room.match;
  if (handsLeft === 0 && pid >= 0 && m.isPvpBlind && m.phase === 'pvp_pending') {

    if (!m.players[pid].blindFinished) {
      m.players[pid].blindFinished = true;
      touchRoom(room);
      log('INFO', 'PVP', `P${pid} blind_finished (via play_hand) score=${m.players[pid].score}`);
      if (m.players[0].blindFinished && m.players[1].blindFinished) {
        resolvePvp(room);
      }
    }
  }
}

function handleReadyBlind(socket) {
  const room = rooms[socket.roomCode];
  if (!room || !room.match) return;
  const m = room.match;
  const pid = getPlayerId(room, socket);
  if (pid < 0) return;

  if (m.phase !== 'pvp_pending' || !m.isPvpBlind) {
    log('DEBUG', 'PVP', `P${pid} ready_blind rejected — phase=${m.phase} isPvp=${m.isPvpBlind}`);
    sendTo(socket, { type: 'ready_blind_rejected', reason: 'phase_mismatch' });
    return;
  }

  if (!m.blindReady) m.blindReady = [false, false];
  if (!m.blindReadyAt) m.blindReadyAt = [0, 0];

  const nowReady = Date.now();
  if (m.blindReady[pid] && m.blindReadyAt[pid] && (nowReady - m.blindReadyAt[pid]) < READY_UNREADY_DEBOUNCE_MS) {
    log('DEBUG', 'PVP', `Ignored fast duplicate ready from P${pid} in ${room.code}`);
    return;
  }

  m.blindReady[pid] = true;
  m.blindReadyAt[pid] = nowReady;
  touchRoom(room);
  log('INFO', 'PVP', `P${pid} ready for blind in ${room.code}`);

  const opp = getOpponentSocket(room, socket);
  if (opp) sendTo(opp, { type: 'opponent_ready_blind' });

  if (m.blindReady[0] && m.blindReady[1]) {
    m.blindReady = [false, false];
    m.blindReadyAt = [0, 0];
    log('INFO', 'PVP', `Both ready — sending start_blind in ${room.code}`);
    schedulePvpTimeout(room);
    sendToRoom(room, { type: 'start_blind' });
  }
}

function handleUnreadyBlind(socket) {
  const room = rooms[socket.roomCode];
  if (!room || !room.match) return;
  const m = room.match;
  const pid = getPlayerId(room, socket);
  if (pid < 0) return;

  if (!m.blindReady) m.blindReady = [false, false];
  if (!m.blindReadyAt) m.blindReadyAt = [0, 0];

  const now = Date.now();
  if (m.blindReady[pid] && m.blindReadyAt[pid] && (now - m.blindReadyAt[pid]) < READY_UNREADY_DEBOUNCE_MS) {
    log('DEBUG', 'PVP', `Ignored fast unready from P${pid} in ${room.code}`);
    return;
  }

  m.blindReady[pid] = false;
  m.blindReadyAt[pid] = 0;
  touchRoom(room);
  log('INFO', 'PVP', `P${pid} unready for blind in ${room.code}`);

  const opp = getOpponentSocket(room, socket);
  if (opp) sendTo(opp, { type: 'opponent_unready_blind' });
}

function handleReturnToMenu(socket) {
  const room = rooms[socket.roomCode];
  if (!room) return;
  const pid = getPlayerId(room, socket);
  log('INFO', 'MENU', `P${pid} returned to menu in ${room.code}`);
  clearPvpTimer(room);

  if (room.match && room.match.phase !== 'finished') {
    const oppId = pid === 0 ? 1 : 0;
    room.match.winner    = oppId;
    room.match.winReason = 'opponent_quit';
    room.match.phase     = 'finished';
  }
  const opp = getOpponentSocket(room, socket);
  if (opp) {
    sendTo(opp, { type: 'opponent_returned_to_menu' });
    if (room.match) broadcastMatchState(room, { event: 'opponent_quit' });
  }
  delete rooms[socket.roomCode];
  socket.roomCode = null;
}

const HANDLERS = {
  create_room:     handleCreateRoom,
  join_room:       handleJoinRoom,
  find_match:      handleFindMatch,
  cancel_search:   handleCancelSearch,
  room_joined:     handleRoomJoined,
  ready_state:     handleReadyState,
  match_settings:  handleMatchSettings,
  match_start:     handleMatchStart,
  player_name:     handlePlayerName,
  ping:            (socket) => sendTo(socket, { type: 'pong' }),
  blind_entered:   handleBlindEntered,
  blind_finished:  handleBlindFinished,
  game_over:       handleGameOver,
  life_lost:       handleLifeLost,
  match_finished:  handleMatchFinished,
  request_state:   handleRequestState,
  boss_sync:       (socket, _msg, raw) => relay(socket, raw),
  sabotage:        handleSabotage,
  taunt:           handleTaunt,
  rematch_vote:    handleRematchVote,
  ready_blind:     handleReadyBlind,
  unready_blind:   handleUnreadyBlind,
  play_hand:       handlePlayHand,
  return_to_lobby: handleReturnToLobby,
  leave_lobby:     handleLeaveLobby,
  return_to_menu:  handleReturnToMenu,
};


wss.on('connection', (socket) => {
  socket.isAlive = true;
  socket.rl      = createRateLimiter();

  socket.on('pong', () => { socket.isAlive = true; });

  socket.on('message', (raw) => {
    socket.isAlive = true;

    const byteLength = Buffer.byteLength(raw);
    let msg;
    try { msg = JSON.parse(raw); } catch {
      log('WARN', 'MSG', `Malformed JSON (${byteLength} bytes)`);
      return;
    }

    const validationError = validateMessage(msg, byteLength);
    if (validationError) {
      log('WARN', 'VALIDATE', `Rejected ${msg && msg.type}: ${validationError}`);
      sendTo(socket, { type: 'error', reason: validationError });
      return;
    }

    const isCreate = msg.type === 'create_room' || msg.type === 'find_match';
    if (isRateLimited(socket.rl, isCreate)) {
      log('WARN', 'RATELIMIT', `Socket over quota on type=${msg.type}`);
      sendTo(socket, { type: 'error', reason: 'rate_limited' });
      return;
    }

    const handler = HANDLERS[msg.type];
    if (handler) handler(socket, msg, raw);
    else safeRelay(socket, msg, raw);
  });

  socket.on('close', () => cleanupSocket(socket));
  socket.on('error', (err) => {
    log('ERROR', 'SOCKET', `Error: ${err.message}`);
    cleanupSocket(socket);
  });
});

const heartbeatInterval = setInterval(() => {
  wss.clients.forEach(socket => {
    const inActiveMatch = socket.roomCode
      && rooms[socket.roomCode]
      && rooms[socket.roomCode].match
      && rooms[socket.roomCode].match.phase !== 'lobby'
      && rooms[socket.roomCode].match.phase !== 'finished';
    if (!socket.isAlive) {
      if (!inActiveMatch && !socket.lobbyIdleStrike) {
        socket.lobbyIdleStrike = true;
        socket.ping();
        return;
      }
      log('WARN', 'HEARTBEAT', `Terminating unresponsive socket (room=${socket.roomCode || 'none'})`);
      return socket.terminate();
    }
    socket.lobbyIdleStrike = false;
    socket.isAlive = false;
    socket.ping();
  });
}, 30000);

wss.on('close', () => {
  clearInterval(heartbeatInterval);
  clearInterval(roomCleanupInterval);
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
  log('INFO', 'SERVER', `Balatro MP server on 0.0.0.0:${PORT} [AUTHORITATIVE][Stage 1]`);
});

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { createMatchState, isBlindPvp, createRoom, generateCode, validateMessage, isRateLimited, server, wss };
}
