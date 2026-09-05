/* Decoding parity with Packages/HatbandCore: the accept/reject catalogues
   of CBORAdversarialTests, Base32AdversarialTests and HB1Tests, the
   invariant that every accepted input re-encodes to itself, and mutation
   fuzz over the published vectors. Codes are the Swift error cases. */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  Base32Error, CBORError, CardError, HBError, HB1Error, HB1_MAX_BYTES, HB1_MAX_FRAGMENT, HB1_URL_PREFIX, CBOR_MAX_DEPTH,
  base32Decode, base32Encode, cardFromMap, cborDecode, cborEncode, hb1DecodeCBOR, hb1DecodeURL, hb1Fragment, hb1URL, hexEncode,
  isSigned, signingBytes, verifySignature,
} from '../src/hb1.js';
import { h, repeat, throwsCode, vectors } from './helpers.mjs';
import {
  BASE32_ALPHABET, Gen, SplitMix64, boundaries, canonicalBase32, inflateHead, referenceBase32Decode, referenceBase32Encode, validRemainders,
} from './review-helpers.mjs';

const hex = (bytes) => hexEncode(bytes);
const bytesEqual = (a, b) => hex(a) === hex(b);
const cbor = (hexText) => throwsOr(() => cborDecode(h(hexText)));
const throwsOr = (fn) => { try { return { value: fn() }; } catch (error) { return { error }; } };

/** The invariant every input must satisfy: rejected with a CBORError, or
    decoded to a value whose re-encoding is exactly the input. */
function canonicalOrRejected(bytes) {
  const r = throwsOr(() => cborDecode(bytes));
  if (r.error) return r.error instanceof CBORError;
  return bytesEqual(cborEncode(r.value), bytes);
}

const rejects = (hexText, code, extra) => throwsCode(() => cborDecode(h(hexText)), CBORError, code, extra);
const unsupported = (major, info) => ({ major, info });

// MARK: - Map key ordering (§4.2.1)

const rfcKeys = [[10, '0a'], [100, '1864'], [-1, '20'], ['z', '617a'], ['aa', '626161'], [[100], '811864'], [[-1], '8120'], [false, 'f4']];

test('RFC 8949 example keys encode in bytewise order and the RFC 7049 order is rejected', () => {
  const map = new Map(rfcKeys.map(([key], i) => [key, i]));
  const expected = 'a8' + rfcKeys.map(([, enc], i) => enc + '0' + i).join('');
  assert.equal(hex(cborEncode(map)), expected);
  assert.equal(cborDecode(h(expected)).size, 8);
  rejects('a8 0a00 2002 f407 186401 617a03 812006 62616104 81186405', 'mapKeysNotOrdered');
  for (let i = 0; i < rfcKeys.length; i++) {
    for (let j = i + 1; j < rfcKeys.length; j++) {
      const [a, b] = [rfcKeys[i][1], rfcKeys[j][1]];
      assert.equal(cborDecode(h(`a2 ${a} 00 ${b} 00`)).size, 2);
      rejects(`a2 ${b} 00 ${a} 00`, 'mapKeysNotOrdered');
    }
  }
});

test('mixed-type keys sort purely by encoded bytes', () => {
  const keys = [
    null, true, false, new Map([[0, 0]]), new Map(), [0], [], 'ÿ', 'a', '', Uint8Array.of(0xff), Uint8Array.of(0), new Uint8Array(0),
    -(1n << 64n), -25, -24, -1, 2 ** 32, 65536, 256, 255, 24, 23, 0,
  ];
  const encoded = cborEncode(new Map(keys.map((k) => [k, null])));
  const order = keys.map((k) => hex(cborEncode(k))).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  // Hex sorts like bytes only when lengths agree; compare through the encoder's own order instead.
  const expectedOrder = [...new Map(keys.map((k) => [k, null]))].map(([k]) => cborEncode(k)).sort((a, b) => {
    const n = Math.min(a.length, b.length);
    for (let i = 0; i < n; i++) if (a[i] !== b[i]) return a[i] - b[i];
    return a.length - b.length;
  }).map(hex);
  assert.equal(hex(encoded), 'b818' + expectedOrder.map((k) => k + 'f6').join(''));
  assert.equal(expectedOrder.length, order.length);
  assert.equal(expectedOrder[0], '00');
  assert.equal(expectedOrder[6], '1b0000000100000000');
  assert.equal(expectedOrder[7], '20');
  assert.equal(expectedOrder[10], '3bffffffffffffffff');
  assert.equal(expectedOrder[11], '40');
  assert.equal(expectedOrder[13], '41ff');
  assert.equal(expectedOrder[14], '60');
  assert.equal(expectedOrder[16], '62c3bf');
  assert.equal(expectedOrder[17], '80');
  assert.equal(expectedOrder[19], 'a0');
  assert.equal(expectedOrder[23], 'f6');
  const decoded = cborDecode(encoded);
  assert.equal(decoded.size, 24);
  assert.equal(hex(cborEncode(decoded)), hex(encoded));
});

test('ordered pairs are accepted and re-encode; unordered, duplicate and nested-unordered pairs are rejected', () => {
  for (const enc of [
    'a2 00 00 20 00', 'a2 1864 00 20 00', 'a2 1bffffffffffffffff 00 20 00', 'a2 18ff 00 190100 00', 'a2 37 00 3818 00',
    'a2 41ff 00 60 00', 'a2 4161 00 6161 00', 'a2 6162 00 626161 00', 'a2 617a 00 626161 00', 'a2 811864 00 8120 00',
    'a2 8120 00 a0 00', 'a2 a0 00 f4 00', 'a2 f4 00 f6 00',
  ]) {
    assert.equal(cborDecode(h(enc)).size, 2, enc);
    assert.ok(bytesEqual(cborEncode(cborDecode(h(enc))), h(enc)), enc);
  }
  for (const enc of [
    'a2 20 00 00 00', 'a2 20 00 1864 00', 'a2 190100 00 18ff 00', 'a2 3818 00 37 00', 'a2 60 00 41ff 00', 'a2 6161 00 4161 00',
    'a2 626161 00 6162 00', 'a2 626161 00 617a 00', 'a2 80 00 60 00', 'a2 a0 00 80 00', 'a2 f4 00 a0 00', 'a2 f6 00 f5 00',
    'a2 f5 00 f4 00', 'a2 8120 00 811864 00', 'a2 a0 00 8120 00',
    'a2 00 00 00 01', 'a2 6161 00 6161 01', 'a2 40 00 40 01', 'a2 80 00 80 01', 'a2 a0 00 a0 01', 'a2 f6 00 f6 01',
    'a3 00 00 01 00 01 00', 'a3 00 00 01 00 00 00',
    'a1 00 a2 01 00 00 00', '81 a2 01 00 00 00', 'a1 a2 01 00 00 00 00', '82 00 a2 00 00 00 01',
  ]) rejects(enc, 'mapKeysNotOrdered');
});

test('look-alike keys are distinct; NFC and NFD text keys both survive', () => {
  const map = new Map([[Uint8Array.of(0x61), 1], ['a', 2], [0, 3], [-1, 4], [[], 5], [new Map(), 6], [false, 7], [null, 8]]);
  const decoded = cborDecode(cborEncode(map));
  assert.equal(decoded.size, 8);
  assert.equal(decoded.get('a'), 2);
  assert.equal(decoded.get(0), 3);
  assert.equal(decoded.get(-1), 4);
  assert.equal(decoded.get(false), 7);
  assert.equal(decoded.get(null), 8);
  const encoded = h('a2 62c3a9 00 6365cc81 01');
  assert.ok(canonicalOrRejected(encoded));
  for (const wrapped of [encoded, Uint8Array.from([0x81, ...encoded]), Uint8Array.from([0xa1, 0x00, ...encoded])]) {
    const value = cborDecode(wrapped);
    assert.ok(bytesEqual(cborEncode(value), wrapped));
    let inner = value;
    if (Array.isArray(inner)) inner = inner[0];
    if (inner instanceof Map && inner.has(0)) inner = inner.get(0);
    assert.equal(inner.size, 2);
    assert.equal(inner.get('é'), 0);
    assert.equal(inner.get('é'), 1);
  }
});

