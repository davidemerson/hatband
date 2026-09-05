/* vCard 3.0 output against Interop/VCard.swift: escaping on code points,
   folding at 75 octets, CRLF only, and a reader written from RFC 2425/2426
   that must recover every value. */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CustomKind, base64Decode, cardFromMap, cardVCard, hb1DecodeURL, hb1URL, urlVerdict, vcardEscape, vcardFold, vcardNameParts, vcardPropertyName, vcardText } from '../src/hb1.js';
import { repeat, vector } from './helpers.mjs';
import { SplitMix64, hostileText, hostileURLs } from './review-helpers.mjs';

const utf8 = (s) => Buffer.from(s, 'utf8');
const physical = (text) => { assert.ok(text.endsWith('\r\n')); return text.slice(0, -2).split('\r\n'); };

/** RFC 2425 §5.8.1 unfolding and RFC 2426 §2.4.2 unescaping, as a reader would. */
function unfold(text) {
  const logical = [];
  for (const line of physical(text)) {
    if ((line.startsWith(' ') || line.startsWith('\t')) && logical.length) logical[logical.length - 1] += line.slice(1);
    else logical.push(line);
  }
  return logical;
}
const unescape = (value) => value.replace(/\\(.)/gsu, (_, c) => (c === 'n' || c === 'N' ? '\n' : c));
const splitComponents = (value) => {
  const parts = [];
  let current = '';
  for (let i = 0; i < value.length; i++) {
    if (value[i] === '\\') { current += value[i] + (value[i + 1] ?? ''); i++; }
    else if (value[i] === ';') { parts.push(current); current = ''; }
    else current += value[i];
  }
  parts.push(current);
  return parts.map(unescape);
};
function parse(text) {
  const logical = unfold(text);
  assert.equal(logical[0], 'BEGIN:VCARD');
  assert.equal(logical[1], 'VERSION:3.0');
  assert.equal(logical[logical.length - 1], 'END:VCARD');
  const card = { links: [], extensions: [] };
  const labels = {};
  const urls = [];
  for (const line of logical.slice(2, -1)) {
    const colon = line.indexOf(':');
    assert.ok(colon > 0, line);
    const head = line.slice(0, colon).split(';')[0].toUpperCase();
    const value = line.slice(colon + 1);
    const [group, name] = head.includes('.') ? head.split('.', 2) : ['', head];
    switch (name) {
      case 'N': [card.familyName, card.givenName] = splitComponents(value); break;
      case 'FN': card.formattedName = unescape(value); break;
      case 'ORG': card.organization = splitComponents(value)[0]; break;
      case 'TEL': card.phone ??= unescape(value); break;
      case 'EMAIL': card.email ??= unescape(value); break;
      case 'URL': urls.push([group, unescape(value)]); break;
      case 'X-ABLABEL': labels[group] = unescape(value); break;
      case 'NOTE': card.note = unescape(value); break;
      case 'PHOTO': card.photoJPEG = base64Decode(value); break;
      default:
        assert.ok(name.startsWith('X-HATBAND-'), name);
        card.extensions.push({ name: name.slice('X-HATBAND-'.length), value: unescape(value) });
    }
  }
  card.links = urls.map(([group, url]) => ({ label: labels[group] ?? '', url }));
  return card;
}
const normalizedBreaks = (s) => s.replace(/\r\n|[\r\n\u0085\u2028\u2029]/g, '\n');

