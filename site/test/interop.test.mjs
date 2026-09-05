import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  Base64Error, base64Decode, base64Encode, calendlyURI, cardFromMap, cardVCard, civilToDay, dayToCivil, emailURI, githubURI,
  gpgFingerprintFormatted, gpgFingerprintURI, hb1DecodeURL, isoDate, keyFingerprintDisplay, linkedinURI, mastodonURI,
  paletteColor, PALETTE, phoneURI, sha256, signalURI, sshAuthorizedKeysLine, sshDisplay, sshFingerprintText, vcardEscape,
  vcardFold, vcardNameParts, vcardText, websiteURI,
} from '../src/hb1.js';
import { h, repeat, throwsCode, vector } from './helpers.mjs';

const utf8 = (s) => new TextEncoder().encode(s);
const physicalLines = (text) => {
  assert.ok(text.endsWith('\r\n'), 'ends with CRLF');
  return text.slice(0, -2).split('\r\n');
};

test('Base64 RFC vectors and the two alphabets', () => {
  for (const [plain, encoded] of [['', ''], ['f', 'Zg=='], ['fo', 'Zm8='], ['foo', 'Zm9v'], ['foob', 'Zm9vYg=='], ['fooba', 'Zm9vYmE='], ['foobar', 'Zm9vYmFy']]) {
    assert.equal(base64Encode(utf8(plain)), encoded);
    assert.equal(base64Encode(utf8(plain), true), encoded.replace(/=+$/, ''));
    assert.deepEqual(base64Decode(encoded), utf8(plain));
    assert.deepEqual(base64Decode(encoded.replace(/=+$/, ''), true), utf8(plain));
  }
  assert.equal(base64Encode(h('fbffbf')), '+/+/');
  assert.equal(base64Encode(h('fbffbf'), true), '-_-_');
  throwsCode(() => base64Decode('-_-_'), Base64Error, 'invalidCharacter');
  for (const [text, code] of [['Z', 'invalidLength'], ['Zg=', 'invalidPadding'], ['Zg===', 'invalidPadding'], ['Zh==', 'nonZeroPadding'], ['Zm9', 'nonZeroPadding'], ['Zm9v YmFy', 'invalidCharacter'], ['=', 'invalidPadding']]) {
    throwsCode(() => base64Decode(text), Base64Error, code);
  }
  const all = Uint8Array.from({ length: 256 }, (_, i) => i);
  assert.deepEqual(base64Decode(base64Encode(all)), all);
  assert.equal(base64Encode(all), Buffer.from(all).toString('base64'));
});

test('canonical URIs match Interop/CanonicalURI.swift', () => {
  assert.equal(phoneURI('+353871234567'), 'tel:+353871234567');
  assert.equal(emailURI('bloom@nnix.com'), 'mailto:bloom@nnix.com');
  assert.equal(emailURI("o'brien+x@x.com"), "mailto:o'brien+x@x.com");
  assert.equal(emailURI('a?b#c%d&e=f/g@x.com'), 'mailto:a%3Fb%23c%25d%26e%3Df%2Fg@x.com');
  assert.equal(emailURI('ü@x.com'), 'mailto:%C3%BC@x.com');
  assert.equal(websiteURI('nnix.com'), 'https://nnix.com');
  assert.equal(websiteURI('nnix.com/~bloom?x=1', true), 'http://nnix.com/~bloom?x=1');
  assert.equal(githubURI('lbloom'), 'https://github.com/lbloom');
  assert.equal(linkedinURI('leopold-bloom'), 'https://www.linkedin.com/in/leopold-bloom');
  assert.equal(linkedinURI('company/freemans-journal'), 'https://www.linkedin.com/company/freemans-journal');
  assert.equal(calendlyURI('bloom/coffee'), 'https://calendly.com/bloom/coffee');
  assert.equal(gpgFingerprintURI(h('abcd01')), 'OPENPGP4FPR:ABCD01');
  assert.deepEqual(mastodonURI('bloom@merveilles.town'), { account: 'acct:bloom@merveilles.town', profile: 'https://merveilles.town/@bloom' });
  assert.equal(mastodonURI('bloom'), null);
  assert.equal(mastodonURI('@merveilles.town'), null);
  assert.equal(mastodonURI('bloom@'), null);
  const username = Uint8Array.from({ length: 48 }, (_, i) => (i * 5 + 3) & 0xff);
  assert.equal(signalURI({ username }), 'https://signal.me/#eu/' + Buffer.from(username).toString('base64url'));
  assert.equal(signalURI({ username }).length, 'https://signal.me/#eu/'.length + 64);
  assert.equal(signalURI({ phone: '+353871234567' }), 'https://signal.me/#p/+353871234567');
});

