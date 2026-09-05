import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Base32Error, base32Decode, base32Encode } from '../src/hb1.js';
import { throwsCode, repeat } from './helpers.mjs';

const rejects = (text, code) => throwsCode(() => base32Decode(text), Base32Error, code);
const bytes = (s) => new TextEncoder().encode(s);

/** RFC 4648 §10, without padding. */
const rfc = [['', ''], ['f', 'MY'], ['fo', 'MZXQ'], ['foo', 'MZXW6'], ['foob', 'MZXW6YQ'], ['fooba', 'MZXW6YTB'], ['foobar', 'MZXW6YTBOI']];

test('encodes and decodes the RFC vectors, either case', () => {
  for (const [plain, encoded] of rfc) {
    assert.equal(base32Encode(bytes(plain)), encoded);
    assert.deepEqual(base32Decode(encoded), bytes(plain));
    assert.deepEqual(base32Decode(encoded.toLowerCase()), bytes(plain));
  }
});

test('accepts padded input', () => {
  assert.deepEqual(base32Decode('MY======'), bytes('f'));
  assert.deepEqual(base32Decode('MZXW6==='), bytes('foo'));
  for (let pads = 0; pads <= 9; pads++) {
    assert.deepEqual(base32Decode('MY' + '='.repeat(pads)), bytes('f'));
    assert.deepEqual(base32Decode('='.repeat(pads)), new Uint8Array());
  }
  assert.deepEqual(base32Decode('MY' + '='.repeat(1000)), bytes('f'));
});

test('matches coreutils base32', () => {
  const cases = [
    [repeat(0, 5), 'AAAAAAAA'], [repeat(0xff, 5), '77777777'], [repeat(0xff, 4), '777777Y='],
    [Uint8Array.of(1), 'AE======'], [Uint8Array.of(0x80), 'QA======'],
    [Uint8Array.from({ length: 16 }, (_, i) => i), 'AAAQEAYEAUDAOCAJBIFQYDIOB4======'],
    [bytes('The quick brown fox jumps over the lazy dog'), 'KRUGKIDROVUWG2ZAMJZG653OEBTG66BANJ2W24DTEBXXMZLSEB2GQZJANRQXU6JAMRXWO==='],
  ];
  for (const [raw, padded] of cases) {
    assert.equal(base32Encode(raw), padded.replace(/=+$/, ''));
    assert.deepEqual(base32Decode(padded), raw);
  }
});

test('rejects malformed input with the Swift error', () => {
  for (const [text, code] of [
    ['M', 'invalidLength'], ['MZX', 'invalidLength'], ['MZXW6Y', 'invalidLength'],
    ['MY1', 'invalidCharacter'], ['M Y', 'invalidCharacter'], ['MY=A', 'invalidCharacter'],
    ['MZ', 'nonZeroPadding'], ['MZXW7', 'nonZeroPadding'],
    ['M=======', 'invalidLength'], ['MZX=====', 'invalidLength'], ['MZXW6Y==', 'invalidLength'], ['A=', 'invalidLength'],
    ['MZ======', 'nonZeroPadding'], ['MZXW7===', 'nonZeroPadding'], ['777777Z=', 'nonZeroPadding'],
    ['MZXQ====MZXW7===', 'invalidCharacter'],
  ]) rejects(text, code);
});

test('accepts exactly the lengths a quantum can end', () => {
  const accepted = new Set([0, 2, 4, 5, 7]);
  for (let count = 0; count <= 256; count++) {
    const text = 'A'.repeat(count);
    if (accepted.has(count % 8)) assert.deepEqual(base32Decode(text), repeat(0, Math.floor(count * 5 / 8)));
    else rejects(text, 'invalidLength');
  }
});

test('pad before the end is a character error', () => {
  for (const text of ['=MY', 'M=Y', 'MY=MY', 'MY======MY', 'MZXW6=YTB', 'MY======\n', 'MY====== ', 'MY=======A', 'MY=​']) {
    rejects(text, 'invalidCharacter');
  }
});

test('fill bits must be zero', () => {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  for (const count of [2, 4, 5, 7]) {
    const fill = (count * 5) % 8;
    for (let value = 0; value < 32; value++) {
      const text = 'A'.repeat(count - 1) + alphabet[value];
      if ((value & ((1 << fill) - 1)) === 0) {
        const decoded = base32Decode(text);
        assert.equal(decoded.length, Math.floor(count * 5 / 8));
        assert.equal(base32Encode(decoded), text);
      } else {
        rejects(text, 'nonZeroPadding');
        rejects(text.toLowerCase(), 'nonZeroPadding');
      }
    }
  }
});

test('rejects non-alphabet scalars anywhere', () => {
  const hostile = ['0', '1', '8', '9', ' ', '\t', '\n', '\r', '\0', '', '-', '_', '+', '/', '.', ',', ':',
    ' ', '​', '﻿', '́', 'é', 'ı', 'K', 'Ａ', '２', '\u{1d400}', '\u{1f600}', '�'];
  for (const scalar of hostile) {
    for (const [head, tail] of [['', 'MZXW6YTB'], ['MZXW', '6YTB'], ['MZXW6YTB', ''], ['MZXW6YTBOI', ''], ['', '']]) {
      rejects(head + scalar + tail, 'invalidCharacter');
    }
  }
  for (const text of ['MZXW6YTB\r\nOI', 'MZXW6YTB\nOI', 'MZXW6YTB OI', 'MZXW6YTBOI\n', ' MZXW6YTBOI']) rejects(text, 'invalidCharacter');
});

test('O, I and L keep their values; 0 and 1 are not aliases', () => {
  assert.deepEqual(base32Decode('OA'), Uint8Array.of(14 << 3));
  assert.deepEqual(base32Decode('iA'), Uint8Array.of(8 << 3));
  assert.deepEqual(base32Decode('lA'), Uint8Array.of(11 << 3));
  rejects('0A', 'invalidCharacter');
  rejects('1A', 'invalidCharacter');
});

test('round trips every length and mixed case', () => {
  for (let length = 0; length <= 64; length++) {
    const raw = Uint8Array.from({ length }, (_, i) => (i * 37 + 11) & 0xff);
    const text = base32Encode(raw);
    assert.equal(text.length, Math.floor((length * 8 + 4) / 5));
    assert.match(text, /^[A-Z2-7]*$/);
    assert.deepEqual(base32Decode(text), raw);
    const mixed = [...text].map((c, i) => (i % 2 ? c.toLowerCase() : c)).join('');
    assert.deepEqual(base32Decode(mixed), raw);
  }
  const all = Uint8Array.from({ length: 256 }, (_, i) => i);
  assert.deepEqual(base32Decode(base32Encode(all)), all);
});