test('escaping is on code points, so a reserved character followed by a combining mark is still escaped', () => {
  // Swift's `escape` switches on Characters (grapheme clusters) and misses these; the page does not.
  for (const [input, expected] of [['\\\u0301', '\\\\\u0301'], [',\u0301', '\\,\u0301'], [';\u0301', '\\;\u0301'], ['a;\u0301b', 'a\\;\u0301b'], ['\n\u0301', '\\n\u0301'], ['\r\u0301\n', '\\n\u0301\\n']]) {
    assert.equal(vcardEscape(input), expected, JSON.stringify(input));
  }
  assert.equal(vcardEscape('a\\b,c;d'), 'a\\\\b\\,c\\;d');
  assert.equal(vcardEscape('\r\n\n\r\u0085\u2028\u2029'), '\\n'.repeat(6));
  assert.equal(vcardEscape('\r\r\n'), '\\n\\n');
  assert.equal(vcardEscape('\u000b\u000c'), '\u000b\u000c', 'VT and FF are not line breaks to vCard');
  assert.equal(vcardEscape(''), '');
  assert.equal(vcardEscape('plain text 水'), 'plain text 水');
  assert.equal(vcardPropertyName('a:b;c.d,e f\r\ng'), 'ABCDEFG');
  assert.equal(vcardPropertyName('item1.URL'), 'ITEM1URL');
  assert.equal(vcardPropertyName('ß-ﬁ'), 'SS-FI');
  assert.equal(vcardPropertyName('水'), '');
  assert.deepEqual(vcardNameParts('Leopold\u0085Bloom'), { familyName: 'Bloom', givenName: 'Leopold' }, 'White_Space splits, as Character.isWhitespace does');
  assert.deepEqual(vcardNameParts('Leopold\ufeffBloom'), { familyName: '', givenName: 'Leopold\ufeffBloom' }, 'a BOM is not White_Space');
});

test('folds: an escape split across the boundary survives, a four-byte scalar moves whole, a mark may start a continuation', () => {
  for (const [suffix, plain] of [[',', ','], [';', ';'], ['\\', '\\'], ['\n', '\n']]) {
    const text = vcardText({ formattedName: 'x', note: 'a'.repeat(69) + suffix + 'tail' });
    const lines = physical(text);
    const note = lines.findIndex((l) => l.startsWith('NOTE:'));
    assert.equal(utf8(lines[note]).length, 75);
    assert.ok(lines[note].endsWith('\\'));
    assert.ok(lines[note + 1].startsWith(' '));
    assert.equal(parse(text).note, 'a'.repeat(69) + plain + 'tail');
  }
  const hat = vcardText({ formattedName: 'x', note: 'a'.repeat(68) + '🎩b' });
  assert.ok(physical(hat).some((l) => l.startsWith('NOTE:') && utf8(l).length === 73));
  assert.ok(physical(hat).includes(' 🎩b'));
  assert.equal(parse(hat).note, 'a'.repeat(68) + '🎩b');
  for (const note of ['a'.repeat(69) + 'e\u0301x', 'a'.repeat(66) + '🏳\ufe0f\u200d🌈', 'a'.repeat(66) + '👨\u200d👩\u200d👧']) {
    const text = vcardText({ formattedName: 'x', note });
    const lines = physical(text);
    assert.ok(lines.every((l) => utf8(l).length <= 75));
    assert.ok(lines.some((l) => l.startsWith(' ')));
    assert.equal(parse(text).note, note);
  }
  assert.equal(vcardFold('NOTE:' + 'n'.repeat(70)), 'NOTE:' + 'n'.repeat(70));
  assert.equal(vcardFold('NOTE:' + 'n'.repeat(71)), 'NOTE:' + 'n'.repeat(70) + '\r\n n');
  const mixed = vcardText({ formattedName: 'x', note: Array.from({ length: 120 }, (_, i) => (i % 3 === 0 ? '水' : i % 3 === 1 ? 'é' : 'a')).join('') });
  assert.ok(physical(mixed).every((l) => utf8(l).length <= 75));
  assert.ok(physical(mixed).filter((l) => l.startsWith(' ')).length >= 3);
});

