import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { build, bundle, PAGES } from '../build.mjs';

const site = (path) => new URL('../' + path, import.meta.url);
const read = (path) => readFileSync(site(path), 'utf8');
const index = read('index.html');
const csp = () => /<meta http-equiv="Content-Security-Policy" content="([^"]*)">/.exec(index)[1];
const inline = (tag) => {
  const matches = [...index.matchAll(new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`, 'g'))];
  assert.equal(matches.length, 1, `one inline ${tag}`);
  return matches[0][1];
};
const hash = (text) => "'sha256-" + createHash('sha256').update(text).digest('base64') + "'";

test('index.html and the pages are what the sources build', () => {
  const built = build();
  assert.deepEqual(Object.keys(built).sort(), ['index.html', 'privacy.html', 'support.html', 'trust.html']);
  for (const [name, html] of Object.entries(built)) assert.equal(read(name), html, `${name} is stale: run node site/build.mjs`);
});

test('the CSP is exactly as specified and its hashes match the inline content', () => {
  const policy = csp();
  const script = inline('script');
  const style = inline('style');
  assert.equal(policy, `default-src 'none'; script-src ${hash(script)}; style-src ${hash(style)}; img-src data:; connect-src 'none'; form-action 'none'; base-uri 'none'; frame-ancestors 'none'`);
  assert.match(policy, /^default-src 'none'; script-src 'sha256-[A-Za-z0-9+/]{43}='; style-src 'sha256-[A-Za-z0-9+/]{43}='; img-src data:; connect-src 'none'; form-action 'none'; base-uri 'none'; frame-ancestors 'none'$/);
  assert.ok(index.indexOf('<meta http-equiv="Content-Security-Policy"') < index.indexOf('<meta name="viewport"'), 'CSP comes first');
  assert.ok(!/<script\s/.test(index), 'no script tag with attributes');
  assert.ok(!/<link\b/.test(index), 'no link element');
  for (const [name] of PAGES) {
    const page = read(name + '.html');
    const pageStyle = /<style>([\s\S]*?)<\/style>/.exec(page)[1];
    assert.match(page, new RegExp(`content="default-src 'none'; style-src ${hash(pageStyle).replace(/[+/]/g, '\\$&')}; form-action 'none'; base-uri 'none'; frame-ancestors 'none'"`));
    assert.ok(!/<script/.test(page), name + ' has no script');
    assert.equal(pageStyle, style, name + ' shares the stylesheet');
  }
  assert.ok(read('trust.html').includes(policy), 'trust page quotes the live CSP');
});

test('nothing external except the GitHub and App Store links', () => {
  const hosts = new Set([...index.matchAll(/https?:\/\/([A-Za-z0-9.-]+)/g)].map((m) => m[1]));
  const allowed = new Set(['hatband.link', 'github.com', 'www.linkedin.com', 'signal.me', 'calendly.com', 'apps.apple.com']);
  for (const host of hosts) assert.ok(allowed.has(host), host);
  const markup = index.replace(/<script>[\s\S]*<\/script>/, '').replace(/<style>[\s\S]*<\/style>/, '');
  const hrefs = [...markup.matchAll(/href="([^"]*)"/g)].map((m) => m[1]);
  for (const href of hrefs) assert.ok(href.startsWith('/') || href.startsWith('https://github.com/davidemerson/hatband'), href);
  const script = inline('script');
  for (const forbidden of ['innerHTML', 'outerHTML', 'insertAdjacentHTML', 'document.write', 'eval(', 'new Function', 'fetch(', 'XMLHttpRequest', 'WebSocket', 'sendBeacon', 'import(', 'importScripts', 'url(', '@import', 'localStorage', 'indexedDB', 'document.cookie']) {
    assert.ok(!script.includes(forbidden), forbidden);
  }
  assert.ok(!/\son[a-z]+=/.test(markup), 'no inline event handlers');
  assert.ok(!/\sstyle=/.test(markup), 'no style attributes');
  const style = inline('style');
  assert.ok(!/url\(|@import|@font-face/.test(style), 'stylesheet loads nothing');
  assert.ok(!/^\s*(import|export)\b/m.test(script), 'bundled script is a classic script');
  assert.ok(script.includes("'use strict'"));
});

test('the committed bundle runs: it renders a card from location.hash and leaves no globals', async () => {
  const { runInThisContext } = await import('node:vm');
  const { makeWindow, elements } = await import('./dom.mjs');
  const { vectors } = await import('./helpers.mjs');
  const typical = vectors.find((v) => v.name === 'typical-signed');
  const before = new Set(Object.keys(globalThis));
  globalThis.window = makeWindow({ hash: typical.url.slice(typical.url.indexOf('#')), href: typical.url });
  try {
    assert.equal(runInThisContext(inline('script'), { filename: 'index.html#script' }), undefined);
    await new Promise((resolve) => setTimeout(resolve, 50));
    const root = globalThis.window.document.getElementById('app');
    assert.equal(elements(root).find((e) => e.tagName === 'H1').textContent, 'Leopold Bloom');
    assert.equal(elements(root).find((e) => e.classList.contains('badge')).textContent, 'signature verified');
    assert.equal(globalThis.window.document.title, 'Hatband');
    assert.deepEqual(Object.keys(globalThis).filter((k) => !before.has(k)), ['window'], 'nothing leaks into the global scope');
  } finally {
    delete globalThis.window;
  }
});

test('index.html stays under 200 KB', () => {
  assert.ok(statSync(site('index.html')).size < 200 * 1024);
});

test('bundling strips module syntax and refuses leftovers', () => {
  const out = bundle('export function a() {}\nexport const b = 1;\nexport class C {}\nexport async function d() {}\n', "import { a } from './hb1.js';\nexport function e() { return a(); }\n");
  assert.ok(!/\b(import|export)\b/.test(out));
  assert.ok(out.startsWith("(() => {\n'use strict';\n"));
  assert.throws(() => bundle('export default 1;\n', ''), /module syntax/);
});

test('.well-known files', () => {
  const aasa = JSON.parse(read('.well-known/apple-app-site-association'));
  assert.deepEqual(aasa, { applinks: { details: [{ appIDs: ['TEAMID.link.hatband.ios'], components: [{ '/': '/', '#': '1*' }] }] } });
  const security = read('.well-known/security.txt');
  const field = (name) => new RegExp(`^${name}: (.*)$`, 'm').exec(security)[1];
  assert.equal(field('Contact'), 'mailto:d@nnix.com');
  assert.equal(field('Expires'), '2027-09-04T00:00:00.000Z');
  assert.equal(field('Canonical'), 'https://hatband.link/.well-known/security.txt');
  assert.equal(field('Policy'), 'https://github.com/davidemerson/hatband#security');
  assert.ok(security.endsWith('\n'));
});
