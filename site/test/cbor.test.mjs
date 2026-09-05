import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CBORError, CBOR_MAX_DEPTH, cborDecode, cborEncode, hexEncode } from '../src/hb1.js';
import { h, u8, repeat, throwsCode, vectors } from './helpers.mjs';

const rejects = (hex, code, extra) => throwsCode(() => cborDecode(h(hex)), CBORError, code, extra);
const unsupported = (major, info) => ({ major, info });
const roundTrips = (hex) => {
  const decoded = cborDecode(h(hex));
  assert.deepEqual(cborEncode(decoded), h(hex));
  return decoded;
};

/** RFC 8949 Appendix A, the subset within the supported types. */
const rfc = [
  [0, '00'], [1, '01'], [10, '0a'], [23, '17'], [24, '1818'], [25, '1819'], [100, '1864'], [1000, '1903e8'],
  [1000000, '1a000f4240'], [1000000000000, '1b000000e8d4a51000'], [18446744073709551615n, '1bffffffffffffffff'],
  [-1, '20'], [-10, '29'], [-100, '3863'], [-1000, '3903e7'], [-18446744073709551616n, '3bffffffffffffffff'],
  [false, 'f4'], [true, 'f5'], [null, 'f6'], [u8(), '40'], [u8(1, 2, 3, 4), '4401020304'],
  ['', '60'], ['a', '6161'], ['IETF', '6449455446'], ['"\\', '62225c'], ['ü', '62c3bc'], ['水', '63e6b0b4'], ['𐅑', '64f0908591'],
  [[], '80'], [[1, 2, 3], '83010203'], [[1, [2, 3], [4, 5]], '8301820203820405'],
  [Array.from({ length: 25 }, (_, i) => i + 1), '98190102030405060708090a0b0c0d0e0f101112131415161718181819'],
  [new Map(), 'a0'], [new Map([[1, 2], [3, 4]]), 'a201020304'], [new Map([['a', 1], ['b', [2, 3]]]), 'a26161016162820203'],
  [['a', new Map([['b', 'c']])], '826161a161626163'],
  [new Map([['a', 'A'], ['b', 'B'], ['c', 'C'], ['d', 'D'], ['e', 'E']]), 'a56161614161626142616361436164614461656145'],
];

test('encodes and decodes the RFC vectors', () => {
  for (const [value, hex] of rfc) {
    assert.equal(hexEncode(cborEncode(value)), hex, `encode ${hex}`);
    assert.deepEqual(cborDecode(h(hex)), value, `decode ${hex}`);
  }
});

test('map keys sort by encoded bytes, not length first', () => {
  assert.equal(hexEncode(cborEncode(new Map([[10, 1], [1, 2]]))), 'a201020a01');
  assert.equal(hexEncode(cborEncode(new Map([[256, 0], [1, 0]]))), 'a2010019010000');
  assert.equal(hexEncode(cborEncode(new Map([['b', 1], ['a', 2]]))), 'a2616102616201');
  assert.equal(hexEncode(cborEncode(new Map([['aa', 1], ['b', 2]]))), 'a261620262616101');
  const keys = [10, 100, -1, 'z', 'aa', [100], [-1], false];
  const map = new Map(keys.map((k, i) => [k, i]));
  assert.equal(hexEncode(cborEncode(map)), 'a80a00186401200261 7a03626161048118640581200 6f407'.replace(/\s/g, ''));
  assert.equal(hexEncode(cborEncode(new Map([...map].reverse()))), hexEncode(cborEncode(map)));
});

test('rejects malformed input with the Swift error', () => {
  for (const [hex, code, extra] of [
    ['1800', 'notShortestForm'], ['1817', 'notShortestForm'], ['1900ff', 'notShortestForm'], ['1a0000ffff', 'notShortestForm'],
    ['1b00000000ffffffff', 'notShortestForm'], ['5800', 'notShortestForm'],
    ['9f', 'indefiniteLength'], ['5f', 'indefiniteLength'],
    ['c000', 'unsupported', unsupported(6, 0)], ['f93c00', 'unsupported', unsupported(7, 25)], ['f7', 'unsupported', unsupported(7, 23)],
    ['1c', 'unsupported', unsupported(0, 28)],
    ['a20a010102', 'mapKeysNotOrdered'], ['a201010102', 'mapKeysNotOrdered'], ['a2616201616101', 'mapKeysNotOrdered'],
    ['62ffff', 'invalidUTF8'], ['18', 'truncated'], ['4401', 'truncated'], ['82010101', 'trailingBytes'], ['0000', 'trailingBytes'],
    ['', 'truncated'], ['83', 'truncated'],
  ]) rejects(hex, code, extra);
});