test('rotating a sorted map by one entry always breaks the order', () => {
  let checked = 0;
  for (const value of Gen.values(600, 7)) {
    if (!(value instanceof Map) || value.size < 2) continue;
    const entries = [...value].map(([k, v]) => [cborEncode(k), cborEncode(v)]).sort((a, b) => (hex(a[0]) < hex(b[0]) ? -1 : 1));
    const encoded = cborEncode(value);
    const bodyLength = entries.reduce((n, [k, v]) => n + k.length + v.length, 0);
    const head = encoded.subarray(0, encoded.length - bodyLength);
    const rotated = [...entries.slice(1), entries[0]].flatMap(([k, v]) => [...k, ...v]);
    throwsCode(() => cborDecode(Uint8Array.from([...head, ...rotated])), CBORError, 'mapKeysNotOrdered');
    checked++;
  }
  assert.ok(checked > 30);
});

// MARK: - Integer boundaries

test('integers use the shortest head at every width and reject a widened one', () => {
  const widths = [[0n, 1], [23n, 1], [24n, 2], [255n, 2], [256n, 3], [65535n, 3], [65536n, 5], [0xffffffffn, 5], [0x100000000n, 9], [(1n << 63n) - 1n, 9], [(1n << 64n) - 1n, 9]];
  for (const [value, width] of widths) {
    for (const v of [value, -1n - value]) {
      const encoded = cborEncode(v);
      assert.equal(encoded.length, width, String(v));
      assert.equal(encoded[0] >> 5, v < 0n ? 1 : 0);
      assert.equal(BigInt(cborDecode(encoded)), v);
      const inflated = inflateHead(encoded, 0);
      if (inflated) throwsCode(() => cborDecode(inflated), CBORError, 'notShortestForm');
    }
  }
  for (const [enc, value] of [
    ['1a ffffffff', 0xffffffffn], ['1b 0000000100000000', 0x100000000n], ['1b 7fffffffffffffff', (1n << 63n) - 1n],
    ['1b 8000000000000000', 1n << 63n], ['1b ffffffffffffffff', (1n << 64n) - 1n],
    ['3a ffffffff', -(1n << 32n)], ['3b 0000000100000000', -(1n << 32n) - 1n], ['3b 7fffffffffffffff', -(1n << 63n)],
    ['3b 8000000000000000', -(1n << 63n) - 1n], ['3b ffffffffffffffff', -(1n << 64n)],
  ]) {
    assert.equal(BigInt(cborDecode(h(enc))), value, enc);
    assert.equal(hex(cborEncode(value)), hex(h(enc)), enc);
  }
  for (const enc of ['18 00', '18 17', '19 0000', '19 0018', '19 00ff', '1a 00000000', '1a 0000ffff', '1b 0000000000000000', '1b 00000000ffffffff',
    '38 00', '38 17', '39 00ff', '3a 0000ffff', '3b 00000000ffffffff']) rejects(enc, 'notShortestForm');
  // Where JavaScript switches from number to BigInt is invisible on the wire.
  assert.equal(typeof cborDecode(h('1b 001fffffffffffff')), 'number');
  assert.equal(typeof cborDecode(h('1b 0020000000000000')), 'bigint');
  assert.equal(typeof cborDecode(h('3b 001ffffffffffffe')), 'number');
  assert.equal(typeof cborDecode(h('3b 001fffffffffffff')), 'bigint');
  assert.equal(cborDecode(h('3b 001fffffffffffff')), -(1n << 53n));
  assert.equal(hex(cborEncode(-(2 ** 53 - 1))), '3b001ffffffffffffe');
});

test('length arguments obey the shortest-form rule before the remaining-input bound', () => {
  for (const enc of [
    '58 00', '58 17 ' + '00 '.repeat(23), '59 0018 ' + '00 '.repeat(24), '5a 000000ff ' + '00 '.repeat(255), '5b 0000000000000000',
    '78 00', '78 01 61', '79 0001 61', '7b 0000000000000001 61',
    '98 00', '98 01 00', '99 0001 00', '9a 00000001 00', '9b 0000000000000001 00',
    'b8 00', 'b8 01 00 00', 'b9 0001 00 00', 'ba 00000001 00 00', 'bb 0000000000000001 00 00',
    '9b 00000000ffffffff', '5b 00000000ffffffff', 'ba 0000ffff',
  ]) rejects(enc, 'notShortestForm');
});

test('strings, arrays and maps at every width boundary round-trip and reject a widened head', () => {
  for (const n of [0, 1, 23, 24, 255, 256, 65535, 65536]) {
    const values = [repeat(0xab, n), 'a'.repeat(n), new Array(n).fill(null), new Map(Array.from({ length: n }, (_, i) => [i, null]))];
    for (const value of values) {
      const encoded = cborEncode(value);
      assert.ok(bytesEqual(cborEncode(cborDecode(encoded)), encoded));
      const inflated = inflateHead(encoded, 0);
      if (inflated) throwsCode(() => cborDecode(inflated), CBORError, 'notShortestForm');
    }
    const width = n < 24 ? 1 : n < 256 ? 2 : n < 65536 ? 3 : 5;
    for (const value of values.slice(0, 3)) assert.equal(cborEncode(value).length, width + n);
  }
});

// MARK: - Text strings and UTF-8

test('invalid UTF-8 is rejected at the top level and nested; valid UTF-8 at every width round-trips', () => {
  for (const enc of [
    '61 80', '61 c0', '62 c0 80', '62 c1 bf', '63 e0 80 80', '63 e0 9f bf', '64 f0 80 80 80', '64 f0 8f bf bf', '63 ed a0 80', '63 ed bf bf',
    '66 ed a0 bd ed b2 a9', '64 f4 90 80 80', '64 f5 80 80 80', '65 f8 88 80 80 80', '61 fe', '61 ff', '62 e2 82', '63 e2 82 41', '62 c3 28',
    '63 e2 28 a1', '64 f0 90 28 bc', '64 f0 28 8c bc', '62 61 ff', '63 ef bf ff',
    '81 61 ff', 'a1 61 ff 00', 'a1 00 61 ff', '82 00 82 00 61 ff', 'a1 81 61 ff 00',
  ]) rejects(enc, 'invalidUTF8');
  for (const [enc, text] of [
    ['61 00', ' '], ['61 7f', ''], ['62 c2 80', ''], ['62 df bf', '߿'], ['63 e0 a0 80', 'ࠀ'], ['63 ed 9f bf', '퟿'],
    ['63 ee 80 80', ''], ['63 ef bf bd', '�'], ['63 ef bf be', '￾'], ['63 ef bf bf', '￿'], ['63 ef b7 90', '﷐'],
    ['63 ef b7 af', '﷯'], ['63 ef bb bf', '﻿'], ['64 f0 90 80 80', '\u{10000}'], ['64 f4 8f bf be', '\u{10fffe}'],
    ['64 f4 8f bf bf', '\u{10ffff}'], ['64 f0 9f 98 80', '\u{1f600}'], ['62 0d 0a', '\r\n'], ['66 65 cc 81 e2 80 8d', 'é‍'],
  ]) {
    assert.equal(cborDecode(h(enc)), text, enc);
    assert.equal(hex(cborEncode(text)), hex(h(enc)), enc);
  }
  assert.equal(hex(cborEncode('水ü𐅑')), '69e6b0b4c3bcf0908591');
  assert.equal(hex(cborEncode('é')), '62c3a9');
  assert.equal(hex(cborEncode('é')), '6365cc81');
  assert.ok(cborDecode(h('49e6b0b4c3bcf0908591')) instanceof Uint8Array);
});

// MARK: - Well-formedness (§3, Appendix F)

