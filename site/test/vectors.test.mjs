import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  CBORError, CardError, CustomKind, HB1Error, HB1_FILE_MAGIC, HB1_MAX_BYTES, HB1_URL_PREFIX, base32Encode, cardFromMap, cborEncode,
  cborToJSON, hb1DecodeCBOR, hb1DecodeFile, hb1DecodeURL, hb1Fragment, hb1URL, hexEncode, isJPEG, isSigned, signatureStatus,
  signingBytes, verifySignature,
} from '../src/hb1.js';
import { h, repeat, throwsCode, vector, vectorFile, vectors } from './helpers.mjs';

test('the vector file describes HB1 as this decoder knows it', () => {
  assert.equal(vectorFile.format, 'HB1');
  assert.equal(vectorFile.urlPrefix, HB1_URL_PREFIX);
  assert.equal(vectorFile.fileMagic, hexEncode(HB1_FILE_MAGIC));
  assert.equal(vectorFile.signingDomain, 'hatband-card-v1');
  assert.ok(vectors.length >= 9);
});

for (const v of vectors) {
  const body = v.url.slice(HB1_URL_PREFIX.length);

  test(`${v.name}: the URL decodes to exactly the published map`, () => {
    const map = hb1DecodeURL(v.url);
    assert.deepEqual(cborToJSON(map), v.map);
    assert.equal(hexEncode(cborEncode(map)), v.cbor);
    assert.equal(hb1URL(map), v.url);
    assert.equal(v.budget.bytes, v.cbor.length / 2);
  });

  test(`${v.name}: URL spellings — upper-case host, lower-case Base32, bare fragment, whitespace`, () => {
    const expected = cborToJSON(hb1DecodeURL(v.url));
    for (const url of [
      'HTTPS://HATBAND.LINK/#' + body, 'https://Hatband.Link/#' + body, '  https://hatband.link/#' + body + '\n',
      '#' + body, body, HB1_URL_PREFIX + body[0] + body.slice(1).toLowerCase(), '#' + body.toLowerCase(),
    ]) {
      assert.deepEqual(cborToJSON(hb1DecodeURL(url)), expected, url);
    }
    assert.deepEqual(hb1Fragment(v.url), h(v.cbor));
  });

  test(`${v.name}: the file form is the CBOR behind the magic`, () => {
    assert.equal(v.file.slice(0, 8), '48423100');
    assert.deepEqual(cborToJSON(hb1DecodeFile(h(v.file))), v.map);
    throwsCode(() => hb1DecodeFile(h(v.file).subarray(1)), HB1Error, 'badMagic');
    throwsCode(() => hb1DecodeFile(h(v.cbor)), HB1Error, 'badMagic');
  });

  test(`${v.name}: signing bytes are the map without key 15`, () => {
    const map = hb1DecodeURL(v.url);
    assert.equal(hexEncode(signingBytes(map)), v.signingBytes);
    if (map.has(15)) assert.notEqual(v.signingBytes, v.cbor);
    else assert.equal(v.signingBytes, v.cbor);
  });

  test(`${v.name}: signature verification agrees with the vector`, async () => {
    const map = hb1DecodeURL(v.url);
    const card = cardFromMap(map);
    if (v.valid === null) {
      assert.equal(v.keyIndex, null);
      assert.equal(card.publicKey, null);
      assert.equal(card.signature, null);
      assert.equal(isSigned(card), false);
      assert.equal(await signatureStatus(card, map), 'none');
    } else {
      assert.equal(hexEncode(card.publicKey), v.publicKey);
      assert.equal(hexEncode(card.signature), v.signature);
      assert.equal(await verifySignature(card.publicKey, card.signature, signingBytes(map)), v.valid);
      assert.equal(await signatureStatus(card, map), v.valid ? 'verified' : 'invalid');
    }
  });
}

test('tampering with a signed card invalidates it', async () => {
  const v = vector('typical-signed');
  const map = hb1DecodeURL(v.url);
  const card = cardFromMap(map);
  assert.equal(await verifySignature(card.publicKey, card.signature, signingBytes(map)), true);
  const renamed = new Map(map);
  renamed.set(1, 'Leopold Bloom ');
  assert.equal(await verifySignature(card.publicKey, card.signature, signingBytes(renamed)), false);
  const reseq = new Map(map);
  reseq.set(21, 2);
  assert.equal(await verifySignature(card.publicKey, card.signature, signingBytes(reseq)), false);
  const otherKey = hb1DecodeURL(vector('alias-signed').url).get(14);
  assert.equal(await verifySignature(otherKey, card.signature, signingBytes(map)), false);
  assert.equal(await verifySignature(card.publicKey.subarray(1), card.signature, signingBytes(map)), false);
  assert.equal(await verifySignature(card.publicKey, card.signature.subarray(1), signingBytes(map)), false);
  assert.equal(vector('tampered-signature').valid, false);
  assert.equal(await signatureStatus(card, map, null), 'unsupported');
  const noEd25519 = { importKey: async () => { throw new Error('NotSupportedError'); } };
  assert.equal(await signatureStatus(card, map, noEd25519), 'unsupported');
});

