// ARCH: Server unit tests using Node built-in test runner (node:test)
// Run: node --test server.test.js
// Run: npm test

const { describe, it, after } = require('node:test');
const assert = require('node:assert/strict');

// server.js starts listening on require — use a unique port to avoid conflicts
process.env.PORT = '0';  // port 0 = OS picks a free port
const { createMatchState, isBlindPvp, createRoom, generateCode, validateMessage, isRateLimited, server, wss } = require('./server.js');

// Close the HTTP + WS servers after all tests so the process exits cleanly
after(() => { wss.close(); server.close(); });

// ============================================
// createMatchState
// ============================================
describe('createMatchState', () => {
  it('returns default state with no settings', () => {
    const m = createMatchState();
    assert.equal(m.phase, 'lobby');
    assert.equal(m.mode, 'attrition');
    assert.equal(m.startingLives, 4);
    assert.equal(m.players[0].lives, 4);
    assert.equal(m.players[1].lives, 4);
    assert.equal(m.currentAnte, 1);
    assert.equal(m.currentBlind, 'S');
    assert.equal(m.winner, null);
    assert.equal(m.anteTimer, false);
  });

  it('respects custom settings', () => {
    const m = createMatchState({ starting_lives: 2, mode: 'vanilla', ante_timer: true, ante_timer_base: 60 });
    assert.equal(m.startingLives, 2);
    assert.equal(m.mode, 'vanilla');
    assert.equal(m.players[0].lives, 2);
    assert.equal(m.anteTimer, true);
    assert.equal(m.anteTimerBase, 60);
  });

  it('defaults ante_timer_base to 120', () => {
    const m = createMatchState({});
    assert.equal(m.anteTimerBase, 120);
  });
});

// ============================================
// isBlindPvp
// ============================================
describe('isBlindPvp', () => {
  it('returns false in vanilla mode always', () => {
    const m = createMatchState({ mode: 'vanilla' });
    assert.equal(isBlindPvp(m, 5, 'L'), false);
    assert.equal(isBlindPvp(m, 10, 'L'), false);
  });

  it('returns true for attrition L blind after pvpStartAnte', () => {
    const m = createMatchState({ mode: 'attrition' });
    m.pvpStartAnte = 1;
    assert.equal(isBlindPvp(m, 2, 'L'), true);
    assert.equal(isBlindPvp(m, 1, 'L'), false);  // not > pvpStartAnte
  });

  it('returns false for non-L blinds in attrition', () => {
    const m = createMatchState({ mode: 'attrition' });
    assert.equal(isBlindPvp(m, 5, 'S'), false);
    assert.equal(isBlindPvp(m, 5, 'B'), false);
  });

  it('handles showdown mode', () => {
    const m = createMatchState({ mode: 'showdown' });
    assert.equal(isBlindPvp(m, 3, 'S'), true);   // ante > 2
    assert.equal(isBlindPvp(m, 2, 'L'), false);   // ante not > 2
  });
});

// ============================================
// createRoom
// ============================================
describe('createRoom', () => {
  it('creates room with expected structure', () => {
    const r = createRoom('ABCD');
    assert.equal(r.code, 'ABCD');
    assert.ok(Array.isArray(r.sockets));
    assert.equal(r.sockets.length, 0);
    assert.equal(r.match, null);
    assert.deepEqual(r.settings, { mode: 'attrition', starting_lives: 4 });
    assert.ok(Array.isArray(r.gameHistory));
  });
});

// ============================================
// generateCode
// ============================================
describe('generateCode', () => {
  it('returns a 4-character string', () => {
    const code = generateCode();
    assert.equal(typeof code, 'string');
    assert.equal(code.length, 4);
  });

  it('uses only allowed characters', () => {
    const allowed = /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]+$/;
    for (let i = 0; i < 50; i++) {
      assert.match(generateCode(), allowed);
    }
  });

  it('generates different codes (probabilistic)', () => {
    const codes = new Set(Array.from({ length: 20 }, () => generateCode()));
    assert.ok(codes.size > 1, 'Expected at least 2 unique codes out of 20');
  });
});