test('end of input in a head, short data, unclosed containers', () => {
  for (const [enc, code, extra] of [
    ['18', 'truncated'], ['19', 'truncated'], ['1a', 'truncated'], ['1b', 'truncated'], ['19 01', 'truncated'], ['1a 01 02', 'truncated'],
    ['1b 01 02 03 04 05 06 07', 'truncated'], ['38', 'truncated'], ['58', 'truncated'], ['78', 'truncated'], ['98', 'truncated'],
    ['9a 01 ff 00', 'truncated'], ['b8', 'truncated'],
    ['d8', 'unsupported', unsupported(6, 24)], ['f8', 'unsupported', unsupported(7, 24)], ['f9 00', 'unsupported', unsupported(7, 25)],
    ['fa 00 00', 'unsupported', unsupported(7, 26)], ['fb 00 00 00', 'unsupported', unsupported(7, 27)],
    ['41', 'truncated'], ['61', 'truncated'], ['5a ff ff ff ff 00', 'truncated'], ['5b ff ff ff ff ff ff ff ff 01 02 03', 'truncated'],
    ['7a ff ff ff ff 00', 'truncated'], ['7b 7f ff ff ff ff ff ff ff 01 02 03', 'truncated'],
    ['81', 'truncated'], ['81 81 81 81 81 81 81 81 81 81', 'truncated'], ['82 00', 'truncated'], ['a1', 'truncated'], ['a2 01 02', 'truncated'],
    ['a1 00', 'truncated'], ['a2 00 00 00', 'truncated'], ['a2 00 00 01', 'truncated'], ['a1 81', 'truncated'], ['a1 00 81', 'truncated'],
    ['', 'truncated'],
  ]) rejects(enc, code, extra);
});

test('reserved additional information, simple values, breaks and info 31', () => {
  for (const initial of [0x1c, 0x1d, 0x1e, 0x3c, 0x3d, 0x3e, 0x5c, 0x5d, 0x5e, 0x7c, 0x7d, 0x7e, 0x9c, 0x9d, 0x9e, 0xbc, 0xbd, 0xbe, 0xdc, 0xdd, 0xde, 0xfc, 0xfd, 0xfe]) {
    const extra = unsupported(initial >> 5, initial & 0x1f);
    throwsCode(() => cborDecode(Uint8Array.of(initial)), CBORError, 'unsupported', extra);
    throwsCode(() => cborDecode(Uint8Array.of(initial, 0, 0, 0, 0, 0, 0, 0, 0)), CBORError, 'unsupported', extra);
    throwsCode(() => cborDecode(Uint8Array.of(0x81, initial)), CBORError, 'unsupported', extra);
  }
  for (const enc of ['f8 00', 'f8 01', 'f8 14', 'f8 15', 'f8 16', 'f8 18', 'f8 1f', 'f8 20', 'f8 ff']) rejects(enc, 'unsupported', unsupported(7, 24));
  for (const initial of [...Array.from({ length: 20 }, (_, i) => 0xe0 | i), 0xf7]) {
    throwsCode(() => cborDecode(Uint8Array.of(initial)), CBORError, 'unsupported', unsupported(7, initial & 0x1f));
  }
  for (const [enc, code, extra] of [
    ['ff', 'unsupported', unsupported(7, 31)], ['81 ff', 'unsupported', unsupported(7, 31)], ['82 00 ff', 'unsupported', unsupported(7, 31)],
    ['a1 ff', 'truncated'], ['a1 ff 00', 'unsupported', unsupported(7, 31)], ['a1 00 ff', 'unsupported', unsupported(7, 31)], ['a2 00 00 ff', 'truncated'],
    ['1f', 'indefiniteLength'], ['3f', 'indefiniteLength'], ['df', 'unsupported', unsupported(6, 31)],
  ]) rejects(enc, code, extra);
});

test('every indefinite-length form and every unsupported Appendix A item is rejected', () => {
  for (const enc of [
    '5f 42 01 02 43 03 04 05 ff', '7f 65 73 74 72 65 61 64 6d 69 6e 67 ff', '9f ff', '9f 01 82 02 03 9f 04 05 ff ff', '9f 01 82 02 03 82 04 05 ff',
    '83 01 82 02 03 9f 04 05 ff', '83 01 9f 02 03 ff 82 04 05',
    '9f 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10 11 12 13 14 15 16 17 18 18 18 19 ff',
    'bf 61 61 01 61 62 9f 02 03 ff ff', '82 61 61 bf 61 62 61 63 ff', 'bf 63 46 75 6e f5 63 41 6d 74 21 ff',
    '5f 41 00', '7f 61 00', '9f', '9f 01 02', 'bf', 'bf 01 02 01 02', '81 9f', '9f 80 00', '5f 00 ff', '5f 21 ff', '5f 5f 41 00 ff ff', 'bf 00 ff',
    'a1 00 9f ff', 'a1 9f ff 00',
  ]) rejects(enc, 'indefiniteLength');
  for (const [enc, major, info] of [
    ['c2 49 01 00 00 00 00 00 00 00 00', 6, 2], ['c3 49 01 00 00 00 00 00 00 00 00', 6, 3],
    ['c0 74 32 30 31 33 2d 30 33 2d 32 31 54 32 30 3a 30 34 3a 30 30 5a', 6, 0], ['c1 1a 51 4b 67 b0', 6, 1], ['c1 fb 41 d4 52 d9 ec 20 00 00', 6, 1],
    ['d7 44 01 02 03 04', 6, 23], ['d8 18 45 64 49 45 54 46', 6, 24], ['d8 20 76 68 74 74 70 3a 2f 2f 77 77 77 2e 65 78 61 6d 70 6c 65 2e 63 6f 6d', 6, 24],
    ['d9 d9 f7 00', 6, 25], ['f9 00 00', 7, 25], ['f9 80 00', 7, 25], ['f9 3c 00', 7, 25], ['f9 7c 00', 7, 25], ['f9 7e 00', 7, 25], ['f9 fc 00', 7, 25],
    ['fa 47 c3 50 00', 7, 26], ['fa 7f 80 00 00', 7, 26], ['fa 7f c0 00 00', 7, 26], ['fb 3f f1 99 99 99 99 99 9a', 7, 27],
    ['fb 7f f0 00 00 00 00 00 00', 7, 27], ['fb 7f f8 00 00 00 00 00 00', 7, 27], ['f7', 7, 23], ['f0', 7, 16], ['f8 ff', 7, 24],
    ['c2 41 01', 6, 2], ['f8 f4', 7, 24], ['d8 18 41 00', 6, 24],
  ]) rejects(enc, 'unsupported', unsupported(major, info));
});

