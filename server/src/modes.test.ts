import { describe, it, expect } from 'bun:test';
import { partyTrapTarget, trapRival } from './party';

function fake(kind: string, teams: number[], extra: Record<string, unknown> = {}): any {
  return {
    settings: { party_kind: kind },
    seats: teams.map((t, i) => ({ team: t, alive: true, lives: 3, best: i * 100 })),
    teamLives: [3, 3, 3, 3], raidLives: 3, ...extra,
  };
}

describe('traps only reach the other side', () => {
  it('drops every trap in a co-op raid', () => {
    const p = fake('raid', [0, 0, 0]);
    expect(partyTrapTarget(p, 0, 1, 'trap_set')).toBeNull();
    expect(partyTrapTarget(p, 0, undefined, 'trap_set')).toBeNull();
    expect(partyTrapTarget(p, 1, 0, 'trap_fire')).toBeNull();
  });
  it('sends a team trap to the other team, even when a teammate was asked', () => {
    const p = fake('teams', [0, 0, 1, 1]);
    expect(trapRival(p, 0, 1)).toBe(false);
    expect(trapRival(p, 0, 2)).toBe(true);
    expect(partyTrapTarget(p, 0, 2, 'trap_set')).toBe(2);
    expect(partyTrapTarget(p, 0, 1, 'trap_set')).toBe(3);
    expect(partyTrapTarget(p, 0, undefined, 'trap_set')).toBe(3);
    expect(partyTrapTarget(p, 2, 3, 'trap_fire')).toBeNull();
  });
  it('aims traps at a human, never at a bot that cannot react', () => {
    const p = fake('br', [0, 0, 0, 0]);
    p.seats[3].ws = { data: { bot: true } };
    expect(partyTrapTarget(p, 0, 3, 'trap_set')).toBe(2);
    expect(partyTrapTarget(p, 0, undefined, 'trap_set')).toBe(2);
    expect(partyTrapTarget(p, 3, 0, 'trap_fire')).toBe(0);
    p.seats[1].ws = { data: { bot: true } };
    p.seats[2].ws = { data: { bot: true } };
    expect(partyTrapTarget(p, 0, undefined, 'trap_set')).toBeNull();
  });
  it('leaves Battle Royale targeting as it was', () => {
    const p = fake('br', [0, 0, 0]);
    expect(partyTrapTarget(p, 0, 1, 'trap_set')).toBe(1);
    expect(partyTrapTarget(p, 0, undefined, 'trap_set')).toBe(2);
  });
});
