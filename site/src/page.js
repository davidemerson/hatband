/* Renders a card into the DOM. Text enters only as text nodes; attributes
   come from constants, from URIs the allow-list accepted, or from bytes we
   encoded ourselves. Every function takes the document, so node:test can
   drive it with a stub. */
import {
  CustomKind, HB1Error, base64Encode, calendlyURI, cardFromMap, cardVCard, dayToCivil, emailURI,
  githubURI, gpgFingerprintFormatted, hb1DecodeURL, isJPEG, isTappable, isoDate, keyFingerprintDisplay,
  linkedinURI, mastodonURI, paletteIndex, phoneURI, sha256, signalURI, signatureStatus, sshDisplay,
  textProblem, textProblemIn, urlVerdict, websiteURI,
} from './hb1.js';

/** Placeholder until the listing exists. */
export const APP_STORE_URL = 'https://apps.apple.com/app/id0000000000';
export const SOURCE_URL = 'https://github.com/davidemerson/hatband';

export function el(doc, tag, className, ...children) {
  const node = doc.createElement(tag);
  if (className) node.className = className;
  for (const child of children) {
    if (child == null) continue;
    node.appendChild(typeof child === 'string' ? doc.createTextNode(child) : child);
  }
  return node;
}

/** The host a link goes to, shown beside it so a label cannot disguise the
    destination. Empty for `tel:`. */