// ============================================
// validateMessage — Stage 1 input validation
// ============================================
describe('validateMessage', () => {
  it('accepts a valid create_room message', () => {
    assert.equal(validateMessage({ type: 'create_room' }, 20), null);
  });

  it('rejects oversized messages', () => {
    const err = validateMessage({ type: 'create_room' }, 5000);
    assert.ok(err && err.includes('oversized'), `expected oversized error, got: ${err}`);
  });

  it('rejects unknown type', () => {
    const err = validateMessage({ type: 'hack_room' }, 20);
    assert.ok(err && err.includes('unknown type'), `expected unknown type error, got: ${err}`);
  });

  it('rejects missing type', () => {
    const err = validateMessage({ action: 'create_room' }, 30);
    assert.ok(err && err.includes('missing type'), `expected missing type error, got: ${err}`);
  });

  it('rejects invalid join_room code', () => {
    const err = validateMessage({ type: 'join_room', code: '!@#$' }, 30);
    assert.ok(err && err.includes('join_room'), `expected join_room error, got: ${err}`);
  });

  it('accepts valid join_room', () => {
    assert.equal(validateMessage({ type: 'join_room', code: 'AB3Z' }, 30), null);
  });

  it('rejects blind_finished with negative score', () => {
    const err = validateMessage({ type: 'blind_finished', score: -1 }, 40);
    assert.ok(err && err.includes('blind_finished'), `expected score error, got: ${err}`);
  });

  it('rejects blind_finished with absurdly large score', () => {
    const err = validateMessage({ type: 'blind_finished', score: 2e15 }, 40);
    assert.ok(err && err.includes('score too large'), `expected score too large error, got: ${err}`);
  });

  it('accepts valid blind_finished', () => {
    assert.equal(validateMessage({ type: 'blind_finished', score: 1000000 }, 50), null);
  });

  it('rejects match_settings with invalid mode', () => {
    const err = validateMessage({ type: 'match_settings', settings: { mode: 'godmode' } }, 60);
    assert.ok(err && err.includes('mode'), `expected mode error, got: ${err}`);
  });

  // Stage 4: sabotage + taunt relay validation
  it('accepts valid sabotage', () => {
    assert.equal(validateMessage({ type: 'sabotage', sabotage_id: 'sleep' }, 40), null);
  });

  it('rejects sabotage with oversized sabotage_id', () => {
    const err = validateMessage({ type: 'sabotage', sabotage_id: 'x'.repeat(65) }, 80);
    assert.ok(err && err.includes('sabotage'), `expected sabotage error, got: ${err}`);
  });

  it('accepts valid taunt', () => {
    assert.equal(validateMessage({ type: 'taunt', title: 'GG' }, 30), null);
  });

  it('rejects taunt with oversized title', () => {
    const err = validateMessage({ type: 'taunt', title: 'x'.repeat(65) }, 80);
    assert.ok(err && err.includes('taunt'), `expected taunt error, got: ${err}`);
  });
});

// ============================================
// isRateLimited — Stage 1 rate limiting
// ============================================
describe('isRateLimited', () => {
  it('allows messages under the per-second limit', () => {
    const rl = { msgCount: 0, msgWindowStart: Date.now(), createCount: 0, createWindowStart: Date.now() };
    for (let i = 0; i < 10; i++) assert.equal(isRateLimited(rl, false), false);
  });

  it('blocks messages exceeding 60/s', () => {
    const rl = { msgCount: 60, msgWindowStart: Date.now() - 100, createCount: 0, createWindowStart: Date.now() };
    assert.equal(isRateLimited(rl, false), true);
  });

  it('resets msg counter after 1 second window', () => {
    const rl = { msgCount: 60, msgWindowStart: Date.now() - 1500, createCount: 0, createWindowStart: Date.now() };
    assert.equal(isRateLimited(rl, false), false);
  });

  it('blocks create_room exceeding 5/min', () => {
    const rl = { msgCount: 0, msgWindowStart: Date.now(), createCount: 5, createWindowStart: Date.now() - 100 };
    assert.equal(isRateLimited(rl, true), true);
  });
});
