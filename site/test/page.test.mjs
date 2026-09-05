import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cardFromMap, hb1DecodeURL, hb1URL, HB1_URL_PREFIX } from '../src/hb1.js';
import { APP_STORE_URL, badgeText, channelRows, customRows, errorMessage, hostOf, keyRows, linkNode, main, renderCard, renderEmpty, renderError, vcardFileName } from '../src/page.js';
import { Document, elements, makeWindow, serialize, texts } from './dom.mjs';
import { repeat, vector } from './helpers.mjs';

const doc = () => new Document();
const links = (root) => elements(root).filter((e) => e.tagName === 'A');
const byClass = (root, name) => elements(root).filter((e) => e.classList.contains(name));
const cardOf = (name) => { const map = hb1DecodeURL(vector(name).url); return { map, card: cardFromMap(map) }; };
const run = async (options) => { const win = makeWindow(options); await main(win); return { win, root: win.document.getElementById('app') }; };

test('the DOM stub refuses innerHTML', () => {
  const d = doc();
  const e = d.createElement('div');
  assert.throws(() => { e.innerHTML = '<b>x</b>'; });
  assert.throws(() => e.insertAdjacentHTML('beforeend', 'x'));
  e.textContent = '<b>x</b>';
  assert.equal(serialize(e), '<div>&lt;b&gt;x&lt;/b&gt;</div>');
});

test('hosts shown beside links', () => {
  assert.equal(hostOf('https://github.com/lbloom'), 'github.com');
  assert.equal(hostOf('HTTP://Example.ORG:8080/x'), 'example.org:8080');
  assert.equal(hostOf('mailto:henry.flower@example.ie?subject=x'), 'example.ie');
  assert.equal(hostOf('tel:+1555'), '');
  assert.equal(hostOf('javascript:alert(1)'), '');
});

test('a link only when the allow-list permits, with the host and any warning beside it', () => {
  const d = doc();
  const ok = d.createElement('p');
  ok.appendChild(linkNode(d, 'https://github.com/lbloom', 'lbloom'));
  assert.equal(serialize(ok), '<p><a href="https://github.com/lbloom" rel="noreferrer noopener">lbloom</a><span class="domain">github.com</span></p>');
  const http = d.createElement('p');
  http.appendChild(linkNode(d, 'http://nnix.com/~d', 'nnix.com/~d'));
  assert.equal(serialize(http), '<p><a href="http://nnix.com/~d" rel="noreferrer noopener">nnix.com/~d</a><span class="domain">nnix.com</span><span class="warn">not encrypted</span></p>');
  for (const bad of ['javascript:alert(1)', 'data:text/html,<script>', 'acct:a@b.ie', 'OPENPGP4FPR:' + 'A'.repeat(40), 'https://gіthub.com/x', 'https://x.com/"', null]) {
    const p = d.createElement('p');
    p.appendChild(linkNode(d, bad, 'label'));
    assert.equal(serialize(p), '<p>label</p>', String(bad));
  }
});

test('rows for the typical card', () => {
  const { card } = cardOf('typical-signed');
  assert.deepEqual(channelRows(card).map((r) => [r.label, r.uri]), [
    ['phone', 'tel:+353871234567'], ['email', 'mailto:henry.flower@example.ie'], ['website', 'https://nnix.com'],
    ['GitHub', 'https://github.com/lbloom'], ['LinkedIn', 'https://www.linkedin.com/in/leopold-bloom'],
    ['Mastodon', 'https://merveilles.town/@bloom'], ['Calendly', 'https://calendly.com/bloom/coffee'],
  ]);
  assert.deepEqual(keyRows(card, null), []);
  assert.deepEqual(keyRows(card, repeat(0xab, 8)), [{ label: 'Hatband key', text: 'ABAB ABAB ABAB ABAB' }]);
  assert.deepEqual(customRows(card), []);
  assert.equal(badgeText(card, 'verified'), 'signature verified');
  assert.equal(badgeText(card, 'invalid'), 'signature invalid');
  assert.equal(badgeText(card, 'unsupported'), 'unverified (browser lacks Ed25519)');
  assert.equal(badgeText(card, 'none'), 'unsigned');
  assert.equal(badgeText(cardOf('compact-name-only').card, 'none'), 'unsigned (Lock Screen card)');
  assert.equal(vcardFileName(card), 'Leopold Bloom.vcf');
  assert.equal(vcardFileName({ name: '../../etc/passwd\n<x>' }), '....etcpasswdx.vcf');
  assert.equal(vcardFileName({ name: 'x‮fdp.exe' }), 'xfdp.exe.vcf');
  assert.equal(vcardFileName({ name: null }), 'card.vcf');
});