test('non-shortest integers and lengths are rejected everywhere', () => {
  for (const hex of ['18 00', '18 17', '19 0000', '19 0018', '19 00ff', '1a 00000000', '1a 0000ffff', '1b 0000000000000000',
    '1b 00000000ffffffff', '38 00', '38 17', '39 00ff', '3a 0000ffff', '3b 00000000ffffffff',
    '58 00', '78 00', '78 01 61', '79 0001 61', '7b 0000000000000001 61', '98 00', '98 01 00', '99 0001 00', '9a 00000001 00',
    '9b 0000000000000001 00', 'b8 00', 'b8 01 00 00', 'b9 0001 00 00', 'ba 00000001 00 00', 'bb 0000000000000001 00 00',
    '9b 00000000ffffffff', '5b 00000000ffffffff', 'ba 0000ffff',
    '82 00 18 01', 'a1 18 01 00', 'a1 00 18 01']) {
    rejects(hex, 'notShortestForm');
  }
});

test('64-bit edges round trip with the right width', () => {
  for (const [hex, value] of [
    ['1a ffffffff', 0xffffffff], ['1b 0000000100000000', 0x100000000], ['1b 001fffffffffffff', Number.MAX_SAFE_INTEGER],
    ['1b 0020000000000000', 9007199254740992n], ['1b 7fffffffffffffff', 9223372036854775807n], ['1b ffffffffffffffff', 18446744073709551615n],
    ['3a ffffffff', -4294967296], ['3b 0000000100000000', -4294967297], ['3b 001ffffffffffffe', -Number.MAX_SAFE_INTEGER],
    ['3b 001fffffffffffff', -9007199254740992n], ['3b ffffffffffffffff', -18446744073709551616n],
  ]) {
    assert.deepEqual(cborDecode(h(hex)), value);
    assert.deepEqual(cborEncode(value), h(hex));
  }
  assert.throws(() => cborEncode(1.5), TypeError);
  assert.throws(() => cborEncode(2n ** 64n), RangeError);
  assert.throws(() => cborEncode(-(2n ** 64n) - 1n), RangeError);
});

test('indefinite lengths are rejected even when well formed', () => {
  for (const hex of ['5f 42 01 02 43 03 04 05 ff', '7f 65 73 74 72 65 61 64 6d 69 6e 67 ff', '9f ff', '9f 01 82 02 03 9f 04 05 ff ff',
    'bf 61 61 01 61 62 9f 02 03 ff ff', '82 61 61 bf 61 62 61 63 ff', '5f 41 00', '7f 61 00', '9f', 'bf', '81 9f', 'a1 00 9f ff', 'a1 9f ff 00',
    '1f', '3f']) {
    rejects(hex, 'indefiniteLength');
  }
});

test('tags, floats, undefined and simple values are unsupported', () => {
  for (const [hex, major, info] of [
    ['c2 49 01 00 00 00 00 00 00 00 00', 6, 2], ['c0 74 32 30 31 33 2d 30 33 2d 32 31 54 32 30 3a 30 34 3a 30 30 5a', 6, 0],
    ['c1 1a 51 4b 67 b0', 6, 1], ['d7 44 01 02 03 04', 6, 23], ['d8 18 45 64 49 45 54 46', 6, 24], ['d9 d9 f7 00', 6, 25], ['df', 6, 31],
    ['f9 00 00', 7, 25], ['f9 7e 00', 7, 25], ['fa 7f c0 00 00', 7, 26], ['fb 3f f1 99 99 99 99 99 9a', 7, 27],
    ['f7', 7, 23], ['f0', 7, 16], ['f8 ff', 7, 24], ['f8 00', 7, 24], ['ff', 7, 31], ['81 ff', 7, 31], ['a1 00 ff', 7, 31],
    ['d8', 6, 24], ['f8', 7, 24], ['f9 00', 7, 25],
  ]) {
    rejects(hex, 'unsupported', unsupported(major, info));
  }
  for (const initial of [0x1c, 0x1d, 0x1e, 0x3c, 0x5d, 0x7e, 0x9c, 0xbd, 0xdc, 0xfe]) {
    const extra = unsupported(initial >> 5, initial & 0x1f);
    throwsCode(() => cborDecode(u8(initial)), CBORError, 'unsupported', extra);
    throwsCode(() => cborDecode(u8(0x81, initial)), CBORError, 'unsupported', extra);
  }
});

