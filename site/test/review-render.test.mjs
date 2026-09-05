/* Injection through every field and every custom kind, bidi and invisible
   characters, photos that are not JPEG, oversized payloads, the error state,
   and what the page touches in the browser. */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  CustomKind, HB1_MAX_BYTES, HB1_URL_PREFIX, base32Encode, base64Decode, cardFromMap, cborEncode, hb1DecodeURL, hb1URL, hexEncode, isTappable,
  textProblem, urlVerdict,
} from '../src/hb1.js';
import { errorMessage, main, renderCard, vcardFileName } from '../src/page.js';
import { Document, elements, makeWindow, serialize, texts } from './dom.mjs';
import { repeat, vector } from './helpers.mjs';
import { RLO, SplitMix64, ZWSP, hostileEmails, hostileKeys, hostilePhones, hostileText, hostileURLs } from './review-helpers.mjs';

const doc = () => new Document();
const links = (root) => elements(root).filter((e) => e.tagName === 'A');
const byClass = (root, name) => elements(root).filter((e) => e.classList.contains(name));
const run = async (options) => { const win = makeWindow(options); await main(win); return { win, root: win.document.getElementById('app') }; };
const cardFrom = (entries) => cardFromMap(hb1DecodeURL(hb1URL(new Map([[16, repeat(9, 8)], [17, 2438], ...entries]))));
const style = readFileSync(new URL('../src/style.css', import.meta.url), 'utf8');

const ALLOWED_TAGS = new Set(['ARTICLE', 'DIV', 'HEADER', 'IMG', 'H1', 'SPAN', 'P', 'UL', 'LI', 'A', 'CODE', 'BUTTON']);
const ALLOWED_ATTRIBUTES = new Set(['class', 'href', 'rel', 'download', 'src', 'alt', 'title', 'type']);
const HREF = /^(https:\/\/|http:\/\/|mailto:|tel:\+|data:text\/vcard;charset=utf-8,)/i;