test('renders the typical card with links, host labels, badge, date and actions', () => {
  const { card } = cardOf('typical-signed');
  const d = doc();
  const article = renderCard(d, card, { signature: 'verified', keyFingerprint: repeat(1, 32), url: 'https://hatband.link/#1X' });
  assert.equal(article.className, 'card c2');
  assert.equal(elements(article).find((e) => e.tagName === 'H1').textContent, 'Leopold Bloom');
  assert.equal(byClass(article, 'company')[0].textContent, "Freeman's Journal");
  const channelLinks = links(byClass(article, 'channels')[0]);
  assert.deepEqual(channelLinks.map((a) => a.getAttribute('href')), [
    'tel:+353871234567', 'mailto:henry.flower@example.ie', 'https://nnix.com', 'https://github.com/lbloom',
    'https://www.linkedin.com/in/leopold-bloom', 'https://merveilles.town/@bloom', 'https://calendly.com/bloom/coffee',
  ]);
  assert.deepEqual(byClass(article, 'domain').map((e) => e.textContent), ['example.ie', 'nnix.com', 'github.com', 'www.linkedin.com', 'merveilles.town', 'calendly.com']);
  assert.deepEqual(byClass(article, 'label').map((e) => e.textContent), ['phone', 'email', 'website', 'GitHub', 'LinkedIn', 'Mastodon', 'Calendly', 'Hatband key']);
  const code = elements(article).find((e) => e.tagName === 'CODE');
  assert.equal(code.textContent, '0101 0101 0101 0101 0101 0101 0101 0101\n0101 0101 0101 0101 0101 0101 0101 0101');
  assert.equal(byClass(article, 'badge')[0].textContent, 'signature verified');
  assert.equal(byClass(article, 'badge')[0].className, 'badge ok');
  assert.equal(byClass(article, 'meta')[0].textContent, 'issued 2026-09-04 · seq 1');
  const actions = links(byClass(article, 'actions')[0]);
  assert.deepEqual(actions.map((a) => a.textContent), ['Add to contacts', 'Open in Hatband', 'App Store']);
  assert.ok(actions[0].getAttribute('href').startsWith('data:text/vcard;charset=utf-8,BEGIN%3AVCARD'));
  assert.equal(actions[0].getAttribute('download'), 'Leopold Bloom.vcf');
  assert.equal(actions[1].getAttribute('href'), 'https://hatband.link/#1X');
  assert.equal(actions[2].getAttribute('href'), APP_STORE_URL);
  assert.equal(byClass(article, 'alias').length, 0);
  assert.equal(byClass(article, 'photo').length, 0);
});