test('typical card fields', () => {
  const card = cardFromMap(hb1DecodeURL(vector('typical-signed').url));
  assert.equal(card.name, 'Leopold Bloom');
  assert.equal(card.company, "Freeman's Journal");
  assert.equal(card.phone, '+353871234567');
  assert.equal(card.email, 'henry.flower@example.ie');
  assert.deepEqual(card.website, { address: 'nnix.com', insecure: false });
  assert.equal(card.github, 'lbloom');
  assert.equal(card.linkedin, 'leopold-bloom');
  assert.equal(card.mastodon, 'bloom@merveilles.town');
  assert.equal(card.calendly, 'bloom/coffee');
  assert.equal(card.signal, null);
  assert.equal(hexEncode(card.personaID), '0101010101010101');
  assert.equal(card.issuedDay, 2438);
  assert.equal(card.color, 2);
  assert.equal(card.seq, 1);
  assert.equal(card.minReader, null);
  assert.equal(card.flags, 0);
  assert.equal(card.compact, false);
  assert.equal(card.alias, false);
  assert.deepEqual(card.custom, []);
});

test('maximal card fields, with the http bit moved into website.insecure', () => {
  const map = hb1DecodeURL(vector('maximal-qr-signed').url);
  const card = cardFromMap(map);
  assert.equal(map.get(0), 8);
  assert.equal(card.flags, 0);
  assert.deepEqual(card.website, { address: 'example.org/~bloom', insecure: true });
  assert.equal(card.signal.username.length, 48);
  assert.equal(card.ssh.kind, 1);
  assert.equal(card.ssh.bytes.length, 32);
  assert.equal(hexEncode(card.ssh.bytes), '404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f');
  assert.equal(card.gpgFingerprint.length, 20);
  assert.deepEqual(card.custom, [
    { label: 'Pub', value: "Davy Byrne's", kind: CustomKind.text },
    { label: 'Matrix', value: 'https://matrix.to/#/@bloom:example.ie', kind: CustomKind.url },
    { label: 'Fax', value: '+35318000000', kind: CustomKind.phone },
  ]);
  assert.equal(card.seq, 7);
  assert.equal(card.minReader, 1);
});

test('compact, alias, photo and unicode cards', () => {
  const compact = cardFromMap(hb1DecodeURL(vector('compact-two-channels').url));
  assert.equal(compact.compact, true);
  assert.equal(hexEncode(compact.keyFingerprint), 'e4f88815c8db93c8');
  assert.equal(compact.publicKey, null);
  const alias = cardFromMap(hb1DecodeURL(vector('alias-signed').url));
  assert.equal(alias.alias, true);
  assert.equal(alias.color, 9);
  const photo = cardFromMap(hb1DecodeURL(vector('file-with-photo-and-key').url));
  assert.equal(photo.photoAvailable, true);
  assert.ok(isJPEG(photo.photo));
  assert.equal(photo.gpgKey[0], 0x98);
  const nfc = cardFromMap(hb1DecodeURL(vector('unicode-nfc').url));
  const nfd = cardFromMap(hb1DecodeURL(vector('unicode-nfd').url));
  assert.equal(nfc.name, 'Zoë Blöm 水 🏳️‍🌈');
  assert.equal(nfd.name.normalize('NFC'), nfc.name);
  assert.notEqual(nfd.name, nfc.name);
});

