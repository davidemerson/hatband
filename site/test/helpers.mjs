import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

export const vectorFile = JSON.parse(readFileSync(new URL('../../spec/vectors/cards.json', import.meta.url), 'utf8'));
export const vectors = vectorFile.vectors;
export const vector = (name) => {
  const v = vectors.find((x) => x.name === name);
  assert.ok(v, `vector ${name}`);
  return v;
};

/** Hex with optional spaces to bytes. */
export function h(hex) {
  const clean = hex.replace(/\s+/g, '');
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  return out;
}

export const u8 = (...bytes) => Uint8Array.from(bytes);
export const repeat = (byte, n) => new Uint8Array(n).fill(byte);

/** Asserts `fn` throws an error of `cls` with `code`, and any extra fields. */
export function throwsCode(fn, cls, code, extra) {
  assert.throws(fn, (error) => {
    assert.ok(error instanceof cls, `expected ${cls.name}, got ${error && error.name}: ${error && error.message}`);
    assert.equal(error.code, code);
    if (extra) for (const [k, v] of Object.entries(extra)) assert.deepEqual(error[k], v);
    return true;
  });
}