test('renders the maximal card: http marked, keys in monospace with copy, custom fields by kind', () => {
  const { card } = cardOf('maximal-qr-signed');
  const d = doc();
  const copied = [];
  const navigator = { clipboard: { writeText: async (text) => { copied.push(text); } } };
  const article = renderCard(d, card, { signature: 'verified', navigator });
  assert.deepEqual(byClass(article, 'warn').map((e) => e.textContent), ['not encrypted']);
  const signal = links(article).find((a) => a.textContent === 'username link');
  assert.ok(signal.getAttribute('href').startsWith('https://signal.me/#eu/'));
  const codes = elements(byClass(article, 'keys')[0]).filter((e) => e.tagName === 'CODE').map((e) => e.textContent);
  assert.equal(codes.length, 2);
  assert.equal(codes[0], 'A0A1 A2A3 A4A5 A6A7 A8A9  AAAB ACAD AEAF B0B1 B2B3');
  assert.match(codes[1], /^ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEBBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5f$/);
  const buttons = elements(article).filter((e) => e.tagName === 'BUTTON');
  assert.equal(buttons.length, 2);
  buttons[1].dispatch('click');
  assert.deepEqual(copied, [codes[1]]);
  const custom = byClass(article, 'custom')[0];
  const items = elements(custom).filter((e) => e.tagName === 'LI');
  assert.equal(items.length, 3);
  assert.equal(serialize(items[0]), "<li><span class=\"label\">Pub</span>Davy Byrne's</li>");
  assert.equal(links(items[1])[0].getAttribute('href'), 'https://matrix.to/#/@bloom:example.ie');
  assert.equal(byClass(items[1], 'domain')[0].textContent, 'matrix.to');
  assert.equal(links(items[2])[0].getAttribute('href'), 'tel:+35318000000');
  assert.equal(byClass(article, 'meta')[0].textContent, 'issued 2026-09-04 · seq 7');
});

test('alias glyph, photo, compact fingerprint', () => {
  const d = doc();
  const alias = renderCard(d, cardOf('alias-signed').card, {});
  const h1 = elements(alias).find((e) => e.tagName === 'H1');
  assert.equal(h1.textContent, 'Henry Flower ✿');
  assert.equal(byClass(alias, 'alias')[0].getAttribute('title'), 'alias');
  assert.equal(alias.className, 'card c9');
  const photo = renderCard(d, cardOf('file-with-photo-and-key').card, {});
  const img = byClass(photo, 'photo')[0];
  assert.equal(img.tagName, 'IMG');
  assert.ok(img.getAttribute('src').startsWith('data:image/jpeg;base64,/9j/4AAQSkZJRg'));
  const notJPEG = cardOf('file-with-photo-and-key').card;
  notJPEG.photo = Uint8Array.from([0x89, 0x50, 0x4e, 0x47]);
  assert.equal(byClass(renderCard(d, notJPEG, {}), 'photo').length, 0);
  const compact = renderCard(d, cardOf('compact-name-only').card, { signature: 'none', keyFingerprint: cardOf('compact-name-only').card.keyFingerprint });
  assert.equal(elements(compact).find((e) => e.tagName === 'CODE').textContent, 'E4F8 8815 C8DB 93C8');
  assert.equal(byClass(compact, 'badge')[0].textContent, 'unsigned (Lock Screen card)');
  assert.equal(byClass(compact, 'channels').length, 0);
  assert.equal(compact.className, 'card c2');
  const wild = cardOf('compact-name-only').card;
  wild.color = 77;
  assert.equal(renderCard(d, wild, {}).className, 'card c0');
});

