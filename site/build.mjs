#!/usr/bin/env node
/* Builds index.html and the three pages from src/: script and style go
   inline, and their SHA-256 hashes go into the Content-Security-Policy.
   No dependencies. `node site/build.mjs` writes the files; tests import
   `build()` to check the committed ones are current. */
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

const here = new URL('.', import.meta.url);
const read = (path) => readFileSync(new URL(path, here), 'utf8');

export const hashSource = (text) => "'sha256-" + createHash('sha256').update(text).digest('base64') + "'";

/** `{{name}}` placeholders; a function replacement so `$` in code survives. */
function fill(template, values) {
  return template.replace(/\{\{(\w+)\}\}/g, (_, key) => {
    if (!(key in values)) throw new Error('unfilled placeholder ' + key);
    return values[key];
  });
}

/** One classic script from the two modules: exports stripped, the import
    dropped, wrapped so nothing reaches the page's global scope. */
export function bundle(hb1, page) {
  const strip = (src) => src.replace(/^export (?=(?:async )?function |const |let |class )/gm, '');
  const body = strip(hb1) + '\n' + strip(page.replace(/^import \{[^}]*\} from '\.\/hb1\.js';\n/m, ''));
  if (/^(import|export)\b/m.test(body)) throw new Error('module syntax survived bundling');
  return `(() => {\n'use strict';\n${body}\n})();\n`;
}

export function indexCSP(script, style) {
  return `default-src 'none'; script-src ${hashSource(script)}; style-src ${hashSource(style)}; img-src data:; connect-src 'none'; form-action 'none'; base-uri 'none'; frame-ancestors 'none'`;
}

export function pageCSP(style) {
  return `default-src 'none'; style-src ${hashSource(style)}; form-action 'none'; base-uri 'none'; frame-ancestors 'none'`;
}

export const PAGES = [['privacy', 'Privacy'], ['trust', 'Trust'], ['support', 'Support']];

/** File name to contents for everything the build produces. */
export function build() {
  const style = read('src/style.css');
  const script = bundle(read('src/hb1.js'), read('src/page.js'));
  if (/<\/(script|style)/i.test(script) || /<\/style/i.test(style)) throw new Error('inline content would close its tag');
  const csp = indexCSP(script, style);
  const files = { 'index.html': fill(read('src/index.template.html'), { csp, style, script }) };
  const pageCsp = pageCSP(style);
  for (const [name, title] of PAGES) {
    const body = fill(read(`src/pages/${name}.html`), { indexCsp: csp }).trim();
    files[name + '.html'] = fill(read('src/page.template.html'), { csp: pageCsp, title, style, body });
  }
  return files;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  for (const [name, html] of Object.entries(build())) {
    writeFileSync(new URL(name, here), html);
    process.stdout.write(`${name} ${Buffer.byteLength(html)} bytes\n`);
  }
}