test('empty containers, nesting at and beyond the limit, hostile lengths, trailing bytes', () => {
  for (const enc of ['80', 'a0', '40', '60', '81 80', '81 a0', 'a1 80 a0', 'a1 a0 80', '82 80 80', 'a2 40 60 60 40', '82 40 60']) {
    assert.ok(bytesEqual(cborEncode(cborDecode(h(enc))), h(enc)), enc);
  }
  const depth = CBOR_MAX_DEPTH;
  assert.equal(depth, 32);
  const arrays = (n, leaf = [0x00]) => Uint8Array.from([...new Array(n).fill(0x81), ...leaf]);
  const maps = (n, leaf = [0x00]) => Uint8Array.from([...new Array(n).fill([0xa1, 0x00]).flat(), ...leaf]);
  assert.doesNotThrow(() => cborDecode(arrays(depth)));
  throwsCode(() => cborDecode(arrays(depth + 1)), CBORError, 'tooDeep');
  assert.doesNotThrow(() => cborDecode(maps(depth)));
  throwsCode(() => cborDecode(maps(depth + 1)), CBORError, 'tooDeep');
  const mixed = [];
  for (let i = 0; i < depth; i++) mixed.push(...(i % 2 === 0 ? [0x81] : [0xa1, 0x00]));
  assert.doesNotThrow(() => cborDecode(Uint8Array.from([...mixed, 0x00])));
  throwsCode(() => cborDecode(Uint8Array.from([...mixed, 0x81, 0x00])), CBORError, 'tooDeep');
  throwsCode(() => cborDecode(Uint8Array.from([...mixed, 0xa1, 0x00, 0x00])), CBORError, 'tooDeep');
  assert.doesNotThrow(() => cborDecode(Uint8Array.from([0xa1, ...arrays(depth - 1), 0x00])));
  throwsCode(() => cborDecode(Uint8Array.from([0xa1, ...arrays(depth), 0x00])), CBORError, 'tooDeep');
  const t0 = performance.now();
  throwsCode(() => cborDecode(new Uint8Array(1_000_000).fill(0x81)), CBORError, 'tooDeep');
  throwsCode(() => cborDecode(new Uint8Array(1_000_000).fill(0xa1)), CBORError, 'tooDeep');
  assert.ok(performance.now() - t0 < 500, 'deep nesting fails fast');
  const deepest = cborDecode(arrays(depth));
  assert.ok(bytesEqual(cborEncode(deepest), arrays(depth)));
  assert.ok(bytesEqual(cborEncode([deepest]), arrays(depth + 1)));
  throwsCode(() => cborDecode(cborEncode([deepest])), CBORError, 'tooDeep');
  for (const enc of [
    '9a ff ff ff ff', '9b 00 00 00 01 00 00 00 00', '9b ff ff ff ff ff ff ff ff', 'ba ff ff ff ff', 'bb 00 00 00 01 00 00 00 00', 'bb ff ff ff ff ff ff ff ff',
    '5a ff ff ff ff', '5b 00 00 00 01 00 00 00 00', '7a ff ff ff ff', '7b ff ff ff ff ff ff ff ff', '98 ff', '99 ff ff 00', 'b8 ff 00 00', 'b9 ff ff 00 00',
    'a3 00 00 01 01', 'a2 00 00 01', '83 00 01', '58 20 00', '81 9a ff ff ff ff', 'a1 00 ba ff ff ff ff', 'a1 9a ff ff ff ff 00', 'a5 00 00 01 01 02',
  ]) rejects(enc, 'truncated');
  assert.equal(cborDecode(h('a2 00 00 01 01')).size, 2);
  for (const enc of ['00 00', '00 ff', '80 00', 'a0 00', '40 00', '60 00', 'f6 f6', '81 00 00', 'a1 00 00 00', '1b ff ff ff ff ff ff ff ff 00',
    '44 01 02 03 04 05', '63 e6 b0 b4 00', '80 ff']) rejects(enc, 'trailingBytes');
});

test('every initial byte alone: exactly the one-byte values decode, everything else fails as Swift does', () => {
  for (let initial = 0; initial < 256; initial++) {
    const major = initial >> 5;
    const info = initial & 0x1f;
    const bytes = Uint8Array.of(initial);
    const r = throwsOr(() => cborDecode(bytes));
    const label = initial.toString(16);
    if (major === 0 && info < 24) assert.equal(r.value, info, label);
    else if (major === 1 && info < 24) assert.equal(r.value, -1 - info, label);
    else if (major === 2 && info === 0) assert.deepEqual(r.value, new Uint8Array(0), label);
    else if (major === 3 && info === 0) assert.equal(r.value, '', label);
    else if (major === 4 && info === 0) assert.deepEqual(r.value, [], label);
    else if (major === 5 && info === 0) assert.deepEqual(r.value, new Map(), label);
    else if (major === 7 && info === 20) assert.equal(r.value, false, label);
    else if (major === 7 && info === 21) assert.equal(r.value, true, label);
    else if (major === 7 && info === 22) assert.equal(r.value, null, label);
    else if (major <= 5 && info >= 24 && info <= 27) assert.equal(r.error && r.error.code, 'truncated', label);
    else if (major >= 2 && major <= 5 && info >= 1 && info < 24) assert.equal(r.error && r.error.code, 'truncated', label);
    else if (major <= 5 && info === 31) assert.equal(r.error && r.error.code, 'indefiniteLength', label);
    else {
      assert.equal(r.error && r.error.code, 'unsupported', label);
      assert.deepEqual([r.error.major, r.error.info], [major, info], label);
    }
    assert.ok(canonicalOrRejected(bytes), label);
  }
});

// MARK: - Non-canonical inputs a lenient decoder would repair

test('well-formed non-canonical inputs are rejected, their canonical spellings accepted', () => {
  for (const [enc, code, canonical] of [
    ['18 01', 'notShortestForm', '01'], ['19 00 01', 'notShortestForm', '01'], ['1a 00 00 00 01', 'notShortestForm', '01'],
    ['1b 00 00 00 00 00 00 00 01', 'notShortestForm', '01'], ['38 00', 'notShortestForm', '20'], ['58 01 00', 'notShortestForm', '41 00'],
    ['78 01 61', 'notShortestForm', '61 61'], ['98 02 00 01', 'notShortestForm', '82 00 01'], ['b8 01 00 00', 'notShortestForm', 'a1 00 00'],
    ['82 00 18 01', 'notShortestForm', '82 00 01'], ['a1 18 01 00', 'notShortestForm', 'a1 01 00'], ['a1 00 18 01', 'notShortestForm', 'a1 00 01'],
    ['a2 01 00 00 00', 'mapKeysNotOrdered', 'a2 00 00 01 00'], ['a2 20 00 18 64 00', 'mapKeysNotOrdered', 'a2 18 64 00 20 00'],
    ['a2 62 61 61 00 61 7a 00', 'mapKeysNotOrdered', 'a2 61 7a 00 62 61 61 00'], ['a2 81 20 00 81 18 64 00', 'mapKeysNotOrdered', 'a2 81 18 64 00 81 20 00'],
    ['a2 f4 00 0a 00', 'mapKeysNotOrdered', 'a2 0a 00 f4 00'], ['a2 00 00 00 01', 'mapKeysNotOrdered', 'a1 00 01'],
    ['9f 00 01 ff', 'indefiniteLength', '82 00 01'], ['bf 00 01 ff', 'indefiniteLength', 'a1 00 01'], ['5f 41 01 41 02 ff', 'indefiniteLength', '42 01 02'],
    ['7f 61 61 61 62 ff', 'indefiniteLength', '62 61 62'],
  ]) {
    rejects(enc, code);
    assert.ok(canonicalOrRejected(h(enc)), enc);
    assert.ok(bytesEqual(cborEncode(cborDecode(h(canonical))), h(canonical)), canonical);
  }
});

test('widening any head in a generated encoding is caught at the top level and nested', () => {
  let checked = 0;
  for (const value of Gen.values(1500, 11)) {
    const encoded = cborEncode(value);
    const inflated = inflateHead(encoded, 0);
    if (!inflated) continue;
    const expected = encoded[0] >> 5 === 7 ? ['unsupported', unsupported(7, 24)] : ['notShortestForm'];
    for (const wrapped of [inflated, Uint8Array.from([0x81, ...inflated]), Uint8Array.from([0xa1, 0x00, ...inflated]), Uint8Array.from([0xa1, ...inflated, 0x00])]) {
      throwsCode(() => cborDecode(wrapped), CBORError, ...expected);
    }
    checked++;
  }
  assert.ok(checked > 1000);
});

// MARK: - Properties over generated values

test('generated values round-trip; random and mutated bytes are canonical or rejected', () => {
  for (const value of Gen.values(5000, 1)) {
    const encoded = cborEncode(value);
    assert.ok(bytesEqual(cborEncode(cborDecode(encoded)), encoded), hex(encoded));
  }
  const rng = new SplitMix64(5);
  let accepted = 0;
  for (let i = 0; i < 40000; i++) {
    const bytes = Gen.fuzz(rng);
    assert.ok(canonicalOrRejected(bytes), hex(bytes));
    if (!throwsOr(() => cborDecode(bytes)).error) accepted++;
  }
  assert.ok(accepted > 100);
  const mutate = new SplitMix64(9);
  for (const value of Gen.values(3000, 13)) {
    const encoded = cborEncode(value);
    const i = mutate.below(encoded.length);
    const flipped = Uint8Array.from(encoded); flipped[i] ^= 1 << mutate.below(8);
    const replaced = Uint8Array.from(encoded); replaced[i] = mutate.byte();
    const inserted = Uint8Array.from([...encoded.subarray(0, i), mutate.byte(), ...encoded.subarray(i)]);
    const deleted = Uint8Array.from([...encoded.subarray(0, i), ...encoded.subarray(i + 1)]);
    for (const mutant of [flipped, replaced, inserted, deleted]) assert.ok(canonicalOrRejected(mutant), `${hex(encoded)} -> ${hex(mutant)}`);
  }
});