test('every line-break character, mixed with other controls, ends up inside one value', () => {
  const breaks = ['\r', '\n', '\r\n', '\u0085', '\u2028', '\u2029', '\u000b', '\u000c', '\r\u000b\n', '\n\u0301', '\r\u200d\n'];
  for (const br of breaks) {
    const v = {
      formattedName: 'Bloom' + br + 'FN:Mallory' + br + 'END:VCARD' + br + 'BEGIN:VCARD', familyName: '', givenName: '',
      note: br + 'X-HATBAND-KEY:evil' + br,
      links: [{ label: 'l' + br + 'item9.URL:https://evil', url: 'https://x' + br + 'PHOTO;ENCODING=b:AAAA' }],
      extensions: [{ name: 'K' + br + 'EY', value: 'v' + br + 'TEL:+1' }],
    };
    const text = vcardText(v);
    const lines = physical(text);
    assert.equal(lines.filter((l) => l === 'BEGIN:VCARD').length, 1);
    assert.equal(lines.filter((l) => l === 'END:VCARD').length, 1);
    assert.equal(lines.filter((l) => l.startsWith('FN:')).length, 1);
    assert.ok(!lines.some((l) => /^(TEL|PHOTO|item9|X-HATBAND-KEY:evil)/.test(l)));
    assert.equal(lines.filter((l) => l.startsWith('X-HATBAND-')).length, 1);
    const parsed = parse(text);
    assert.equal(parsed.links.length, 1);
    assert.deepEqual(parsed.extensions.map((e) => e.name), ['KEY']);
    assert.equal(parsed.photoJPEG, undefined);
    assert.equal(parsed.phone, undefined);
    assert.equal(parsed.formattedName, normalizedBreaks(v.formattedName));
  }
});

test('600 fuzzed cards round-trip through a reader: CRLF only, 75 octets, one envelope, every value recovered', () => {
  const rng = new SplitMix64(0xca4dn);
  const fragments = ['a', 'Z', '0', '-', '.', '/', ':', ';', ',', '\\', '\\n', '\\N', ' ', '\t', '\r', '\n', '\r\n', '\u0085', '\u2028', '\u2029', '\u0000', '\u007f', '\u00a0', '\u200b', '\u202e', '\ufeff',
    'é', 'ß', 'İ', '水', '🎩', '\u{1f1ee}\u{1f1ea}', 'ﬁ', 'Ｅ', '<', '>', '"', "'", '[', ']', '(', ')', '{', '}', '|', '^', '`', '~', '*', '!', '$', '%', '=', '==',
    'BEGIN:VCARD', 'END:VCARD', 'VERSION:3.0', 'N:', 'FN:', 'PHOTO;ENCODING=b:', 'item1.URL:', 'X-HATBAND-', 'https', 'mailto', 'tel'];
  const noMarks = fragments.filter((f) => !/\p{Grapheme_Extend}/u.test(f));
  const fuzz = (max = 12) => { let s = ''; for (let i = rng.below(max); i > 0; i--) s += rng.pick(noMarks); return s; };
  for (let i = 0; i < 600; i++) {
    const v = { formattedName: fuzz(), familyName: fuzz(4), givenName: fuzz(4), links: [], extensions: [] };
    if (rng.below(2) === 0) v.organization = fuzz();
    if (rng.below(2) === 0) v.phone = fuzz();
    if (rng.below(2) === 0) v.email = fuzz();
    if (rng.below(2) === 0) v.note = fuzz(60);
    if (rng.below(3) === 0) v.photoJPEG = rng.bytes(rng.below(400));
    for (let n = rng.below(4); n > 0; n--) v.links.push({ label: fuzz(), url: fuzz() });
    for (let n = rng.below(4); n > 0; n--) v.extensions.push({ name: fuzz(), value: fuzz() });
    const text = vcardText(v);
    const bytes = utf8(text);
    for (let j = 0; j < bytes.length; j++) {
      if (bytes[j] === 0x0a) assert.equal(bytes[j - 1], 0x0d);
      if (bytes[j] === 0x0d) assert.equal(bytes[j + 1], 0x0a);
    }
    const lines = physical(text);
    assert.ok(lines.every((l) => utf8(l).length <= 75));
    assert.ok(lines.every((l) => { try { new TextDecoder('utf-8', { fatal: true }).decode(utf8(l)); return true; } catch { return false; } }));
    assert.equal(lines.filter((l) => /^(BEGIN|END):VCARD$/i.test(l)).length, 2);
    assert.ok(!lines.some((l) => l === ' '));
    const parsed = parse(text);
    assert.equal(parsed.formattedName, normalizedBreaks(v.formattedName));
    assert.equal(parsed.familyName, normalizedBreaks(v.familyName));
    assert.equal(parsed.givenName, normalizedBreaks(v.givenName));
    if (v.organization != null) assert.equal(parsed.organization, normalizedBreaks(v.organization));
    if (v.phone != null) assert.equal(parsed.phone, normalizedBreaks(v.phone));
    if (v.email != null) assert.equal(parsed.email, normalizedBreaks(v.email));
    if (v.note != null) assert.equal(parsed.note, normalizedBreaks(v.note));
    if (v.photoJPEG) assert.deepEqual(parsed.photoJPEG, v.photoJPEG);
    assert.deepEqual(parsed.links, v.links.map((l) => ({ label: normalizedBreaks(l.label), url: normalizedBreaks(l.url) })));
    assert.deepEqual(parsed.extensions, v.extensions.map((e) => ({ name: vcardPropertyName(e.name), value: normalizedBreaks(e.value) })));
  }
});

