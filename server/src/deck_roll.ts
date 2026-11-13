export const RANDOM_DECK = 'random_pick';
export const DECK_POOL_MAX = 80;

export function cleanDeckPool(raw: unknown): string[] | undefined {
  if (!Array.isArray(raw)) return undefined;
  const out: string[] = [];
  for (const v of raw) {
    if (typeof v !== 'string' || v.length === 0 || v.length > 40 || v === RANDOM_DECK) continue;
    if (!out.includes(v)) out.push(v);
    if (out.length >= DECK_POOL_MAX) break;
  }
  return out;
}

export function rollDeck(settings: Record<string, unknown>, rnd: () => number = Math.random): string | null {
  if (settings.deck !== RANDOM_DECK) {
    delete settings.rolled_deck;
    return null;
  }
  const pool = cleanDeckPool(settings.deck_pool) ?? [];
  if (pool.length === 0) return null;
  const pick = pool[Math.min(pool.length - 1, Math.floor(rnd() * pool.length))];
  settings.rolled_deck = pick;
  return pick;
}