test('invalid UTF-8 is rejected wherever it appears', () => {
  for (const hex of ['61 80', '61 c0', '62 c0 80', '62 c1 bf', '63 e0 80 80', '63 e0 9f bf', '64 f0 80 80 80', '64 f0 8f bf bf',
    '63 ed a0 80', '63 ed bf bf', '66 ed a0 bd ed b2 a9', '64 f4 90 80 80', '64 f5 80 80 80', '65 f8 88 80 80 80', '61 fe', '61 ff',
    '62 e2 82', '63 e2 82 41', '62 c3 28', '63 e2 28 a1', '64 f0 90 28 bc', '64 f0 28 8c bc', '62 61 ff', '63 ef bf ff',
    '81 61 ff', 'a1 61 ff 00', 'a1 00 61 ff', '82 00 82 00 61 ff', 'a1 81 61 ff 00']) {
    rejects(hex, 'invalidUTF8');
  }
});

test('valid UTF-8 at every width round trips, BOM and noncharacters kept', () => {
  for (const [hex, text] of [
    ['61 00', '\0'], ['61 7f', ''], ['62 c2 80', ''], ['62 df bf', '߿'], ['63 e0 a0 80', 'ࠀ'],
    ['63 ed 9f bf', '퟿'], ['63 ee 80 80', ''], ['63 ef bf bd', '�'], ['63 ef bf be', '￾'], ['63 ef bf bf', '￿'],
    ['63 ef b7 90', '﷐'], ['63 ef bb bf', '﻿'], ['64 f0 90 80 80', '\u{10000}'], ['64 f4 8f bf bf', '\u{10ffff}'],
    ['64 f0 9f 98 80', '\u{1f600}'], ['62 0d 0a', '\r\n'], ['66 65 cc 81 e2 80 8d', 'é‍'],
  ]) {
    assert.equal(cborDecode(h(hex)), text);
    assert.deepEqual(cborEncode(text), h(hex));
  }
  // The encoder writes stored bytes verbatim: no normalization.
  assert.equal(hexEncode(cborEncode('é')), '62c3a9');
  assert.equal(hexEncode(cborEncode('é')), '6365cc81');
  // NFC and NFD spellings are distinct keys and both survive.
  const map = roundTrips('a2 62c3a9 00 6365cc81 01');
  assert.equal(map.size, 2);
});

test('map key order: every RFC pair accepted in order, rejected reversed', () => {
  const keys = ['0a', '1864', '20', '617a', '626161', '811864', '8120', 'f4'];
  for (let i = 0; i < keys.length; i++) {
    for (let j = i + 1; j < keys.length; j++) {
      assert.equal(roundTrips(`a2 ${keys[i]} 00 ${keys[j]} 00`).size, 2);
      rejects(`a2 ${keys[j]} 00 ${keys[i]} 00`, 'mapKeysNotOrdered');
    }
  }
  rejects('a8 0a00 2002 f407 186401 617a03 812006 62616104 81186405', 'mapKeysNotOrdered');
  for (const hex of ['a2 00 00 20 00', 'a2 1bffffffffffffffff 00 20 00', 'a2 18ff 00 190100 00', 'a2 37 00 3818 00', 'a2 41ff 00 60 00',
    'a2 4161 00 6161 00', 'a2 6162 00 626161 00', 'a2 811864 00 8120 00', 'a2 8120 00 a0 00', 'a2 a0 00 f4 00', 'a2 f4 00 f6 00']) {
    roundTrips(hex);
  }
  for (const hex of ['a2 20 00 00 00', 'a2 190100 00 18ff 00', 'a2 3818 00 37 00', 'a2 60 00 41ff 00', 'a2 6161 00 4161 00',
    'a2 626161 00 6162 00', 'a2 80 00 60 00', 'a2 a0 00 80 00', 'a2 f4 00 a0 00', 'a2 f6 00 f5 00', 'a2 f5 00 f4 00']) {
    rejects(hex, 'mapKeysNotOrdered');
  }
});

test('duplicate keys are rejected, nested maps included', () => {
  for (const hex of ['a2 00 00 00 01', 'a2 6161 00 6161 01', 'a2 40 00 40 01', 'a2 80 00 80 01', 'a2 a0 00 a0 01', 'a2 f6 00 f6 01',
    'a3 00 00 01 00 01 00', 'a3 00 00 01 00 00 00', 'a1 00 a2 01 00 00 00', '81 a2 01 00 00 00', 'a1 a2 01 00 00 00 00', '82 00 a2 00 00 00 01']) {
    rejects(hex, 'mapKeysNotOrdered');
  }
});