test('cardVCard: a rejected channel goes to the note as text, every URL line passes the allow-list, the maximal card stays under 32 KB', () => {
  const map = new Map([[1, 'Leopold Paula Bloom '.repeat(3)], [2, "Freeman's Journal; ".repeat(4)], [3, '+353871234567'], [4, 'a'.repeat(64) + '@' + 'b'.repeat(63) + '.ie'],
    [5, 'evil.example/"><script>'], [6, 'lbloom'], [7, 'leopold' + '\u202e'], [8, 'bloom@merveilles.town'], [10, 'bloom/coffee'],
    [12, repeat(0xab, 20)], [11, Uint8Array.from([1, ...repeat(0x40, 32)])],
    [13, [...hostileURLs.slice(0, 32).map((u, i) => ['Link ' + i, u, CustomKind.url]), ...hostileText.slice(0, 8).map((t, i) => ['Text ' + i, t, CustomKind.text])]],
    [16, repeat(2, 8)], [17, 2438], [20, Uint8Array.from([0xff, 0xd8, ...repeat(0x11, 12286)])], [21, 7]]);
  const card = cardFromMap(hb1DecodeURL(hb1URL(map)));
  const text = cardVCard(card);
  assert.ok(utf8(text).length < 32768);
  const lines = physical(text);
  assert.ok(lines.every((l) => utf8(l).length <= 75));
  const parsed = parse(text);
  for (const link of parsed.links) {
    assert.notEqual(urlVerdict(link.url).kind, 'reject', link.url);
    assert.ok(!/^(javascript|data|vbscript|file):/i.test(link.url));
  }
  assert.ok(parsed.note.includes('Website: evil.example/"><script>'));
  assert.ok(parsed.note.includes('LinkedIn: leopold\u202e'));
  assert.ok(parsed.note.includes('ssh-ed25519 '));
  assert.ok(parsed.note.includes('Link 0: javascript:alert(1)'));
  assert.ok(parsed.links.some((l) => l.url === 'https://github.com/lbloom' && l.label === 'GitHub'));
  assert.ok(parsed.links.some((l) => l.url === 'OPENPGP4FPR:' + 'AB'.repeat(20) && l.label === 'GPG'));
  assert.deepEqual(parsed.photoJPEG, card.photo);
  assert.deepEqual(parsed.extensions.map((e) => e.name), ['PERSONA', 'ISSUED-DAY', 'SEQ']);
  assert.equal(parsed.extensions[0].value, '0202020202020202');
  const typical = cardFromMap(hb1DecodeURL(vector('typical-signed').url));
  const t = parse(cardVCard(typical));
  assert.equal(t.formattedName, 'Leopold Bloom');
  assert.equal(t.familyName, 'Bloom');
  assert.equal(t.givenName, 'Leopold');
  assert.deepEqual(t.extensions.map((e) => e.name), ['PERSONA', 'KEY', 'ISSUED-DAY', 'SEQ']);
  assert.equal(t.extensions[1].value, Buffer.from(typical.publicKey).toString('base64'));
});
