/* The least DOM page.js needs, so node:test can render without a browser.
   innerHTML and its relatives throw: text has to arrive as text nodes. */

export class Node {
  constructor(doc) {
    this.ownerDocument = doc;
    this.childNodes = [];
    this.parentNode = null;
  }

  appendChild(node) {
    if (node instanceof DocumentFragment) {
      for (const child of node.childNodes.splice(0)) this.appendChild(child);
      return node;
    }
    if (node.parentNode) node.parentNode.removeChild(node);
    node.parentNode = this;
    this.childNodes.push(node);
    return node;
  }

  removeChild(node) {
    const index = this.childNodes.indexOf(node);
    if (index >= 0) this.childNodes.splice(index, 1);
    node.parentNode = null;
    return node;
  }

  append(...nodes) {
    for (const node of nodes) this.appendChild(typeof node === 'string' ? this.ownerDocument.createTextNode(node) : node);
  }

  get textContent() {
    return this.childNodes.map((node) => node.textContent).join('');
  }

  set textContent(value) {
    this.childNodes = [];
    if (value !== '') this.appendChild(this.ownerDocument.createTextNode(value));
  }

  get innerHTML() { throw new Error('innerHTML is forbidden'); }
  set innerHTML(_) { throw new Error('innerHTML is forbidden'); }
  get outerHTML() { throw new Error('outerHTML is forbidden'); }
  set outerHTML(_) { throw new Error('outerHTML is forbidden'); }
  insertAdjacentHTML() { throw new Error('insertAdjacentHTML is forbidden'); }

  * walk() {
    yield this;
    for (const child of this.childNodes) yield* child.walk();
  }
}

export class TextNode extends Node {
  constructor(doc, data) {
    super(doc);
    this.nodeType = 3;
    this.nodeName = '#text';
    this.data = String(data);
  }

  get textContent() { return this.data; }
  set textContent(value) { this.data = String(value); }
}

export class DocumentFragment extends Node {
  constructor(doc) {
    super(doc);
    this.nodeType = 11;
    this.nodeName = '#document-fragment';
  }
}

export class Element extends Node {
  constructor(doc, tag) {
    super(doc);
    this.nodeType = 1;
    this.tagName = String(tag).toUpperCase();
    this.nodeName = this.tagName;
    this.attributes = new Map();
    this.listeners = new Map();
  }

  setAttribute(name, value) { this.attributes.set(String(name).toLowerCase(), String(value)); }
  getAttribute(name) {
    const key = String(name).toLowerCase();
    return this.attributes.has(key) ? this.attributes.get(key) : null;
  }
  hasAttribute(name) { return this.attributes.has(String(name).toLowerCase()); }

  get className() { return this.getAttribute('class') ?? ''; }
  set className(value) { this.setAttribute('class', value); }
  get classList() {
    const names = () => this.className.split(/\s+/).filter(Boolean);
    return {
      contains: (name) => names().includes(name),
      add: (...more) => { this.className = [...new Set([...names(), ...more])].join(' '); },
    };
  }
  get id() { return this.getAttribute('id') ?? ''; }
  set id(value) { this.setAttribute('id', value); }
  get href() { return this.getAttribute('href') ?? ''; }
  set href(value) { this.setAttribute('href', value); }
  get title() { return this.getAttribute('title') ?? ''; }
  set title(value) { this.setAttribute('title', value); }
  get children() { return this.childNodes.filter((node) => node instanceof Element); }

  addEventListener(type, listener) {
    if (!this.listeners.has(type)) this.listeners.set(type, []);
    this.listeners.get(type).push(listener);
  }

  /** Fires listeners; returns false when one called preventDefault. */
  dispatch(type, extra = {}) {
    let prevented = false;
    const event = { type, target: this, preventDefault: () => { prevented = true; }, ...extra };
    for (const listener of this.listeners.get(type) || []) listener(event);
    return !prevented;
  }

  getElementsByTagName(tag) {
    const name = tag.toUpperCase();
    return elements(this).filter((node) => node !== this && node.tagName === name);
  }

  getElementsByClassName(name) {
    return elements(this).filter((node) => node !== this && node.classList.contains(name));
  }
}

export class Document {
  constructor() {
    this.title = '';
    this.documentElement = new Element(this, 'html');
    this.body = new Element(this, 'body');
    this.documentElement.appendChild(this.body);
  }

  createElement(tag) { return new Element(this, tag); }
  createTextNode(data) { return new TextNode(this, data); }
  createDocumentFragment() { return new DocumentFragment(this); }
  getElementById(id) { return elements(this.documentElement).find((node) => node.getAttribute('id') === id) ?? null; }
  getElementsByTagName(tag) { return this.documentElement.getElementsByTagName(tag); }
}

export function elements(root) {
  return [...root.walk()].filter((node) => node instanceof Element);
}

export function texts(root) {
  return [...root.walk()].filter((node) => node instanceof TextNode).map((node) => node.data);
}

const escapeText = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const escapeAttr = (s) => escapeText(s).replace(/"/g, '&quot;');

/** HTML with escaping, the way a browser would serialise the tree. */
export function serialize(node) {
  if (node instanceof TextNode) return escapeText(node.data);
  if (node instanceof DocumentFragment) return node.childNodes.map(serialize).join('');
  const attrs = [...node.attributes].map(([k, v]) => ` ${k}="${escapeAttr(v)}"`).join('');
  const tag = node.tagName.toLowerCase();
  return `<${tag}${attrs}>${node.childNodes.map(serialize).join('')}</${tag}>`;
}

/** A window with `#app` in place, as index.html has it. */
export function makeWindow({ hash = '', href = 'https://hatband.link/' + hash, navigator = {}, crypto = globalThis.crypto, File = undefined } = {}) {
  const document = new Document();
  const app = document.createElement('main');
  app.id = 'app';
  document.body.appendChild(app);
  return { document, location: { hash, href }, navigator, crypto, File };
}