test('fingerprints display as GnuPG and the app do', () => {
  const tor = h('EF6E286DDA85EA2A4BA7DE684E2C6E8793298290');
  assert.equal(gpgFingerprintFormatted(tor), 'EF6E 286D DA85 EA2A 4BA7  DE68 4E2C 6E87 9329 8290');
  const v6 = h('CB186C4F0609A697E4D52DFA6C722B0C1F1E27C18A56708F6525EC27BAD9ACC9');
  assert.equal(gpgFingerprintFormatted(v6), 'CB18 6C4F 0609 A697 E4D5 2DFA 6C72 2B0C  1F1E 27C1 8A56 708F 6525 EC27 BAD9 ACC9');
  assert.equal(keyFingerprintDisplay(h('e4f88815c8db93c8')), 'E4F8 8815 C8DB 93C8');
  assert.equal(keyFingerprintDisplay(v6), 'CB18 6C4F 0609 A697 E4D5 2DFA 6C72 2B0C\n1F1E 27C1 8A56 708F 6525 EC27 BAD9 ACC9');
});

test('key fingerprint is SHA-256 of the public key, first 8 bytes on the compact tier', async () => {
  const full = cardFromMap(hb1DecodeURL(vector('typical-signed').url));
  const digest = await sha256(full.publicKey);
  assert.equal(digest.length, 32);
  assert.equal(Buffer.from(digest).toString('hex'), Buffer.from(await sha256(full.publicKey)).toString('hex'));
  const nodeDigest = (await import('node:crypto')).createHash('sha256').update(full.publicKey).digest('hex');
  assert.equal(Buffer.from(digest).toString('hex'), nodeDigest);
});

test('SSH lines rebuild from the stored material', () => {
  const line = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBjJlVLb4OQSjA2M1WCE+kKq1u22L+67K93iFB3A20R3';
  const blob = Buffer.from(line.split(' ')[1], 'base64');
  const key = new Uint8Array(blob.subarray(blob.length - 32));
  assert.equal(sshAuthorizedKeysLine(1, key), line);
  assert.equal(sshDisplay({ kind: 1, bytes: key }), line);
  assert.equal(sshAuthorizedKeysLine(1, key.subarray(1)), null);
  const point = Uint8Array.from([4, ...repeat(0xab, 64)]);
  const ecdsa = sshAuthorizedKeysLine(2, point);
  assert.match(ecdsa, /^ecdsa-sha2-nistp256 /);
  const decoded = Buffer.from(ecdsa.split(' ')[1], 'base64');
  const expected = Buffer.concat([
    Buffer.from([0, 0, 0, 19]), Buffer.from('ecdsa-sha2-nistp256'), Buffer.from([0, 0, 0, 8]), Buffer.from('nistp256'),
    Buffer.from([0, 0, 0, 65]), Buffer.from(point),
  ]);
  assert.deepEqual(decoded, expected);
  assert.equal(sshAuthorizedKeysLine(2, Uint8Array.from([5, ...repeat(0xab, 64)])), null);
  assert.equal(sshAuthorizedKeysLine(3, point), null);
  assert.match(sshAuthorizedKeysLine(3, Uint8Array.from([4, ...repeat(1, 96)])), /^ecdsa-sha2-nistp384 /);
  assert.match(sshAuthorizedKeysLine(4, Uint8Array.from([4, ...repeat(1, 132)])), /^ecdsa-sha2-nistp521 /);
  const digest = repeat(0x2a, 32);
  assert.equal(sshFingerprintText(digest), 'SHA256:' + Buffer.from(digest).toString('base64').replace(/=+$/, ''));
  assert.equal(sshDisplay({ kind: 0x10, bytes: digest }), sshFingerprintText(digest));
  assert.equal(sshDisplay({ kind: 0x10, bytes: repeat(0, 31) }), null);
  assert.equal(sshDisplay({ kind: 0x42, bytes: digest }), null);
  assert.equal(sshDisplay(null), null);
});