test('hostile text renders as text: no element injection, no bad hrefs', () => {
  const rtl = 'moc.elgoog‮';
  const map = new Map([
    [1, '<script>alert(1)</script>' + rtl],
    [2, '"><img src=x onerror=alert(1)>'],
    [4, 'a@b.ie?subject=x&body=<script>'],
    [5, 'evil.com/"><script>alert(1)</script>'],
    [6, '../<svg onload=alert(1)>'],
    [8, '<b>@evil.com'],
    [10, 'x?q=<script>'],
    [13, [
      ['x', 'javascript:alert(1)', 1], ['y', 'data:text/html,<script>alert(1)</script>', 1], ['z', '<b>bold</b>', 0],
      ['e', 'a@b.ie?subject=x&body=<script>', 2], ['p', '+1<script>', 3], ['k', '</code><script>x</script>', 4],
      ['ok', 'https://example.com/fine', 1], ['vb', 'vbscript:msgbox', 1], ['rtl', 'https://' + rtl + '.com', 1],
      ['&amp;', '&lt;script&gt;', 0], ['sp', 'https://example.com/<script>', 1],
    ]],
    [16, repeat(9, 8)], [17, 2438], [18, 4],
  ]);
  const card = cardFromMap(hb1DecodeURL(hb1URL(map)));
  const d = doc();
  const article = renderCard(d, card, { signature: 'none', url: 'https://hatband.link/#1' });
  const tags = new Set(elements(article).map((e) => e.tagName));
  for (const forbidden of ['SCRIPT', 'IMG', 'SVG', 'B', 'IFRAME', 'OBJECT', 'EMBED', 'STYLE', 'LINK']) assert.ok(!tags.has(forbidden), forbidden);
  const html = serialize(article);
  assert.ok(!html.includes('<script'), 'no script tag opens');
  assert.ok(!html.includes('<img'), 'no img');
  assert.ok(html.includes('"&gt;&lt;img src=x onerror=alert(1)&gt;'), 'attribute text is escaped, not an attribute');
  for (const e of elements(article)) for (const name of e.attributes.keys()) assert.ok(!name.startsWith('on'), name);
  assert.ok(html.includes('&lt;script&gt;alert(1)&lt;/script&gt;'), 'the name is text');
  const hrefs = links(article).map((a) => a.getAttribute('href'));
  for (const href of hrefs) {
    assert.match(href, /^(https:\/\/|tel:\+|mailto:|data:text\/vcard;charset=utf-8,)/, href);
    if (!href.startsWith('data:')) assert.ok(!/javascript|vbscript|<|>|"/.test(href), href);
  }
  assert.deepEqual(hrefs.filter((h) => h.startsWith('https://')), ['https://example.com/fine', 'https://hatband.link/#1', APP_STORE_URL]);
  for (const attr of elements(article).flatMap((e) => [...e.attributes.values()])) assert.ok(!/<|>/.test(attr), attr);
  const textContent = texts(article);
  for (const hostile of ['<script>alert(1)</script>' + rtl, '"><img src=x onerror=alert(1)>', 'evil.com/"><script>alert(1)</script>',
    'javascript:alert(1)', 'data:text/html,<script>alert(1)</script>', '<b>bold</b>', '</code><script>x</script>', '&lt;script&gt;', '&amp;']) {
    assert.ok(textContent.includes(hostile), hostile);
  }
  const code = elements(article).filter((e) => e.tagName === 'CODE');
  assert.equal(code.length, 1);
  assert.equal(code[0].textContent, '</code><script>x</script>');
  const vcf = decodeURIComponent(hrefs.find((h) => h.startsWith('data:')).split(',')[1]);
  assert.ok(!vcf.includes('URL:javascript'));
  assert.ok(!vcf.includes('URL:data:'));
  assert.ok(!vcf.includes('URL:https://evil.com'), 'a rejected channel URL is not a vCard link either');
  assert.ok(vcf.includes('item1.URL:https://example.com/fine\r\n'));
  assert.ok(vcf.replace(/\r\n /g, '').includes('NOTE:Website: evil.com/"><script>alert(1)</script>\\n'));
  assert.ok(vcf.includes('FN:<script>alert(1)</script>'));
  assert.equal(vcardFileName(card), 'scriptalert(1)scriptmoc.elgoog.vcf');
  assert.equal(links(article).find((a) => a.textContent === 'Add to contacts').getAttribute('download'), 'scriptalert(1)scriptmoc.elgoog.vcf');
});

test('error and empty states never echo the fragment', async () => {
  for (const [hash, message] of [
    ['#1!!!<script>alert(1)</script>', 'Not a Hatband card.'],
    ['#9' + 'A'.repeat(16), 'This card uses a newer format than this page knows. Open it in the app.'],
    ['#2AAAA', 'Not a Hatband card.'],
    ['#1AAAAAAAA', 'This card could not be read.'],
    ['#1' + 'AAAAAAAA'.repeat(3), 'This card could not be read.'],
  ]) {
    const { root } = await run({ hash });
    assert.equal(root.textContent, message, hash);
    assert.ok(!serialize(root).includes('AAAA'));
    assert.ok(!serialize(root).includes('alert'));
    assert.ok(!serialize(root).includes('<script'));
  }
  assert.equal(errorMessage(new Error('x')), 'This card could not be read.');
  assert.equal(errorMessage(null), 'This card could not be read.');
  assert.equal(renderError(doc(), new TypeError('y')).textContent, 'This card could not be read.');
  const { root: empty } = await run({ hash: '' });
  assert.equal(elements(empty).find((e) => e.tagName === 'H1').textContent, 'No fixed abode.');
  assert.match(empty.textContent, /hatband\.link shows a Hatband business card/);
  assert.equal(renderEmpty(doc()).className, 'empty');
  const { root: onlyHash } = await run({ hash: '#' });
  assert.ok(onlyHash.textContent.startsWith('No fixed abode.'));
});

test('main: verifies, fingerprints and renders from location.hash', async () => {
  const typical = vector('typical-signed');
  const { win, root } = await run({ hash: typical.url.slice(HB1_URL_PREFIX.length - 1), href: typical.url });
  assert.equal(win.document.title, 'Leopold Bloom · Hatband');
  assert.equal(byClass(root, 'badge')[0].textContent, 'signature verified');
  const open = links(root).find((a) => a.textContent === 'Open in Hatband');
  assert.equal(open.getAttribute('href'), typical.url);
  const code = elements(root).find((e) => e.tagName === 'CODE');
  const digest = (await import('node:crypto')).createHash('sha256').update(Buffer.from(typical.publicKey, 'hex')).digest('hex').toUpperCase();
  assert.equal(code.textContent.replace(/[\s]/g, ''), digest);

  const tampered = vector('tampered-signature');
  const bad = await run({ hash: tampered.url.slice(HB1_URL_PREFIX.length - 1) });
  assert.equal(byClass(bad.root, 'badge')[0].textContent, 'signature invalid');
  assert.equal(byClass(bad.root, 'badge')[0].className, 'badge bad');

  const compact = vector('compact-two-channels');
  const lock = await run({ hash: compact.url.slice(HB1_URL_PREFIX.length - 1) });
  assert.equal(byClass(lock.root, 'badge')[0].textContent, 'unsigned (Lock Screen card)');
  assert.equal(elements(lock.root).find((e) => e.tagName === 'CODE').textContent, 'E4F8 8815 C8DB 93C8');

  const noCrypto = await run({ hash: typical.url.slice(HB1_URL_PREFIX.length - 1), crypto: null });
  assert.equal(byClass(noCrypto.root, 'badge')[0].textContent, 'unverified (browser lacks Ed25519)');
  const noEd25519 = { subtle: { importKey: async () => { throw new DOMException('x', 'NotSupportedError'); }, digest: globalThis.crypto.subtle.digest.bind(globalThis.crypto.subtle) } };
  const old = await run({ hash: typical.url.slice(HB1_URL_PREFIX.length - 1), crypto: noEd25519 });
  assert.equal(byClass(old.root, 'badge')[0].textContent, 'unverified (browser lacks Ed25519)');
});

test('Add to contacts prefers the share sheet when it can carry a file', async () => {
  const shared = [];
  class FakeFile { constructor(parts, name, options) { this.parts = parts; this.name = name; this.type = options.type; } }
  const navigator = { canShare: ({ files }) => files.length === 1 && files[0] instanceof FakeFile, share: async (data) => { shared.push(data); } };
  const { card } = cardOf('typical-signed');
  const article = renderCard(doc(), card, { navigator, File: FakeFile });
  const add = links(article).find((a) => a.textContent === 'Add to contacts');
  assert.equal(add.dispatch('click'), false, 'default prevented');
  assert.equal(shared.length, 1);
  assert.equal(shared[0].files[0].name, 'Leopold Bloom.vcf');
  assert.equal(shared[0].files[0].type, 'text/vcard');
  assert.ok(shared[0].files[0].parts[0].startsWith('BEGIN:VCARD\r\n'));
  const plain = renderCard(doc(), card, { navigator: { canShare: () => false }, File: FakeFile });
  assert.equal(links(plain).find((a) => a.textContent === 'Add to contacts').dispatch('click'), true, 'download link stands');
});