test('foreign and future forms are refused with the right reason', () => {
  const body = vector('minimal').url.slice(HB1_URL_PREFIX.length);
  const notHatband = (text) => throwsCode(() => hb1DecodeURL(text), HB1Error, 'notHatband');
  notHatband('https://example.com/#' + body);
  notHatband('https://hatband.link/card#' + body);
  notHatband('http://hatband.link/#' + body);
  notHatband('https://www.hatband.link/#' + body);
  notHatband('https://hatband.link/#');
  notHatband('https://hatband.link/#1!!');
  notHatband('#1' + body.slice(1, 4));
  notHatband('#1' + body.slice(1) + '=A');
  throwsCode(() => hb1DecodeURL('#1' + body.slice(1, -1)), CBORError, 'truncated');
  notHatband('BEGIN:VCARD');
  notHatband('');
  notHatband('#');
  notHatband('#2' + body.slice(1));
  throwsCode(() => hb1DecodeURL('https://hatband.link/#9' + body.slice(1)), HB1Error, 'unsupportedFormat', { tag: '9' });
  throwsCode(() => hb1DecodeURL('#0' + body.slice(1)), HB1Error, 'unsupportedFormat', { tag: '0' });
  throwsCode(() => hb1DecodeURL('#8'), HB1Error, 'unsupportedFormat', { tag: '8' });
});

test('the 32 KB ceiling and non-map payloads', () => {
  const big = new Map([[16, repeat(7, 8)], [17, 0], [20, repeat(0, HB1_MAX_BYTES)]]);
  const bytes = cborEncode(big);
  throwsCode(() => hb1DecodeCBOR(bytes), HB1Error, 'tooLarge', { size: bytes.length });
  throwsCode(() => hb1DecodeURL('#1' + base32Encode(bytes)), HB1Error, 'tooLarge');
  throwsCode(() => hb1DecodeFile(Uint8Array.from([...HB1_FILE_MAGIC, ...bytes])), HB1Error, 'tooLarge');
  throwsCode(() => hb1DecodeCBOR(h('00')), CardError, 'notAMap');
  throwsCode(() => hb1DecodeCBOR(h('82 00 01')), CardError, 'notAMap');
  throwsCode(() => hb1DecodeURL('#1' + base32Encode(h('ff'))), Error, 'unsupported');
});

test('wrong shapes are errors; unknown keys and flag bits are not', () => {
  const base = hb1DecodeURL(vector('maximal-qr-signed').url);
  const withKey = (key, value) => { const m = new Map(base); m.set(key, value); return m; };
  const cases = [
    [1, 1, 'wrongType'], [16, repeat(1, 3), 'wrongLength', { expected: [8], actual: 3 }], [14, repeat(0, 31), 'wrongLength'],
    [15, repeat(0, 65), 'wrongLength'], [19, repeat(1, 1), 'wrongLength'], [12, repeat(0, 21), 'wrongLength', { expected: [20, 32], actual: 21 }],
    [9, repeat(1, 2), 'wrongLength', { expected: [48], actual: 2 }], [9, 5, 'wrongType'], [11, repeat(1, 1), 'wrongLength'],
    [13, [['only-label']], 'badCustomField'], [13, [['l', 'v', 9]], 'badCustomField'], [13, [['l', 'v', 256]], 'badCustomField'],
    [13, [['l', 'v', -1]], 'badCustomField'], [13, [['l', 1, 0]], 'badCustomField'], [13, 'x', 'wrongType'],
    [17, 2 ** 32, 'outOfRange'], [18, 256, 'outOfRange'], [17, -1, 'wrongType'], [17, 'x', 'wrongType'], [0, -1, 'wrongType'],
    [0, 2n ** 64n, 'outOfRange'], [21, 2 ** 32, 'outOfRange'], [22, 256, 'outOfRange'], [20, 'x', 'wrongType'], [23, 1, 'wrongType'],
  ];
  for (const [key, value, code, extra] of cases) throwsCode(() => cardFromMap(withKey(key, value)), CardError, code, { key, ...extra });
  const noID = new Map(base); noID.delete(16);
  throwsCode(() => cardFromMap(noID), CardError, 'missing', { key: 16 });
  const noDay = new Map(base); noDay.delete(17);
  throwsCode(() => cardFromMap(noDay), CardError, 'missing', { key: 17 });
  throwsCode(() => cardFromMap([1, 2]), CardError, 'notAMap');

  const future = withKey(99, 'future');
  future.set(0, 2 ** 40 | 0 + 1);
  future.set(0, 2 ** 40 + 1);
  const card = cardFromMap(future);
  assert.equal(card.name, 'Leopold Bloom');
  assert.equal(card.compact, true);
  assert.equal(card.flags, 2 ** 40 + 1);
  const huge = withKey(0, 2n ** 63n | 9n);
  const hugeCard = cardFromMap(huge);
  assert.equal(hugeCard.compact, true);
  assert.equal(hugeCard.website.insecure, true);
  assert.equal(hugeCard.flags, 2n ** 63n | 1n);
});