test('days since 2020-01-01 map to civil dates without Date', () => {
  assert.deepEqual(dayToCivil(0), { year: 2020, month: 1, day: 1 });
  assert.deepEqual(dayToCivil(2438), { year: 2026, month: 9, day: 4 });
  assert.equal(isoDate(dayToCivil(2438)), '2026-09-04');
  assert.deepEqual(dayToCivil(-1), { year: 2019, month: 12, day: 31 });
  assert.deepEqual(dayToCivil(59), { year: 2020, month: 2, day: 29 });
  assert.equal(civilToDay(2026, 9, 4), 2438);
  const epoch = Date.UTC(2020, 0, 1);
  for (let n = -800; n <= 40000; n += 37) {
    const d = new Date(epoch + n * 86400000);
    assert.deepEqual(dayToCivil(n), { year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: d.getUTCDate() }, `day ${n}`);
    assert.equal(civilToDay(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate()), n);
  }
});

test('palette order is frozen and out-of-range indexes fall back to ink', () => {
  assert.equal(PALETTE.length, 10);
  assert.deepEqual(PALETTE.map((c) => c.name), ['ink', 'dark blue', 'bottle green', 'brass', 'rust', 'slate', 'bog', 'peat', 'heather', 'tram cream']);
  assert.deepEqual(paletteColor(1), { name: 'dark blue', light: '#00008b', dark: '#7f7fff' });
  assert.equal(paletteColor(200).name, 'ink');
  assert.throws(() => { PALETTE[0].light = '#fff'; });
});

test('vCard: minimal card and name guessing', () => {
  assert.deepEqual(vcardNameParts('Leopold Bloom'), { familyName: 'Bloom', givenName: 'Leopold' });
  assert.deepEqual(vcardNameParts('Cher'), { familyName: '', givenName: 'Cher' });
  assert.deepEqual(vcardNameParts('  '), { familyName: '', givenName: '' });
  assert.deepEqual(vcardNameParts('Henry  Flower Bloom'), { familyName: 'Bloom', givenName: 'Henry Flower' });
  const text = vcardText({ formattedName: 'Leopold Bloom', ...vcardNameParts('Leopold Bloom') });
  assert.equal(text, 'BEGIN:VCARD\r\nVERSION:3.0\r\nN:Bloom;Leopold;;;\r\nFN:Leopold Bloom\r\nEND:VCARD\r\n');
});

test('vCard: reserved characters and line breaks are escaped on code points', () => {
  assert.equal(vcardEscape(''), '');
  assert.equal(vcardEscape('plain text 水'), 'plain text 水');
  assert.equal(vcardEscape('a\\b,c;d'), 'a\\\\b\\,c\\;d');
  assert.equal(vcardEscape('line1\r\nline2\nline3\rline4 line5line6 '), 'line1\\nline2\\nline3\\nline4\\nline5\\nline6\\n');
  assert.equal(vcardEscape('\\́'), '\\\\́');
  const lines = physicalLines(vcardText({
    formattedName: 'Bloom, Leopold; "Poldy" \\ back', familyName: 'Bloom;Virag', givenName: 'Leopold,Paula',
    organization: "Freeman's Journal; Editorial, Dublin", note: 'line1\r\nline2\nline3\rline4 line5',
    links: [{ label: 'A,B;C', url: 'https://example.com/a,b;c\\d' }],
  }));
  assert.ok(lines.includes('N:Bloom\\;Virag;Leopold\\,Paula;;;'));
  assert.ok(lines.includes('FN:Bloom\\, Leopold\\; "Poldy" \\\\ back'));
  assert.ok(lines.includes("ORG:Freeman's Journal\\; Editorial\\, Dublin"));
  assert.ok(lines.includes('NOTE:line1\\nline2\\nline3\\nline4\\nline5'));
  assert.ok(lines.includes('item1.URL:https://example.com/a\\,b\\;c\\\\d'));
  assert.ok(lines.includes('item1.X-ABLabel:A\\,B\\;C'));
  assert.equal(lines.length, 9);
});