test('every proper prefix is exactly truncated; every extension is exactly trailing bytes', () => {
  for (const value of Gen.values(400, 17)) {
    const encoded = cborEncode(value);
    for (let cut = 0; cut < encoded.length; cut++) throwsCode(() => cborDecode(encoded.subarray(0, cut)), CBORError, 'truncated');
  }
  const rng = new SplitMix64(19);
  for (const value of Gen.values(1000, 23)) {
    const encoded = cborEncode(value);
    throwsCode(() => cborDecode(Uint8Array.from([...encoded, 0xff])), CBORError, 'trailingBytes');
    const tail = Gen.fuzz(rng);
    if (tail.length) throwsCode(() => cborDecode(Uint8Array.from([...encoded, ...tail])), CBORError, 'trailingBytes');
  }
});

test('structures at the depth limit round-trip and one more container is rejected', () => {
  const rng = new SplitMix64(29);
  for (let i = 0; i < 50; i++) {
    let value = Gen.value(0, rng);
    for (let d = 0; d < CBOR_MAX_DEPTH; d++) value = (rng.next() & 1n) === 0n ? [value] : new Map([[Gen.value(0, rng), value]]);
    const encoded = cborEncode(value);
    assert.ok(bytesEqual(cborEncode(cborDecode(encoded)), encoded));
    throwsCode(() => cborDecode(cborEncode([value])), CBORError, 'tooDeep');
  }
  const widths = new SplitMix64(31);
  for (let i = 0; i < 5000; i++) {
    const v = Gen.integer(widths);
    const width = v < 24n ? 1 : v <= 0xffn ? 2 : v <= 0xffffn ? 3 : v <= 0xffffffffn ? 5 : 9;
    for (const value of [v, -1n - v]) {
      const encoded = cborEncode(value);
      assert.equal(encoded.length, width);
      assert.equal(BigInt(cborDecode(encoded)), value);
    }
  }
  assert.ok(boundaries.every((b) => cborEncode(b).length <= 9));
});

// MARK: - Base32 (RFC 4648 §6, §3.3, §3.5) against the prose oracle

const outcome = (text) => {
  try { return { bytes: base32Decode(text) }; } catch (error) {
    return error instanceof Base32Error ? { code: error.code } : { trap: error };
  }
};
const same = (a, b) => (a.code !== undefined ? a.code === b.code : b.bytes !== undefined && hex(a.bytes) === hex(b.bytes));

test('Base32 matches coreutils and RFC 4648 §10, padded and unpadded, either case', () => {
  for (const [bytes, padded] of [
    [[0, 0, 0, 0, 0], 'AAAAAAAA'], [[0xff, 0xff, 0xff, 0xff, 0xff], '77777777'], [[0xff, 0xff, 0xff, 0xff], '777777Y='], [[0x01], 'AE======'], [[0x80], 'QA======'],
    [Array.from({ length: 16 }, (_, i) => i), 'AAAQEAYEAUDAOCAJBIFQYDIOB4======'],
    [[...Buffer.from('The quick brown fox jumps over the lazy dog')], 'KRUGKIDROVUWG2ZAMJZG653OEBTG66BANJ2W24DTEBXXMZLSEB2GQZJANRQXU6JAMRXWO==='],
    [Array.from({ length: 256 }, (_, i) => i), 'AAAQEAYEAUDAOCAJBIFQYDIOB4IBCEQTCQKRMFYYDENBWHA5DYPSAIJCEMSCKJRHFAUSUKZMFUXC6MBRGIZTINJWG44DSOR3HQ6T4P2AIFBEGRCFIZDUQSKKJNGE2TSPKBIVEU2UKVLFOWCZLJNVYXK6L5QGCYTDMRSWMZ3INFVGW3DNNZXXA4LSON2HK5TXPB4XU634PV7H7AEBQKBYJBMGQ6EITCULRSGY5D4QSGJJHFEVS2LZRGM2TOOJ3HU7UCQ2FI5EUWTKPKFJVKV2ZLNOV6YLDMVTWS23NN5YXG5LXPF5X274BQOCYPCMLRWHZDE4VS6MZXHM7UGR2LJ5JVOW27MNTWW33TO55X7A4HROHZHF43T6R2PK5PWO33XP6DY7F47U6X3PP6HZ7L57Z7P674======'],
  ]) {
    const unpadded = padded.replace(/=+$/, '');
    assert.equal(base32Encode(Uint8Array.from(bytes)), unpadded);
    assert.equal(referenceBase32Encode(bytes), unpadded);
    assert.deepEqual(base32Decode(padded), Uint8Array.from(bytes));
    assert.deepEqual(base32Decode(unpadded), Uint8Array.from(bytes));
    assert.deepEqual(base32Decode(padded.toLowerCase()), Uint8Array.from(bytes));
  }
  for (const [plain, padded] of [['', ''], ['f', 'MY======'], ['fo', 'MZXQ===='], ['foo', 'MZXW6==='], ['foob', 'MZXW6YQ='], ['fooba', 'MZXW6YTB'], ['foobar', 'MZXW6YTBOI======']]) {
    assert.equal(padded.length % 8, 0);
    assert.deepEqual(base32Decode(padded), Uint8Array.from(Buffer.from(plain)));
    assert.deepEqual(base32Decode(padded.toLowerCase()), Uint8Array.from(Buffer.from(plain)));
    assert.equal(base32Encode(Buffer.from(plain)) + '='.repeat((padded.match(/=/g) || []).length), padded);
  }
});

test('Base32 round-trips every length through 100, bit patterns, and is the inverse of decode on canonical text', () => {
  const rng = new SplitMix64(0x4842312062617365n);
  for (let length = 0; length <= 100; length++) {
    for (let i = 0; i < 4; i++) {
      const bytes = rng.bytes(length);
      const text = base32Encode(bytes);
      assert.equal(text.length, Math.floor((length * 8 + 4) / 5));
      assert.equal(text, referenceBase32Encode(bytes));
      assert.deepEqual(base32Decode(text), bytes);
      assert.deepEqual(base32Decode(text.toLowerCase()), bytes);
      assert.ok(same(referenceBase32Decode(text), { bytes }));
    }
  }
  const patterns = [
    new Uint8Array(41).fill(0), new Uint8Array(41).fill(0xff),
    Uint8Array.from({ length: 41 }, (_, i) => (i % 2 === 0 ? 0x55 : 0xaa)), Uint8Array.from({ length: 41 }, (_, i) => (i % 2 === 0 ? 0xaa : 0x55)),
    Uint8Array.from({ length: 41 }, (_, i) => 1 << (i % 8)), Uint8Array.from({ length: 41 }, (_, i) => 0x80 >> (i % 8)),
  ];
  for (const bytes of patterns) {
    for (let length = 0; length <= bytes.length; length++) {
      const prefix = bytes.subarray(0, length);
      const text = base32Encode(prefix);
      assert.equal(text, referenceBase32Encode(prefix));
      assert.deepEqual(base32Decode(text), prefix);
    }
  }
  const inverse = new SplitMix64(7);
  for (let i = 0; i < 500; i++) {
    const text = base32Encode(inverse.bytes(inverse.below(81)));
    assert.equal(base32Encode(base32Decode(text)), text);
    assert.equal(base32Encode(base32Decode(text.toLowerCase())), text);
  }
});

