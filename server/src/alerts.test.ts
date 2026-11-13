import { expect, test } from 'bun:test';
import { shouldAlert } from './alerts';

test('same error alerts once per window, new ones still go through', () => {
  const t = 1_000_000_000;
  expect(shouldAlert('a', t).send).toBe(true);
  expect(shouldAlert('a', t + 1000).send).toBe(false);
  expect(shouldAlert('b', t + 1000).send).toBe(true);
  const r = shouldAlert('a', t + 11 * 60 * 1000);
  expect(r.send).toBe(true);
  expect(r.skipped).toBe(1);
});