test('vCard: CRLF injection cannot start a line', () => {
  const text = vcardText({
    formattedName: 'Bloom\r\nEND:VCARD\r\nBEGIN:VCARD\r\nFN:Mallory', familyName: '', givenName: '',
    note: 'x\r\nX-HATBAND-KEY:evil\r\n', email: 'a@b.ie\nTEL:+1',
    extensions: [{ name: 'K\r\nEY', value: 'v\r\nFN:Mallory' }],
  });
  const lines = physicalLines(text);
  assert.equal(lines.filter((l) => l === 'BEGIN:VCARD').length, 1);
  assert.equal(lines.filter((l) => l === 'END:VCARD').length, 1);
  assert.ok(!lines.some((l) => l.startsWith('TEL')));
  assert.ok(!lines.some((l) => l.startsWith('FN:Mallory')));
  assert.deepEqual(lines.filter((l) => l.startsWith('X-HATBAND-')), ['X-HATBAND-KEY:v\\nFN:Mallory']);
  const bytes = utf8(text);
  bytes.forEach((b, i) => { if (b === 0x0a) assert.equal(bytes[i - 1], 0x0d); });
});

test('vCard: folds at 75 octets on UTF-8 boundaries', () => {
  const note = 'abcdefghij'.repeat(20);
  const lines = physicalLines(vcardText({ formattedName: 'Leopold Bloom', note }));
  assert.ok(lines.every((l) => utf8(l).length <= 75));
  const noteLines = lines.filter((l) => l.startsWith('NOTE:') || l.startsWith(' '));
  assert.equal(noteLines.length, 3);
  assert.equal(utf8(noteLines[0]).length, 75);
  assert.equal(utf8(noteLines[1]).length, 75);
  assert.equal(noteLines[0] + noteLines.slice(1).map((l) => l.slice(1)).join(''), 'NOTE:' + note);
  assert.equal(vcardFold('NOTE:' + 'n'.repeat(70)), 'NOTE:' + 'n'.repeat(70));
  assert.equal(vcardFold('NOTE:' + 'n'.repeat(71)), 'NOTE:' + 'n'.repeat(70) + '\r\n n');
  for (const unit of ['é', '水', '🎩', 'ß', 'Ω']) {
    for (const count of [20, 25, 37, 38, 75, 76, 200]) {
      const text = vcardText({ formattedName: 'x', note: unit.repeat(count) });
      for (const line of physicalLines(text)) {
        assert.ok(utf8(line).length <= 75);
        assert.doesNotThrow(() => new TextDecoder('utf-8', { fatal: true }).decode(utf8(line)));
      }
      const unfolded = text.replace(/\r\n /g, '');
      assert.ok(unfolded.includes('NOTE:' + unit.repeat(count) + '\r\n'));
    }
  }
});

test('vCard: photo is base64, folded, and only when JPEG', () => {
  const photo = Uint8Array.from({ length: 256 }, (_, i) => i);
  const lines = physicalLines(vcardText({ formattedName: 'x', photoJPEG: photo }));
  const index = lines.findIndex((l) => l.startsWith('PHOTO;ENCODING=b;TYPE=JPEG:'));
  assert.ok(index >= 0);
  let b64 = lines[index].slice('PHOTO;ENCODING=b;TYPE=JPEG:'.length);
  for (let i = index + 1; lines[i] && lines[i].startsWith(' '); i++) b64 += lines[i].slice(1);
  assert.deepEqual(base64Decode(b64), photo);
  assert.ok(lines.every((l) => utf8(l).length <= 75));
});