/** What every rendered card must satisfy, whatever went into it. */
function audit(article, card) {
  for (const e of elements(article)) {
    assert.ok(ALLOWED_TAGS.has(e.tagName), e.tagName);
    for (const [name, value] of e.attributes) {
      assert.ok(ALLOWED_ATTRIBUTES.has(name), name);
      assert.ok(!name.startsWith('on'));
      if (name === 'href') {
        assert.match(value, HREF);
        if (!value.startsWith('data:')) {
          assert.ok(isTappable(value), value);
          assert.notEqual(urlVerdict(value).kind, 'reject', value);
          assert.ok(!/[\s<>"\\]/.test(value), value);
          if (!value.startsWith('https://hatband.link/')) assert.equal(e.getAttribute('rel'), 'noreferrer noopener', value);
        }
      }
      if (name === 'src') {
        assert.ok(value.startsWith('data:image/jpeg;base64,'), value);
        assert.deepEqual(base64Decode(value.slice('data:image/jpeg;base64,'.length)), card.photo);
      }
      if (name === 'download') assert.match(value, /^[^/\\:*?"<>|\u0000-\u001f\u007f-\u009f\u202a-\u202e]{1,60}\.vcf$/u);
      if (name === 'title' || name === 'type' || name === 'rel' || name === 'class') assert.ok(!/[<>"]/.test(value));
    }
  }
  const html = serialize(article);
  assert.ok(!/<(script|img(?! class="photo" src="data:image\/jpeg;base64,)|svg|iframe|object|embed|style|link|base|form|meta)[\s>/]/i.test(html), html.slice(0, 200));
  const vcf = decodeURIComponent(links(article).find((a) => a.getAttribute('download')).getAttribute('href').split(',')[1]);
  const logical = vcf.replace(/\r\n[ \t]/g, '').split('\r\n');
  assert.equal(logical[0], 'BEGIN:VCARD');
  assert.equal(logical[logical.length - 2], 'END:VCARD');
  assert.equal(logical.filter((l) => /^(BEGIN|END):VCARD$/i.test(l)).length, 2);
  for (const line of logical.slice(1, -2)) {
    assert.ok(line.includes(':'), line);
    const m = /^(?:item\d+\.)?URL:(.*)$/.exec(line);
    if (m) assert.notEqual(urlVerdict(m[1].replace(/\\([\\,;])/g, '$1')).kind, 'reject', line);
    assert.ok(!/^(item\d+\.)?(URL|EMAIL|TEL):(javascript|data|vbscript):/i.test(line), line);
  }
  return { html, vcf, logical };
}

test('every hostile text, in every text field and custom kind, renders as text with no sink reached', () => {
  const rng = new SplitMix64(0x5853535n);
  const pools = { [CustomKind.text]: hostileText, [CustomKind.url]: hostileURLs, [CustomKind.email]: hostileEmails, [CustomKind.phone]: hostilePhones, [CustomKind.key]: hostileKeys };
  let rendered = 0;
  let tappable = 0;
  const fields = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  for (let i = 0; i < 400; i++) {
    const entries = [];
    const expectedTexts = [];
    for (const key of fields) {
      if (rng.below(3) === 0) continue;
      const pool = key === 3 || key === 9 ? hostilePhones : key === 4 ? hostileEmails : key === 5 ? [...hostileURLs, ...hostileText] : hostileText;
      const value = rng.pick(pool);
      entries.push([key, value]);
      if (key === 9 && rng.below(2) === 0) entries[entries.length - 1] = [9, rng.bytes(48)];
      else expectedTexts.push(value);
    }
    const custom = [];
    for (let n = rng.below(6); n > 0; n--) {
      const kind = rng.below(5);
      const label = rng.pick(hostileText);
      const value = rng.pick(pools[kind]);
      custom.push([label, value, kind]);
      expectedTexts.push(label, value);
    }
    if (custom.length) entries.push([13, custom]);
    if (rng.below(2) === 0) entries.push([0, Number(rng.below(8))]);
    if (rng.below(3) === 0) entries.push([12, repeat(0xab, rng.below(2) ? 20 : 32)]);
    if (rng.below(3) === 0) entries.push([11, Uint8Array.from([1, ...rng.bytes(32)])]);
    if (rng.below(3) === 0) entries.push([20, Uint8Array.from([0xff, 0xd8, ...rng.bytes(rng.below(200))])]);
    entries.push([18, rng.below(256)]);
    const card = cardFrom(entries);
    const article = renderCard(doc(), card, { signature: rng.pick(['none', 'verified', 'invalid', 'unsupported']), keyFingerprint: rng.below(2) ? repeat(1, 32) : null, url: 'https://hatband.link/#1X', navigator: {} });
    audit(article, card);
    const text = texts(article);
    for (const expected of expectedTexts) {
      if (expected === '' || key9Phone(expected)) continue;
      assert.ok(text.includes(expected), JSON.stringify(expected));
    }
    tappable += links(article).length - 2;
    rendered++;
  }
  assert.equal(rendered, 400);
  assert.ok(tappable > 0);
  function key9Phone() { return false; }
});

test('URL, email and phone kinds: exactly the allow-list decides, and the host is printed beside every link', () => {
  for (const value of hostileURLs) {
    const article = renderCard(doc(), cardFrom([[13, [['x', value, CustomKind.url]]]]), {});
    const custom = byClass(article, 'custom')[0];
    const a = links(custom);
    const verdict = urlVerdict(value);
    if (isTappable(value)) {
      assert.equal(a.length, 1, value);
      assert.equal(a[0].getAttribute('href'), value);
      assert.equal(a[0].getAttribute('rel'), 'noreferrer noopener');
      const domain = byClass(custom, 'domain');
      if (/^https?:/i.test(value)) {
        assert.equal(domain.length, 1, value);
        assert.equal(domain[0].textContent, /^https?:\/\/([^/?#]+)/i.exec(value)[1].toLowerCase());
      }
      if (verdict.kind === 'warning') assert.equal(byClass(custom, 'warn')[0].textContent, verdict.message);
    } else {
      assert.equal(a.length, 0, value);
      assert.equal(serialize(custom).includes('href'), false, value);
      assert.ok(texts(custom).includes(value), value);
    }
  }
  for (const value of hostileEmails) {
    const article = renderCard(doc(), cardFrom([[4, value], [13, [['e', value, CustomKind.email]]]]), {});
    for (const a of links(article).filter((l) => l.getAttribute('href').startsWith('mailto:'))) {
      const href = a.getAttribute('href');
      assert.ok(isTappable(href), href);
      assert.ok(!/[\r\n\s"<>]/.test(href), href);
      assert.ok(!/%0d|%0a/i.test(href) || urlVerdict(href).kind !== 'reject', href);
    }
  }
  for (const value of hostilePhones) {
    const article = renderCard(doc(), cardFrom([[3, value], [13, [['p', value, CustomKind.phone]]]]), {});
    for (const a of links(article).filter((l) => l.getAttribute('href').startsWith('tel:'))) {
      assert.match(a.getAttribute('href'), /^tel:\+[1-9][0-9.()-]{1,}$/);
    }
    const expectedLinks = isTappable('tel:' + value) ? 2 : 0;
    assert.equal(links(article).filter((l) => l.getAttribute('href').startsWith('tel:')).length, expectedLinks, value);
  }
});

test('a bidi override in a custom label cannot reorder the host printed beside the link', () => {
  const card = cardFrom([[13, [[RLO, 'https://moc.buhtig/', CustomKind.url], [RLO + 'etisbew', 'https://moc.buhtig/x', CustomKind.url]]]]);
  const article = renderCard(doc(), card, {});
  const rows = elements(byClass(article, 'custom')[0]).filter((e) => e.tagName === 'LI');
  assert.equal(rows.length, 2);
  for (const row of rows) {
    const [label, a, domain] = row.children;
    assert.equal(label.className, 'label');
    assert.ok(label.textContent.includes(RLO), 'the label is shown as it came');
    assert.equal(a.tagName, 'A');
    assert.equal(domain.className, 'domain');
    assert.equal(domain.textContent, 'moc.buhtig');
    assert.ok(row.children.every((e) => e.parentNode === row), 'label, link and host are sibling elements, each its own bidi isolate');
  }
  // The isolation is CSS: every child of a card row is its own bidi paragraph, so an
  // unterminated override in the label ends at the label.
  assert.match(style, /\.card li > \* \{[^}]*unicode-bidi: isolate/);
});

test('bidi and invisible characters in hosts and handles make the row plain text, never a link', () => {
  const cases = [
    [5, RLO + 'moc.buhtig'], [5, 'moc.buhtig' + RLO], [5, 'github' + ZWSP + '.com'], [5, 'gіthub.com'], [5, 'github.com/\u202e'],
    [6, 'lbloom' + RLO], [6, 'lb' + ZWSP + 'loom'], [7, 'leopold' + RLO], [8, 'bloom@merveilles.town' + ZWSP], [8, 'bloom@' + RLO + 'nwot.sellievrem'],
    [8, 'bloom@gіthub.com'], [10, 'bloom/' + RLO], [4, 'bloom@' + ZWSP + 'example.ie'], [4, 'bl' + RLO + 'oom@example.ie'], [3, '+1555' + ZWSP],
  ];
  for (const [key, value] of cases) {
    const article = renderCard(doc(), cardFrom([[key, value]]), {});
    const channel = byClass(article, 'channels')[0];
    assert.equal(links(channel).length, 0, JSON.stringify(value));
    assert.ok(texts(channel).includes(value), JSON.stringify(value));
  }
  // Percent-encoding hides an override from the URL check (`%` is atext in a local part), so the
  // visible text is checked too: a link never shows text that hides something.
  assert.equal(urlVerdict('mailto:bl%E2%80%AEoom@example.ie').kind, 'ok');
  const article = renderCard(doc(), cardFrom([[4, 'bl' + RLO + 'oom@example.ie'], [13, [['e', RLO + 'ei.elpmaxe@eod.nhoj', CustomKind.email]]]]), {});
  assert.equal(links(article).filter((a) => a.getAttribute('href').startsWith('mailto:')).length, 0);
  // A URL with a look-alike host is refused at the verdict, before any DOM.
  assert.equal(urlVerdict('https://' + RLO + 'moc.buhtig').kind, 'reject');
  assert.equal(urlVerdict('https://gіthub.com').message, 'non-ASCII host, looks like “github.com”');
});

test('photo bytes that are not JPEG are neither shown nor exported; a JPEG-headed polyglot is only ever an image', () => {
  const notJPEG = [
    Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Uint8Array.from(Buffer.from('GIF89a')),
    Uint8Array.from(Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"/>')), Uint8Array.from(Buffer.from('<script>alert(1)</script>')),
    Uint8Array.from([0xff]), new Uint8Array(0), Uint8Array.from([0xd8, 0xff]), Uint8Array.from(Buffer.from('data:image/jpeg;base64,')),
  ];
  for (const photo of notJPEG) {
    const card = cardFrom([[1, 'x'], [20, photo]]);
    const article = renderCard(doc(), card, {});
    assert.equal(byClass(article, 'photo').length, 0);
    assert.equal(elements(article).filter((e) => e.tagName === 'IMG').length, 0);
    const { vcf } = audit(article, card);
    assert.ok(!vcf.includes('PHOTO'));
  }
  const polyglot = Uint8Array.from([0xff, 0xd8, ...Buffer.from('<svg onload=alert(1)></svg><script>alert(1)</script>'), 0xff, 0xd9]);
  const card = cardFrom([[1, 'x'], [20, polyglot]]);
  const article = renderCard(doc(), card, {});
  const img = byClass(article, 'photo')[0];
  assert.equal(img.tagName, 'IMG');
  assert.deepEqual([...img.attributes.keys()].sort(), ['alt', 'class', 'src']);
  assert.ok(img.getAttribute('src').startsWith('data:image/jpeg;base64,'));
  assert.ok(!/[<>]/.test(img.getAttribute('src')));
  const { vcf } = audit(article, card);
  assert.ok(vcf.includes('PHOTO;ENCODING=b;TYPE=JPEG:'));
  assert.ok(!vcf.includes('<svg'));
});

test('oversized payloads: the page says only that the card is too large, quickly, and echoes nothing', async () => {
  const photoCard = (n) => cborEncode(new Map([[1, '<script>alert(1)</script>'], [16, repeat(7, 8)], [17, 0], [20, repeat(0x41, n)]]));
  const overhead = photoCard(1000).length - 1000;
  const hundredKB = '#1' + base32Encode(photoCard(100 * 1024));
  const tenMB = '#1' + 'A'.repeat(10 * 1024 * 1024);
  for (const hash of [hundredKB, tenMB, '#1' + base32Encode(photoCard(HB1_MAX_BYTES - overhead + 1))]) {
    const t0 = performance.now();
    const { root, win } = await run({ hash });
    assert.ok(performance.now() - t0 < 500);
    assert.equal(serialize(root), '<main id="app"><p class="error">This card is too large to be a Hatband card.</p></main>');
    assert.equal(win.document.title, '');
  }
  const exact = photoCard(HB1_MAX_BYTES - overhead);
  assert.equal(exact.length, HB1_MAX_BYTES);
  const { root } = await run({ hash: '#1' + base32Encode(exact) });
  assert.equal(elements(root).find((e) => e.tagName === 'H1').textContent, '<script>alert(1)</script>');
  assert.equal(byClass(root, 'photo').length, 0, 'bytes that are not JPEG are not a photo');
});

test('the error state is one of four fixed sentences and never carries anything from the fragment', async () => {
  const pool = ['#', '1', '#1', 'A', 'AAAAAAAA', 'MZXW6YTBOI', '=', '0', '9', '8', ' ', '<script>', 'alert(1)', 'javascript:', '%', '\u200b', '\u0301', 'ａ', '\u202e', '"', "'", 'https://hatband.link/'];
  const rng = new SplitMix64(0x455252n);
  const sentences = new Set(['Not a Hatband card.', 'This card uses a newer format than this page knows. Open it in the app.', 'This card is too large to be a Hatband card.', 'This card could not be read.']);
  let distinct = new Set();
  for (let i = 0; i < 400; i++) {
    let hash = '#';
    for (let j = rng.below(10); j > 0; j--) hash += rng.pick(pool);
    if (hash === '#') continue;
    const { root, win } = await run({ hash });
    const message = root.textContent;
    if (elements(root).some((e) => e.tagName === 'ARTICLE')) continue;
    assert.ok(sentences.has(message), JSON.stringify(hash) + ' -> ' + message);
    assert.equal(serialize(root), `<main id="app"><p class="error">${message}</p></main>`);
    assert.equal(win.document.title, '');
    distinct.add(message);
  }
  assert.ok(distinct.size >= 3, [...distinct].join(' | '));
  assert.equal(errorMessage({ code: 'tooLarge', characters: 10 }), 'This card could not be read.', 'a foreign object with a code is not an HB1Error');
});

test('main() touches nothing but the document, the hash, crypto, navigator and File; the URL is never rewritten', async () => {
  const typical = vector('typical-signed');
  const hash = typical.url.slice(HB1_URL_PREFIX.length - 1);
  const touched = new Set();
  const location = new Proxy({ hash, href: typical.url }, {
    get(target, prop) { touched.add('location.' + String(prop)); return target[prop]; },
    set(target, prop) { throw new Error('location.' + String(prop) + ' assigned'); },
  });
  const base = makeWindow({ hash, href: typical.url });
  const forbidden = ['localStorage', 'sessionStorage', 'indexedDB', 'history', 'fetch', 'XMLHttpRequest', 'WebSocket', 'caches', 'open', 'postMessage', 'Image', 'EventSource', 'Worker', 'cookieStore'];
  const win = new Proxy({ ...base, location }, {
    get(target, prop) {
      touched.add(String(prop));
      if (forbidden.includes(prop)) throw new Error(String(prop) + ' touched');
      return target[prop];
    },
  });
  await main(win);
  assert.deepEqual([...touched].sort(), ['File', 'crypto', 'document', 'location', 'location.hash', 'location.href', 'navigator'].sort());
  assert.equal(location.hash, hash);
  assert.equal(location.href, typical.url);
  const root = win.document.getElementById('app');
  assert.equal(byClass(root, 'badge')[0].textContent, 'signature verified');
  // The one thing that leaves the card for the browser chrome: the name in the window title,
  // which browsers keep in history and tab lists. Deliberate; recorded here so a change is noticed.
  assert.equal(win.document.title, 'Leopold Bloom · Hatband');
});

test('vCard file names: everything the text check flags is stripped, path characters too, and a surrogate is never split', () => {
  assert.equal(vcardFileName({ name: 'Leopold Bloom' }), 'Leopold Bloom.vcf');
  assert.equal(vcardFileName({ name: '../../etc/passwd\n<x>' }), '....etcpasswdx.vcf');
  assert.equal(vcardFileName({ name: 'x' + RLO + 'fdp.exe' }), 'xfdp.exe.vcf');
  assert.equal(vcardFileName({ name: 'a\u061cb\u2060c\u00add\u{e0041}e\u200bf\u2066g\ufeffh\u0000i\u007fj\u0085k' }), 'abcdefghijk.vcf');
  assert.equal(vcardFileName({ name: 'C:\\Users\\x|y*z?"<>' }), 'CUsersxyz.vcf');
  assert.equal(vcardFileName({ name: '   ' }), 'card.vcf');
  assert.equal(vcardFileName({ name: RLO }), 'card.vcf');
  assert.equal(vcardFileName({ name: null }), 'card.vcf');
  const emoji = '🎩'.repeat(70);
  const name = vcardFileName({ name: emoji });
  assert.equal(name, '🎩'.repeat(60) + '.vcf');
  assert.doesNotThrow(() => new TextDecoder('utf-8', { fatal: true }).decode(new TextEncoder().encode(name)));
  for (let cp = 0; cp < 0x3000; cp++) {
    const ch = String.fromCodePoint(cp);
    const kept = vcardFileName({ name: 'a' + ch + 'b' }) === 'a' + ch + 'b.vcf';
    const expected = textProblem(cp) === null && !'/\\:*?"<>|'.includes(ch) && !(cp === 0x20);
    if (cp === 0x20) continue;
    assert.equal(kept, expected, cp.toString(16));
  }
});

test('the vCard built from a hostile card escapes every value and forges no line', () => {
  const br = ['\r\n', '\n', '\r', '\u0085', '\u2028', '\u2029'];
  for (const b of br) {
    const card = cardFrom([
      [1, 'Bloom' + b + 'FN:Mallory' + b + 'END:VCARD' + b + 'BEGIN:VCARD'], [2, 'Org' + b + 'TEL:+1'], [3, '+1555' + b + 'TEL:+2'], [4, 'a@b.ie' + b + 'EMAIL:x@y'],
      [5, 'nnix.com/' + b + 'item9.URL:https://evil'], [6, 'lbloom' + b], [13, [['l' + b + 'item9.URL:https://evil', 'v' + b + 'PHOTO;ENCODING=b:AAAA', 0], ['k', 'ssh-ed25519 AAAA' + b + 'X-HATBAND-KEY:evil', 4]]],
    ]);
    const article = renderCard(doc(), card, {});
    const { vcf } = audit(article, card);
    const lines = vcf.slice(0, -2).split('\r\n');
    assert.ok(lines.every((l) => Buffer.byteLength(l) <= 75));
    assert.equal(lines.filter((l) => l === 'BEGIN:VCARD').length, 1);
    assert.equal(lines.filter((l) => l === 'END:VCARD').length, 1);
    assert.equal(lines.filter((l) => l.startsWith('FN:')).length, 1);
    assert.ok(!lines.some((l) => /^(TEL:\+2|EMAIL:x|item9|PHOTO|X-HATBAND-KEY:evil)/.test(l)), lines.join('|'));
    assert.equal(lines.filter((l) => l.startsWith('X-HATBAND-')).length, 2);
    const bytes = Buffer.from(vcf);
    for (let i = 0; i < bytes.length; i++) {
      if (bytes[i] === 0x0a) assert.equal(bytes[i - 1], 0x0d);
      if (bytes[i] === 0x0d) assert.equal(bytes[i + 1], 0x0a);
    }
    assert.ok(!vcf.includes('\u0085') && !vcf.includes('\u2028') && !vcf.includes('\u2029'));
  }
});

test('the wild-card palette index, alias glyph and unknown flag bits render without reaching an attribute', () => {
  for (const [flags, color] of [[0, 0], [1, 9], [4, 10], [7, 255], [2 ** 40 + 4, 42]]) {
    const card = cardFrom([[0, flags], [1, 'x'], [18, color]]);
    const article = renderCard(doc(), card, {});
    assert.match(article.className, /^card c[0-9]$/);
    assert.equal(article.className, 'card c' + (color < 10 ? color : 0));
    audit(article, card);
  }
  const compact = cardFrom([[0, 1], [1, 'x'], [19, repeat(0xee, 8)]]);
  const article = renderCard(doc(), compact, { signature: 'none', keyFingerprint: compact.keyFingerprint });
  assert.equal(elements(article).find((e) => e.tagName === 'CODE').textContent, 'EEEE EEEE EEEE EEEE');
  assert.equal(byClass(article, 'badge')[0].textContent, 'unsigned (Lock Screen card)');
  audit(article, compact);
  assert.equal(hexEncode(compact.keyFingerprint), 'eeeeeeeeeeeeeeee');
});