test('depth is capped at 32 and fails fast', () => {
  const nested = (n, leaf = u8(0)) => Uint8Array.from([...repeat(0x81, n), ...leaf]);
  assert.equal(CBOR_MAX_DEPTH, 32);
  assert.doesNotThrow(() => cborDecode(nested(CBOR_MAX_DEPTH)));
  throwsCode(() => cborDecode(nested(CBOR_MAX_DEPTH + 1)), CBORError, 'tooDeep');
  const maps = (n) => Uint8Array.from([...Array.from({ length: n }, () => [0xa1, 0x00]).flat(), 0]);
  assert.doesNotThrow(() => cborDecode(maps(CBOR_MAX_DEPTH)));
  throwsCode(() => cborDecode(maps(CBOR_MAX_DEPTH + 1)), CBORError, 'tooDeep');
  // Counted through map keys too.
  assert.doesNotThrow(() => cborDecode(Uint8Array.from([0xa1, ...nested(CBOR_MAX_DEPTH - 1), 0])));
  throwsCode(() => cborDecode(Uint8Array.from([0xa1, ...nested(CBOR_MAX_DEPTH), 0])), CBORError, 'tooDeep');
  throwsCode(() => cborDecode(repeat(0x81, 1000000)), CBORError, 'tooDeep');
  throwsCode(() => cborDecode(repeat(0xa1, 1000000)), CBORError, 'tooDeep');
});

test('hostile lengths fail before allocating', () => {
  for (const hex of ['7b 00000001 00000000', '9a ff ff ff ff', '9b 00 00 00 01 00 00 00 00', '9b ff ff ff ff ff ff ff ff', 'ba ff ff ff ff',
    'bb ff ff ff ff ff ff ff ff', '5a ff ff ff ff', '5b 00 00 00 01 00 00 00 00', '7a ff ff ff ff', '98 ff', '99 ff ff 00', 'b8 ff 00 00',
    'a3 00 00 01 01', 'a2 00 00 01', '83 00 01', '58 20 00', '81 9a ff ff ff ff', 'a1 00 ba ff ff ff ff', 'a5 00 00 01 01 02',
    '41', '61', '5b ff ff ff ff ff ff ff ff 01 02 03', '81', '82 00', 'a1', 'a2 01 02', 'a1 00', 'a2 00 00 00', 'a1 81', 'a1 ff', 'a2 00 00 ff',
    '19 01', '1a 01 02', '1b 01 02 03 04 05 06 07', '38', '58', '78', '98', 'b8']) {
    rejects(hex, 'truncated');
  }
  assert.doesNotThrow(() => cborDecode(h('a2 00 00 01 01')));
});

test('trailing bytes are rejected', () => {
  for (const hex of ['00 00', '00 ff', '80 00', 'a0 00', '40 00', '60 00', 'f6 f6', '81 00 00', 'a1 00 00 00',
    '1b ff ff ff ff ff ff ff ff 00', '44 01 02 03 04 05', '63 e6 b0 b4 00', '80 ff']) {
    rejects(hex, 'trailingBytes');
  }
});

test('every initial byte alone decodes or fails as the Swift decoder does', () => {
  for (let initial = 0; initial < 256; initial++) {
    const major = initial >> 5;
    const info = initial & 0x1f;
    const one = u8(initial);
    if (major <= 1 && info < 24) assert.deepEqual(cborDecode(one), major === 0 ? info : -1 - info);
    else if (major === 2 && info === 0) assert.deepEqual(cborDecode(one), u8());
    else if (major === 3 && info === 0) assert.equal(cborDecode(one), '');
    else if (major === 4 && info === 0) assert.deepEqual(cborDecode(one), []);
    else if (major === 5 && info === 0) assert.deepEqual(cborDecode(one), new Map());
    else if (major === 7 && info === 20) assert.equal(cborDecode(one), false);
    else if (major === 7 && info === 21) assert.equal(cborDecode(one), true);
    else if (major === 7 && info === 22) assert.equal(cborDecode(one), null);
    else if ((major <= 5 && info >= 24 && info <= 27) || (major >= 2 && major <= 5 && info < 24)) throwsCode(() => cborDecode(one), CBORError, 'truncated');
    else if (major <= 5 && info === 31) throwsCode(() => cborDecode(one), CBORError, 'indefiniteLength');
    else throwsCode(() => cborDecode(one), CBORError, 'unsupported', unsupported(major, info));
  }
});

test('every published card re-encodes to its own bytes', () => {
  for (const v of vectors) {
    assert.deepEqual(hexEncode(cborEncode(cborDecode(h(v.cbor)))), v.cbor, v.name);
    for (let cut = 0; cut < v.cbor.length / 2; cut += 7) throwsCode(() => cborDecode(h(v.cbor).subarray(0, cut)), CBORError, 'truncated');
    throwsCode(() => cborDecode(h(v.cbor + '00')), CBORError, 'trailingBytes');
  }
});