test('Base32 alphabet is Table 3, every value in every position, output inside QR alphanumeric mode', () => {
  const qrAlphanumeric = new Set('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:');
  assert.equal(new Set(BASE32_ALPHABET).size, 32);
  assert.ok([...'0189'].every((c) => !BASE32_ALPHABET.includes(c)));
  for (let value = 0; value < 32; value++) assert.equal(base32Encode(Uint8Array.of(value << 3)), BASE32_ALPHABET[value] + 'A');
  const placing = (value, position, count) => { const s = new Array(count).fill('A'); s[position] = BASE32_ALPHABET[value]; return s.join(''); };
  const bytesPlacing = (value, position, count) => {
    const out = new Uint8Array(Math.floor(count * 5 / 8));
    for (let i = 0; i < 5; i++) {
      if (((value >> (4 - i)) & 1) === 0) continue;
      const bit = position * 5 + i;
      if (bit >> 3 < out.length) out[bit >> 3] |= 1 << (7 - (bit % 8));
    }
    return out;
  };
  for (let position = 0; position < 16; position++) {
    for (let value = 0; value < 32; value++) {
      const text = placing(value, position, 16);
      const expected = bytesPlacing(value, position, 16);
      assert.deepEqual(base32Decode(text), expected);
      assert.deepEqual(base32Decode(text.toLowerCase()), expected);
      assert.equal(base32Encode(expected), text);
      assert.equal(referenceBase32Encode(expected), text);
    }
  }
  const rng = new SplitMix64(3);
  const samples = [Uint8Array.from({ length: 256 }, (_, i) => i), new Uint8Array(0), Uint8Array.of(0), Uint8Array.of(0xff)];
  for (let i = 0; i < 200; i++) samples.push(rng.bytes(rng.below(301)));
  for (const bytes of samples) {
    const text = base32Encode(bytes);
    assert.equal(text, text.toUpperCase());
    assert.ok([...text].every((c) => BASE32_ALPHABET.includes(c) && qrAlphanumeric.has(c) && c.charCodeAt(0) < 0x80));
    assert.ok(!/\s/u.test(text));
  }
  // Fill bits (§3.5): every value that sets one is rejected; every other decodes to its whole bytes.
  for (const count of [2, 4, 5, 7]) {
    const fill = (count * 5) % 8;
    for (let value = 0; value < 32; value++) {
      const partial = placing(value, count - 1, count);
      const expected = bytesPlacing(value, count - 1, count);
      for (const prefix of ['', 'MZXW6YTB']) {
        const text = prefix + partial;
        const prefixBytes = Uint8Array.from(Buffer.from('fooba').subarray(0, Math.floor(prefix.length * 5 / 8)));
        if ((value & ((1 << fill) - 1)) === 0) {
          assert.deepEqual(base32Decode(text), Uint8Array.from([...prefixBytes, ...expected]), text);
          assert.deepEqual(base32Decode(text.toLowerCase()), Uint8Array.from([...prefixBytes, ...expected]), text);
          assert.equal(base32Encode(Uint8Array.from([...prefixBytes, ...expected])), text);
        } else {
          throwsCode(() => base32Decode(text), Base32Error, 'nonZeroPadding');
          throwsCode(() => base32Decode(text.toLowerCase()), Base32Error, 'nonZeroPadding');
        }
      }
    }
  }
  const seen = new Set();
  let accepted = 0;
  for (const first of BASE32_ALPHABET) {
    for (const second of BASE32_ALPHABET) {
      const r = outcome(first + second);
      if (!r.bytes) continue;
      accepted++;
      assert.equal(r.bytes.length, 1);
      assert.ok(!seen.has(r.bytes[0]), first + second);
      seen.add(r.bytes[0]);
    }
  }
  assert.equal(accepted, 256);
  assert.equal(seen.size, 256);
});

test('Base32 length rule, prefixes, padding tolerance, pad before the end, wrapped input, hostile scalars', () => {
  for (let count = 0; count <= 256; count++) {
    const text = 'A'.repeat(count);
    const expected = validRemainders.has(count % 8) ? { bytes: new Uint8Array(Math.floor(count * 5 / 8)) } : { code: 'invalidLength' };
    assert.ok(same(outcome(text), expected), `count ${count}`);
  }
  const rng = new SplitMix64(11);
  const bytes = rng.bytes(50);
  const text = base32Encode(bytes);
  for (let count = 0; count <= text.length; count++) {
    const prefix = text.slice(0, count);
    const r = outcome(prefix);
    assert.ok(same(r, referenceBase32Decode(prefix)), `count ${count}`);
    if (r.bytes) {
      assert.ok(validRemainders.has(count % 8));
      assert.deepEqual(r.bytes, bytes.subarray(0, Math.floor(count * 5 / 8)));
    } else if (r.code === 'invalidLength') assert.ok(!validRemainders.has(count % 8));
    else if (r.code === 'nonZeroPadding') assert.ok(validRemainders.has(count % 8) && count % 8 !== 0);
    else assert.fail(`prefix ${count}: ${JSON.stringify(r)}`);
  }
  const pads = new SplitMix64(5);
  for (let length = 0; length <= 25; length++) {
    const b = pads.bytes(length);
    const t = base32Encode(b);
    const n = (8 - (t.length % 8)) % 8;
    assert.equal(n, [0, 6, 4, 3, 1][length % 5]);
    assert.deepEqual(base32Decode(t + '='.repeat(n)), b);
    assert.deepEqual(base32Decode((t + '='.repeat(n)).toLowerCase()), b);
  }
  for (let n = 0; n <= 9; n++) {
    assert.deepEqual(base32Decode('MY' + '='.repeat(n)), Uint8Array.from(Buffer.from('f')));
    assert.deepEqual(base32Decode('MZXW6YTBOI' + '='.repeat(n)), Uint8Array.from(Buffer.from('foobar')));
    assert.deepEqual(base32Decode('='.repeat(n)), new Uint8Array(0));
  }
  assert.deepEqual(base32Decode('MY' + '='.repeat(1000)), Uint8Array.from(Buffer.from('f')));
  for (const t of ['=MY', 'M=Y', 'MY=MY', 'MY======MY', 'MZXW6=YTB', 'MZXW6===MZXW6===', 'MY======MZXQ====', 'MY======\n', 'MY====== ', 'MY=======A', 'MY=​']) {
    throwsCode(() => base32Decode(t), Base32Error, 'invalidCharacter');
  }
  for (const [t, code] of [['M=======', 'invalidLength'], ['MZX=====', 'invalidLength'], ['MZXW6Y==', 'invalidLength'], ['MZXW6YTBO=======', 'invalidLength'], ['A=', 'invalidLength'],
    ['MZ======', 'nonZeroPadding'], ['MZXW7===', 'nonZeroPadding'], ['777777Z=', 'nonZeroPadding'], ['MZXQ====MZXW7===', 'invalidCharacter'],
    ['M', 'invalidLength'], ['MZX', 'invalidLength'], ['MZXW6Y', 'invalidLength'], ['MY1', 'invalidCharacter'], ['M Y', 'invalidCharacter'], ['MY=A', 'invalidCharacter'],
    ['MZ', 'nonZeroPadding'], ['MZXW7', 'nonZeroPadding']]) throwsCode(() => base32Decode(t), Base32Error, code);
  for (const t of ['MZXW6YTB\r\nOI', 'MZXW6YTB\nOI', 'MZXW6YTB OI', 'MZXW6YTBOI\n', ' MZXW6YTBOI', 'MZXW6YTBOI\r', 'MZXW6YTÁ']) {
    throwsCode(() => base32Decode(t), Base32Error, 'invalidCharacter');
  }
  const hostile = ['0', '1', '8', '9', ' ', '\t', '\n', '\r', '', '', '\0', '', '-', '_', '+', '/', '.', ',', ':', '$', '%', '*',
    ' ', '​', '﻿', '́', 'é', 'ß', 'ı', 'İ', 'K', 'Ａ', '２', '٢', '\u{1d400}', '\u{1f600}', '�'];
  for (const scalar of hostile) {
    for (const [head, tail] of [['', 'MZXW6YTB'], ['MZXW', '6YTB'], ['MZXW6YTB', ''], ['MZXW6YTBOI', ''], ['', '']]) {
      throwsCode(() => base32Decode(head + scalar + tail), Base32Error, 'invalidCharacter');
    }
  }
  assert.deepEqual(base32Decode('OA'), Uint8Array.of(14 << 3));
  assert.deepEqual(base32Decode('iA'), Uint8Array.of(8 << 3));
  assert.deepEqual(base32Decode('lA'), Uint8Array.of(11 << 3));
  for (const t of ['0A', '1A', 'OAAAAAA0', 'IAAAAAA1']) throwsCode(() => base32Decode(t), Base32Error, 'invalidCharacter');
  const mixed = new SplitMix64(13);
  for (let i = 0; i < 200; i++) {
    const b = mixed.bytes(mixed.below(61));
    const upper = base32Encode(b);
    const mixedCase = [...upper].map((c, j) => (j % 2 === 0 ? c : c.toLowerCase())).join('');
    assert.deepEqual(base32Decode(upper.toLowerCase()), b);
    assert.deepEqual(base32Decode(mixedCase), b);
  }
});