export function hostOf(uri) {
  const web = /^https?:\/\/([^/?#]+)/i.exec(uri);
  if (web) return web[1].toLowerCase();
  const mail = /^mailto:([^?]*)/i.exec(uri);
  if (mail) {
    const at = mail[1].lastIndexOf('@');
    return at < 0 ? '' : mail[1].slice(at + 1).toLowerCase();
  }
  return '';
}

/** A link when the allow-list permits and the text it shows hides nothing;
    the bare text otherwise. */
export function linkNode(doc, uri, label) {
  if (!uri || textProblemIn(label) || !isTappable(uri)) return doc.createTextNode(label);
  const fragment = doc.createDocumentFragment();
  const a = el(doc, 'a', null, label);
  a.setAttribute('href', uri);
  a.setAttribute('rel', 'noreferrer noopener');
  fragment.appendChild(a);
  const host = hostOf(uri);
  if (host) fragment.appendChild(el(doc, 'span', 'domain', host));
  const verdict = urlVerdict(uri);
  if (verdict.kind === 'warning') fragment.appendChild(el(doc, 'span', 'warn', verdict.message));
  return fragment;
}

export function channelRows(card) {
  const rows = [];
  if (card.phone) rows.push({ label: 'phone', text: card.phone, uri: phoneURI(card.phone) });
  if (card.email) rows.push({ label: 'email', text: card.email, uri: emailURI(card.email) });
  if (card.website) {
    rows.push({ label: 'website', text: card.website.address, uri: websiteURI(card.website.address, card.website.insecure) });
  }
  if (card.github) rows.push({ label: 'GitHub', text: card.github, uri: githubURI(card.github) });
  if (card.linkedin) rows.push({ label: 'LinkedIn', text: card.linkedin, uri: linkedinURI(card.linkedin) });
  if (card.mastodon) {
    const m = mastodonURI(card.mastodon);
    rows.push({ label: 'Mastodon', text: card.mastodon, uri: m ? m.profile : null });
  }
  if (card.signal) {
    rows.push({ label: 'Signal', text: card.signal.phone || 'username link', uri: signalURI(card.signal) });
  }
  if (card.calendly) rows.push({ label: 'Calendly', text: card.calendly, uri: calendlyURI(card.calendly) });
  return rows;
}

/** Monospace rows with a copy button: GPG and SSH from the card, the
    Hatband key fingerprint from key 19 or SHA-256 of key 14. */
export function keyRows(card, keyFingerprint) {
  const rows = [];
  if (card.gpgFingerprint) rows.push({ label: 'GPG', text: gpgFingerprintFormatted(card.gpgFingerprint) });
  const ssh = sshDisplay(card.ssh);
  if (ssh) rows.push({ label: 'SSH', text: ssh });
  if (keyFingerprint) rows.push({ label: 'Hatband key', text: keyFingerprintDisplay(keyFingerprint) });
  return rows;
}

export function customRows(card) {
  return card.custom.map((field) => {
    const row = { label: field.label, text: field.value, uri: null, mono: false };
    switch (field.kind) {
      case CustomKind.url: row.uri = field.value; break;
      case CustomKind.email: row.uri = emailURI(field.value); break;
      case CustomKind.phone: row.uri = phoneURI(field.value); break;
      case CustomKind.key: row.mono = true; break;
      default: break;
    }
    return row;
  });
}

export function badgeText(card, signature) {
  switch (signature) {
    case 'verified': return 'signature verified';
    case 'invalid': return 'signature invalid';
    case 'unsupported': return 'unverified (browser lacks Ed25519)';
    default: return card.compact ? 'unsigned (Lock Screen card)' : 'unsigned';
  }
}

/** Everything `textProblem` flags and every path character stripped: a
    name cannot disguise the extension or escape a folder. */
export function vcardFileName(card) {
  const stem = [...(card.name || '')]
    .filter((ch) => textProblem(ch.codePointAt(0)) === null && !'/\\:*?"<>|'.includes(ch))
    .slice(0, 60).join('').trim();
  return (stem || 'card') + '.vcf';
}

function copyButton(doc, env, text) {
  const button = el(doc, 'button', 'copy', 'copy');
  button.setAttribute('type', 'button');
  button.addEventListener('click', () => {
    const clipboard = env.navigator && env.navigator.clipboard;
    if (clipboard) clipboard.writeText(text).catch(() => {});
  });
  return button;
}

function rowList(doc, env, className, rows) {
  const list = el(doc, 'ul', className);
  for (const row of rows) {
    const item = el(doc, 'li', null, el(doc, 'span', 'label', row.label));
    if (row.mono) {
      item.appendChild(el(doc, 'code', null, row.text));
      item.appendChild(copyButton(doc, env, row.text));
    } else {
      item.appendChild(linkNode(doc, row.uri, row.text));
    }
    list.appendChild(item);
  }
  return list;
}

/** `env`: `{ signature, keyFingerprint, url, navigator, File }`. */
export function renderCard(doc, card, env = {}) {
  const article = el(doc, 'article', 'card c' + paletteIndex(card.color));
  article.appendChild(el(doc, 'div', 'band'));

  const header = el(doc, 'header');
  if (card.photo && isJPEG(card.photo)) {
    const img = el(doc, 'img', 'photo');
    img.setAttribute('src', 'data:image/jpeg;base64,' + base64Encode(card.photo));
    img.setAttribute('alt', '');
    header.appendChild(img);
  }
  const names = el(doc, 'div');
  const h1 = el(doc, 'h1', 'name', card.name || '');
  if (card.alias) {
    const glyph = el(doc, 'span', 'alias', ' ✿');
    glyph.setAttribute('title', 'alias');
    h1.appendChild(glyph);
  }
  names.appendChild(h1);
  if (card.company) names.appendChild(el(doc, 'p', 'company', card.company));
  header.appendChild(names);
  article.appendChild(header);

  const channels = channelRows(card);
  if (channels.length) article.appendChild(rowList(doc, env, 'channels', channels));
  const keys = keyRows(card, env.keyFingerprint || null).map((row) => ({ ...row, mono: true }));
  if (keys.length) article.appendChild(rowList(doc, env, 'keys', keys));
  const custom = customRows(card);
  if (custom.length) article.appendChild(rowList(doc, env, 'custom', custom));

  const status = env.signature || 'none';
  const badge = el(doc, 'span', 'badge ' + (status === 'verified' ? 'ok' : status === 'invalid' ? 'bad' : 'plain'),
    badgeText(card, status));
  const meta = 'issued ' + isoDate(dayToCivil(card.issuedDay)) + (card.seq ? ' · seq ' + card.seq : '');
  article.appendChild(el(doc, 'p', 'badges', badge, el(doc, 'span', 'meta', meta)));

  const actions = el(doc, 'p', 'actions');
  const vcf = cardVCard(card);
  const filename = vcardFileName(card);
  const add = el(doc, 'a', 'button', 'Add to contacts');
  add.setAttribute('href', 'data:text/vcard;charset=utf-8,' + encodeURIComponent(vcf));
  add.setAttribute('download', filename);
  const nav = env.navigator;
  if (nav && typeof nav.canShare === 'function' && typeof env.File === 'function') {
    try {
      const file = new env.File([vcf], filename, { type: 'text/vcard' });
      if (nav.canShare({ files: [file] })) {
        add.addEventListener('click', (event) => {
          event.preventDefault();
          nav.share({ files: [file], title: card.name || 'Hatband card' }).catch(() => {});
        });
      }
    } catch {
      // No share sheet: the download link stands.
    }
  }
  actions.appendChild(add);
  if (env.url) {
    const open = el(doc, 'a', 'button', 'Open in Hatband');
    open.setAttribute('href', env.url);
    actions.appendChild(open);
  }
  const store = el(doc, 'a', null, 'App Store');
  store.setAttribute('href', APP_STORE_URL);
  store.setAttribute('rel', 'noreferrer noopener');
  actions.appendChild(store);
  article.appendChild(actions);
  return article;
}

export function renderEmpty(doc) {
  return el(doc, 'section', 'empty',
    el(doc, 'h1', null, 'No fixed abode.'),
    el(doc, 'p', null, 'hatband.link shows a Hatband business card from the link that opened it, decoded in your browser and sent nowhere.'));
}

/** Fixed sentences only; the fragment is never echoed. */
export function errorMessage(error) {
  if (error instanceof HB1Error) {
    switch (error.code) {
      case 'notHatband': return 'Not a Hatband card.';
      case 'unsupportedFormat': return 'This card uses a newer format than this page knows. Open it in the app.';
      case 'tooLarge': return 'This card is too large to be a Hatband card.';
      default: break;
    }
  }
  return 'This card could not be read.';
}

export function renderError(doc, error) {
  return el(doc, 'p', 'error', errorMessage(error));
}

export async function main(win) {
  const doc = win.document;
  const root = doc.getElementById('app');
  const hash = win.location.hash || '';
  if (hash === '' || hash === '#') {
    root.appendChild(renderEmpty(doc));
    return;
  }
  let map;
  let card;
  try {
    map = hb1DecodeURL(hash);
    card = cardFromMap(map);
  } catch (error) {
    root.appendChild(renderError(doc, error));
    return;
  }
  const subtle = (win.crypto && win.crypto.subtle) || null;
  const signature = await signatureStatus(card, map, subtle);
  let keyFingerprint = card.keyFingerprint;
  if (card.publicKey && subtle) keyFingerprint = await sha256(card.publicKey, subtle);
  if (card.name) doc.title = card.name + ' · Hatband';
  root.appendChild(renderCard(doc, card, {
    signature, keyFingerprint, url: win.location.href, navigator: win.navigator, File: win.File,
  }));
}

if (typeof window !== 'undefined' && window.document) {
  main(window).catch(() => {
    const root = window.document.getElementById('app');
    root.textContent = '';
    root.appendChild(renderError(window.document, null));
  });
}