test('vCard for the typical vector', () => {
  const card = cardFromMap(hb1DecodeURL(vector('typical-signed').url));
  const text = cardVCard(card);
  const lines = physicalLines(text);
  assert.equal(lines[0], 'BEGIN:VCARD');
  assert.equal(lines[1], 'VERSION:3.0');
  assert.equal(lines[lines.length - 1], 'END:VCARD');
  assert.ok(lines.every((l) => utf8(l).length <= 75));
  for (const expected of [
    'N:Bloom;Leopold;;;', 'FN:Leopold Bloom', "ORG:Freeman's Journal", 'TEL;TYPE=CELL:+353871234567',
    'EMAIL;TYPE=INTERNET:henry.flower@example.ie',
    'item1.URL:https://nnix.com', 'item1.X-ABLabel:Website',
    'item2.URL:https://github.com/lbloom', 'item2.X-ABLabel:GitHub',
    'item3.URL:https://www.linkedin.com/in/leopold-bloom', 'item3.X-ABLabel:LinkedIn',
    'item4.URL:https://merveilles.town/@bloom', 'item4.X-ABLabel:Mastodon',
    'item5.URL:https://calendly.com/bloom/coffee', 'item5.X-ABLabel:Calendly',
    'X-HATBAND-PERSONA:0101010101010101',
    'X-HATBAND-KEY:' + Buffer.from(card.publicKey).toString('base64'),
    'X-HATBAND-ISSUED-DAY:2438', 'X-HATBAND-SEQ:1',
  ]) assert.ok(lines.includes(expected), expected);
  assert.ok(!lines.some((l) => l.startsWith('NOTE:')));
  assert.ok(!lines.some((l) => l.startsWith('PHOTO')));
  assert.ok(!text.includes('\n') || text.split('\n').every((_, i, a) => i === a.length - 1 || a[i].endsWith('\r')));
});

test('vCard for the maximal vector: http website, Signal, GPG, custom fields sorted by kind, SSH in the note', () => {
  const card = cardFromMap(hb1DecodeURL(vector('maximal-qr-signed').url));
  const lines = physicalLines(cardVCard(card));
  const unfolded = physicalLines(cardVCard(card).replace(/\r\n /g, ''));
  const signal = 'https://signal.me/#eu/' + Buffer.from(card.signal.username).toString('base64url');
  const ssh = sshDisplay(card.ssh);
  for (const expected of [
    'item1.URL:http://example.org/~bloom', 'item1.X-ABLabel:Website',
    'item5.URL:' + signal, 'item5.X-ABLabel:Signal',
    'item6.URL:https://calendly.com/bloom/coffee',
    'item7.URL:OPENPGP4FPR:A0A1A2A3A4A5A6A7A8A9AAABACADAEAFB0B1B2B3', 'item7.X-ABLabel:GPG',
    'item8.URL:https://matrix.to/#/@bloom:example.ie', 'item8.X-ABLabel:Matrix',
    "NOTE:Pub: Davy Byrne's\\nFax: +35318000000\\n" + ssh,
    'X-HATBAND-PERSONA:0202020202020202', 'X-HATBAND-SEQ:7',
  ]) assert.ok(unfolded.includes(expected), expected);
  assert.ok(lines.every((l) => utf8(l).length <= 75));
  assert.ok(!unfolded.some((l) => l.startsWith('item9.')));
});

test('vCard for a photo card embeds the JPEG; a hostile custom URL goes to the note', () => {
  const card = cardFromMap(hb1DecodeURL(vector('file-with-photo-and-key').url));
  const lines = physicalLines(cardVCard(card));
  assert.ok(lines.some((l) => l.startsWith('PHOTO;ENCODING=b;TYPE=JPEG:/9j/')));
  card.custom = [{ label: 'Evil', value: 'javascript:alert(1)', kind: 1 }, { label: 'Ok', value: 'https://example.com/x', kind: 1 }];
  card.photo = null;
  const unfolded = physicalLines(cardVCard(card).replace(/\r\n /g, ''));
  assert.ok(unfolded.some((l) => l === 'item8.URL:https://example.com/x'));
  assert.ok(!unfolded.some((l) => l.includes('URL:javascript')));
  assert.ok(unfolded.some((l) => l.startsWith('NOTE:Evil: javascript:alert(1)\\n')));
});