test('Base32 never traps: every one- and two-byte input and 25,000 fuzzed strings agree with the oracle', () => {
  const counts = {};
  for (let byte = 0; byte < 256; byte++) {
    const text = Buffer.from([byte]).toString('utf8');
    const r = outcome(text);
    assert.ok(!r.trap, `byte ${byte}`);
    assert.ok(same(r, referenceBase32Decode(text)), `byte ${byte}`);
    const key = r.code || 'success';
    counts[key] = (counts[key] || 0) + 1;
  }
  assert.deepEqual(counts, { success: 1, invalidLength: 58, invalidCharacter: 197 });
  let accepted = 0;
  for (let first = 0; first < 256; first++) {
    for (let second = 0; second < 256; second++) {
      const text = Buffer.from([first, second]).toString('utf8');
      const r = outcome(text);
      assert.ok(!r.trap && same(r, referenceBase32Decode(text)), `bytes ${first} ${second}`);
      if (r.bytes) {
        accepted++;
        assert.equal(base32Encode(r.bytes), canonicalBase32(text));
      }
    }
  }
  assert.equal(accepted, 58 * 15 + 1);
  const pool = [...(BASE32_ALPHABET + BASE32_ALPHABET.toLowerCase() + '=' + '0189')];
  pool.push('\0', ' ', '\n', ' ', '​', '﻿', '́', 'é', 'K', 'Ａ', '\u{1f600}', '�', '-', '_', '/', '+');
  const rng = new SplitMix64(0xdeadbeefn);
  let successes = 0;
  for (let i = 0; i < 20000; i++) {
    const count = rng.below(41);
    let text = '';
    for (let j = 0; j < count; j++) text += rng.below(8) === 0 ? rng.pick(pool) : BASE32_ALPHABET[rng.below(32)];
    const r = outcome(text);
    assert.ok(!r.trap && same(r, referenceBase32Decode(text)), `iteration ${i}: ${JSON.stringify(text)}`);
    if (r.bytes) {
      successes++;
      assert.equal(base32Encode(r.bytes), canonicalBase32(text));
    }
  }
  assert.ok(successes > 500);
  const arbitrary = new SplitMix64(0xc0ffeen);
  for (let i = 0; i < 5000; i++) {
    const text = Buffer.from(arbitrary.bytes(arbitrary.below(65))).toString('utf8');
    const r = outcome(text);
    assert.ok(!r.trap && same(r, referenceBase32Decode(text)), `iteration ${i}`);
  }
});

test('Base32 handles a mebibyte each way, and hostile mebibyte inputs, in bounded time', () => {
  const rng = new SplitMix64(1n << 20n);
  const bytes = rng.bytes(1 << 20);
  const t0 = performance.now();
  const text = base32Encode(bytes);
  const decoded = base32Decode(text);
  assert.equal(text.length, 1677722);
  assert.deepEqual(decoded, bytes);
  const zeros = 'A'.repeat(1 << 20);
  assert.deepEqual(base32Decode(zeros), new Uint8Array((1 << 20) * 5 / 8));
  assert.deepEqual(base32Decode('='.repeat(1 << 20)), new Uint8Array(0));
  throwsCode(() => base32Decode(zeros + 'A'), Base32Error, 'invalidLength');
  throwsCode(() => base32Decode(zeros + '0'), Base32Error, 'invalidCharacter');
  throwsCode(() => base32Decode('0' + zeros), Base32Error, 'invalidCharacter');
  throwsCode(() => base32Decode(zeros + 'AB'), Base32Error, 'nonZeroPadding');
  assert.deepEqual(base32Decode('7'.repeat(1 << 20)), new Uint8Array((1 << 20) * 5 / 8).fill(0xff));
  assert.ok(performance.now() - t0 < 10000);
});

// MARK: - HB1 wire forms

const body = (v) => v.url.slice(HB1_URL_PREFIX.length + 1);
const urlOutcome = (text) => {
  try { return { map: hb1DecodeURL(text) }; } catch (error) {
    return error instanceof HBError ? { code: error.code, cls: error.constructor.name } : { trap: error };
  }
};

test('HB1 URL spellings: every way HB1.decode(url:) accepts, and every way it refuses', () => {
  for (const v of vectors) {
    const b = body(v);
    const expected = hex(h(v.cbor));
    for (const url of [
      v.url, 'HTTPS://HATBAND.LINK/#1' + b, 'https://Hatband.Link/#1' + b, '  https://hatband.link/#1' + b + ' ', '\n#1' + b + '\t',
      '#1' + b, '1' + b, '#1' + b.toLowerCase(), '#1' + b + '=', '#1' + b + '========', ' #1' + b + '　',
    ]) assert.equal(hex(cborEncode(hb1DecodeURL(url))), expected, JSON.stringify(url));
    assert.deepEqual(hb1Fragment(v.url), h(v.cbor));
    assert.equal(hb1URL(hb1DecodeURL(v.url)), v.url);
    for (const url of [
      'https://example.com/#1' + b, 'https://hatband.link/card#1' + b, 'http://hatband.link/#1' + b, 'https://www.hatband.link/#1' + b,
      'https://hatband.link:443/#1' + b, 'https://hatband.link/?q#1' + b, 'https://hatband.link//#1' + b, 'https://hatband.link#1' + b,
      'https://hatband.link/#/1' + b, 'https://hatband.link/# 1' + b, 'https://hatband.link/#1 ' + b, '#1=' + b, '#1' + b + '=A', '#1' + b + '́',
      '#2' + b, '#' + b, '##1' + b, 'https://hatband.link/#', '#', '', ' ', 'BEGIN:VCARD', 'https://hatband.link/#1!!', '#1' + b.slice(0, 3),
      '#1' + b + '%41', '#1' + b.replace(/[A-Z]/, '0'), '#1' + b.replace(/[A-Z]/, '1'),
    ]) {
      const r = urlOutcome(url);
      assert.equal(r.code, 'notHatband', JSON.stringify(url));
      assert.equal(r.cls, 'HB1Error');
    }
    for (const tag of ['0', '8', '9']) throwsCode(() => hb1DecodeURL('#' + tag + b), HB1Error, 'unsupportedFormat', { tag });
    // One character short: an impossible length or fill bits (not Base32, so not Hatband), else CBOR cut short.
    const short = b.slice(0, -1);
    if (referenceBase32Decode(short).bytes) throwsCode(() => hb1DecodeURL('#1' + short), CBORError, 'truncated');
    else throwsCode(() => hb1DecodeURL('#1' + short), HB1Error, 'notHatband');
  }
  // A tag with nothing after it is an empty byte string, which is CBOR cut short, as in Swift.
  for (const url of ['#1', '1', 'https://hatband.link/#1', '#1=', '#1========']) throwsCode(() => hb1DecodeURL(url), CBORError, 'truncated');
  // Both decoders lower-case with Unicode rules, so a Kelvin sign in the host folds to `k`; documented, not exploited.
  assert.doesNotThrow(() => hb1DecodeURL('https://hatband.linK/#1' + body(vectors[0])));
});

test('flipping any bit of any vector yields a rejection, a card whose signature fails, or an unsigned card', async () => {
  let accepted = 0;
  let rejected = 0;
  let verified = 0;
  let restored = 0;
  const signedCBOR = new Set(vectors.filter((v) => v.valid === true).map((v) => v.cbor));
  for (const v of vectors) {
    const original = h(v.cbor);
    const originalMap = hb1DecodeURL(v.url);
    const originalCard = cardFromMap(originalMap);
    const stride = original.length > 2048 ? 97 : 1;
    for (let bit = 0; bit < original.length * 8; bit += stride) {
      const mutant = Uint8Array.from(original);
      mutant[bit >> 3] ^= 1 << (bit & 7);
      const url = HB1_URL_PREFIX + '1' + base32Encode(mutant);
      const r = urlOutcome(url);
      assert.ok(!r.trap, `${v.name} bit ${bit}: ${r.trap}`);
      if (r.code) { rejected++; continue; }
      assert.ok(bytesEqual(cborEncode(r.map), mutant), `${v.name} bit ${bit}: accepted but not canonical`);
      accepted++;
      let card;
      try { card = cardFromMap(r.map); } catch (error) { assert.ok(error instanceof CardError, `${v.name} bit ${bit}`); continue; }
      if (!isSigned(card) || !isSigned(originalCard)) continue;
      verified++;
      const valid = await verifySignature(card.publicKey, card.signature, signingBytes(r.map));
      // The tampered vector is typical-signed with one bit flipped; flipping it back is the one mutant that verifies.
      if (valid && signedCBOR.has(hex(mutant))) { restored++; continue; }
      assert.equal(valid, false, `${v.name} bit ${bit} still verifies`);
    }
  }
  assert.equal(restored, 1);
  assert.ok(accepted > 500 && rejected > 500 && verified > 200, `${accepted} accepted, ${rejected} rejected, ${verified} verified`);
});

test('mutating the Base32 of every vector: accepted only when canonical, and then the URL rebuilds itself', () => {
  const rng = new SplitMix64(0x4831n);
  let accepted = 0;
  for (const v of vectors) {
    const b = body(v);
    const check = (text) => {
      const r = urlOutcome('#1' + text);
      assert.ok(!r.trap, text.slice(0, 40));
      if (r.code) {
        assert.ok(['notHatband', 'tooLarge'].includes(r.code) || r.cls === 'CBORError' || r.cls === 'CardError', `${r.cls} ${r.code}`);
        return;
      }
      accepted++;
      assert.equal(hb1URL(r.map), HB1_URL_PREFIX + '1' + canonicalBase32(text));
      assert.ok(bytesEqual(hb1Fragment('#1' + text), cborEncode(r.map)));
    };
    for (let cut = 0; cut <= b.length; cut++) check(b.slice(0, cut));
    for (let i = 0; i < b.length; i += Math.max(1, Math.floor(b.length / 120))) {
      for (let k = 0; k < 4; k++) {
        const c = BASE32_ALPHABET[rng.below(32)];
        check(b.slice(0, i) + c + b.slice(i + 1));
        check(b.slice(0, i) + c + b.slice(i));
      }
      check(b.slice(0, i) + b.slice(i + 1));
      check(b.slice(0, i) + rng.pick(['0', '1', '=', ' ', '​', '́', 'ａ']) + b.slice(i + 1));
    }
  }
  assert.ok(accepted >= vectors.length, String(accepted));
});

test('the 32 KB ceiling: exact size accepted, one byte over refused, 100 KB refused, and a 10 MB fragment refused before allocation', () => {
  const photoCard = (photoLength) => cborEncode(new Map([[16, repeat(7, 8)], [17, 0], [20, repeat(0xd8, photoLength)]]));
  const overhead = photoCard(1000).length - 1000;
  const exact = photoCard(HB1_MAX_BYTES - overhead);
  assert.equal(exact.length, HB1_MAX_BYTES);
  assert.equal(base32Encode(exact).length, HB1_MAX_FRAGMENT);
  assert.equal(HB1_MAX_FRAGMENT, 52429);
  assert.equal(cardFromMap(hb1DecodeURL('#1' + base32Encode(exact))).photo.length, HB1_MAX_BYTES - overhead);
  const over = photoCard(HB1_MAX_BYTES - overhead + 1);
  assert.equal(over.length, HB1_MAX_BYTES + 1);
  throwsCode(() => hb1DecodeCBOR(over), HB1Error, 'tooLarge', { size: HB1_MAX_BYTES + 1 });
  throwsCode(() => hb1DecodeURL('#1' + base32Encode(over)), HB1Error, 'tooLarge');
  const hundredKB = photoCard(100 * 1024);
  throwsCode(() => hb1DecodeURL('#1' + base32Encode(hundredKB)), HB1Error, 'tooLarge');
  throwsCode(() => hb1DecodeCBOR(hundredKB), HB1Error, 'tooLarge', { size: hundredKB.length });
  // No valid Base32 text longer than HB1_MAX_FRAGMENT decodes to HB1_MAX_BYTES bytes or fewer.
  for (let n = HB1_MAX_FRAGMENT + 1; n < HB1_MAX_FRAGMENT + 40; n++) {
    if (validRemainders.has(n % 8)) assert.ok(Math.floor(n * 5 / 8) > HB1_MAX_BYTES, String(n));
  }
  const t0 = performance.now();
  const before = process.memoryUsage().heapUsed;
  for (const text of ['A'.repeat(10 * 1024 * 1024), '!'.repeat(10 * 1024 * 1024), 'A'.repeat(HB1_MAX_FRAGMENT + 1), 'A'.repeat(52429) + '='.repeat(9) + 'A']) {
    throwsCode(() => hb1DecodeURL('#1' + text), HB1Error, 'tooLarge');
    throwsCode(() => hb1DecodeURL(HB1_URL_PREFIX + '1' + text), HB1Error, 'tooLarge');
  }
  assert.ok(performance.now() - t0 < 250, 'refused without decoding');
  assert.ok(process.memoryUsage().heapUsed - before < 16 * 1024 * 1024, 'refused without allocating for the payload');
  // Trailing pad does not count, as Swift strips it before decoding.
  assert.doesNotThrow(() => hb1DecodeURL('#1' + base32Encode(exact) + '='.repeat(100000)));
  throwsCode(() => hb1DecodeURL('#1' + '='.repeat(10 * 1024 * 1024)), CBORError, 'truncated');
  throwsCode(() => hb1DecodeURL('#1' + 'A'.repeat(HB1_MAX_FRAGMENT)), CBORError, 'trailingBytes');
});

test('hb1DecodeURL never throws anything but an HBError, for 5,000 fuzzed strings and every vector map with one field mutated', () => {
  const pool = ['#', '1', '#1', 'https://hatband.link/', 'HTTPS://HATBAND.LINK/', 'A', 'AAAA', 'MZXW6YTBOI', '=', '0', ' ', '\n', '​', '́', '%', '<script>', 'ａ', '9', '8'];
  const rng = new SplitMix64(0x4831414141n);
  for (let i = 0; i < 5000; i++) {
    let text = '';
    for (let j = rng.below(12); j > 0; j--) text += rng.pick(pool);
    const r = urlOutcome(text);
    assert.ok(!r.trap, JSON.stringify(text) + ' ' + r.trap);
  }
  const values = [0, -1, 1n << 60n, '', 'x', new Uint8Array(0), repeat(1, 8), repeat(1, 32), repeat(1, 48), repeat(1, 64), [], [[]], [['l', 'v', 0]], [['l', 'v', 5]], new Map(), true, null];
  for (const v of vectors) {
    const base = hb1DecodeURL(v.url);
    for (const key of [...base.keys(), 99, 'text-key', -1]) {
      for (const value of values) {
        const m = new Map(base);
        m.set(key, value);
        const r = urlOutcome(hb1URL(m));
        assert.ok(!r.trap, `${v.name} ${String(key)}`);
        if (r.map) {
          try { cardFromMap(r.map); } catch (error) { assert.ok(error instanceof CardError, `${v.name} ${String(key)}`); }
        }
      }
    }
  }
});
