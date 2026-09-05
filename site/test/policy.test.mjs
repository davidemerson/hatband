import { test } from 'node:test';
import assert from 'node:assert/strict';
import { OK, URL_MAX_BYTES, domainVerdict, isE164, isTappable, looksLikeASCII, reject, textProblem, urlScheme, urlVerdict, warning } from '../src/hb1.js';

const fp40 = 'D8692E4DD0D4B4C7A1E30A1F3F1B2C4D5E6F7A8B';
const fp64 = fp40 + '0123456789ABCDEF01234567';
const check = (cases) => { for (const [url, verdict] of cases) assert.deepEqual(urlVerdict(url), verdict, url); };

test('accepts web links, http with a warning', () => check([
  ['https://github.com', OK], ['https://github.com/', OK], ['https://github.com/lbloom?tab=repositories#top', OK],
  ['HTTPS://GitHub.com', OK], ['https://host:443', OK], ['https://host:1', OK], ['https://host:65535/x', OK], ['https://127.0.0.1', OK],
  ['https://example.com/a%2Fb%20c', OK], ['https://example.com/Straße', OK], ["https://example.com/~bloom/(1),2;3=4&5+6*7!8$9'", OK],
  ['https://de.wikipedia.org/wiki/Ulysses_(Roman)', OK], ['https://signal.me/#p/+1555', OK], ['https://signal.me/#eu/abc-_=', OK],
  ['https://matrix.to/#/@bloom:example.ie', OK],
  ['http://example.com', warning('not encrypted')], ['HTTP://example.com/x', warning('not encrypted')],
  ['https://xn--mnchen-3ya.de', warning('punycode host label')], ['http://xn--mnchen-3ya.de', warning('punycode host label; not encrypted')],
]));

test('rejects other schemes', () => check([
  ['javascript:alert(1)', reject('scheme not allowed: javascript')], ['JAVASCRIPT:alert(1)', reject('scheme not allowed: javascript')],
  ['JAVASCRIPT:', reject('scheme not allowed: javascript')], ['data:text/html,<script>', reject('scheme not allowed: data')],
  ['file:///etc/passwd', reject('scheme not allowed: file')], ['ftp://example.com', reject('scheme not allowed: ftp')],
  ['sgnl://signal.me/#p/+1555', reject('scheme not allowed: sgnl')], ['ssh://git@github.com', reject('scheme not allowed: ssh')],
  ['xmpp:a@b', reject('scheme not allowed: xmpp')], ['hatband:x', reject('scheme not allowed: hatband')], ['a+b-c.d:x', reject('scheme not allowed: a+b-c.d')],
  ['example.com', reject('missing scheme')], ['//example.com', reject('missing scheme')], ['', reject('missing scheme')], [':', reject('missing scheme')],
  ['1http://x', reject('missing scheme')], ['example.com/path:80', reject('missing scheme')], ['ht tp://x', reject('whitespace')],
  ['z'.repeat(100) + ':', reject('scheme not allowed: ' + 'z'.repeat(32))],
]));

test('rejects hidden characters', () => check([
  [' https://x', reject('whitespace')], ['https://x ', reject('whitespace')], ['https://exam ple.com', reject('whitespace')],
  ['https://example.com/path with space', reject('whitespace')], ['https://x .com', reject('whitespace')], ['https://x　.com', reject('whitespace')],
  ['https://x\n', reject('control character')], ['https://x\0', reject('control character')], ['https://x​.com', reject('invisible character')],
  ['https://x﻿.com', reject('invisible character')], ['https://x‮', reject('bidirectional control character')],
  ['https://x', reject('unassigned or private-use character')], ['https://x﷐', reject('unassigned or private-use character')],
]));

test('rejects bad authorities', () => check([
  ['https://user:pw@host', reject('userinfo in URL')], ['https://user@host', reject('userinfo in URL')], ['https://@host', reject('userinfo in URL')],
  ['https://host:0', reject('invalid port')], ['https://host:65536', reject('invalid port')], ['https://host:', reject('invalid port')],
  ['https://host:4a', reject('invalid port')], ['https://host:443:1', reject('invalid port')], ['https://host:123456', reject('invalid port')],
  ['https://[::1]', reject('invalid host label')], ['https://[::1]:443', reject('invalid host label')],
  ['https://', reject('empty host')], ['https:///path', reject('empty host')], ['https://?q', reject('empty host')],
  ['https:example.com', reject('malformed URL')], ['https:/example.com', reject('malformed URL')], ['https:', reject('malformed URL')],
  ['https://gіthub.com', reject('non-ASCII host, looks like “github.com”')], ['https://аpple.com/', reject('non-ASCII host, looks like “apple.com”')],
  ['https://münchen.de', reject('non-ASCII host')], ['https://-example.com', reject('invalid host label')], ['https://example-.com', reject('invalid host label')],
  ['https://example..com', reject('invalid host label')], ['https://.example.com', reject('invalid host label')], ['https://example.com.', reject('invalid host label')],
  ['https://ex_ample.com', reject('invalid host label')], ['https://example.com\\evil', reject('invalid host label')],
  ['https://' + 'a'.repeat(254), reject('host over 253 bytes')], ['https://' + 'a'.repeat(64) + '.com', reject('invalid host label')],
]));

test('rejects bad paths', () => check([
  ['https://example.com/<script>', reject('invalid character in URL')], ['https://example.com/"', reject('invalid character in URL')],
  ['https://example.com/a|b', reject('invalid character in URL')], ['https://example.com/a\\b', reject('invalid character in URL')],
  ['https://example.com/a^b', reject('invalid character in URL')], ['https://example.com/a`b', reject('invalid character in URL')],
  ['https://example.com/{a}', reject('invalid character in URL')], ['https://example.com/%zz', reject('bad percent-encoding')],
  ['https://example.com/%2', reject('bad percent-encoding')], ['https://example.com/%', reject('bad percent-encoding')],
  ['https://example.com/?%G0', reject('bad percent-encoding')],
]));

test('judges mailto', () => check([
  ['mailto:a@b', OK], ['mailto:a@b?subject=x', OK], ['mailto:a@b?subject=x&body=y%20z', OK], ['mailto:henry.flower@example.ie', OK],
  ['mailto:henry+flower@example.ie', OK], ['MAILTO:A@B', OK], ['mailto:a@xn--mnchen-3ya.de', warning('punycode host label')],
  ['mailto:a@b?subject=x y', reject('whitespace')], ['mailto:a', reject('not an email address')], ['mailto:', reject('not an email address')],
  ['mailto:a@b@c', reject('not an email address')], ['mailto:@b', reject('not an email address')], ['mailto:.a@b', reject('not an email address')],
  ['mailto:a.@b', reject('not an email address')], ['mailto:a..b@c', reject('not an email address')], ['mailto://a@b', reject('not an email address')],
  ['mailto:a(b)@c', reject('not an email address')], ['mailto:"a"@c', reject('not an email address')], ['mailto:a@', reject('empty host')],
  ['mailto:a@-b', reject('invalid host label')], ['mailto:a@b?%zz', reject('bad percent-encoding')], ['mailto:ünï@b', reject('non-ASCII character')],
  ['mailto:a@münchen.de', reject('non-ASCII host')], ['mailto:a@gіthub.com', reject('non-ASCII host, looks like “github.com”')],
  ['mailto:' + 'a'.repeat(65) + '@b', reject('not an email address')],
]));

test('judges tel', () => check([
  ['tel:+1-555', OK], ['tel:+15551234567', OK], ['tel:+353871234567', OK], ['tel:+1(555)123.4567', OK], ['tel:+123456789012345', OK],
  ['TEL:+1555', OK], ['tel:+12', OK], ['tel:+1 555', reject('whitespace')], ['tel:5551234', reject('not an E.164 number')],
  ['tel:+0123', reject('not an E.164 number')], ['tel:+1', reject('not an E.164 number')], ['tel:+1234567890123456', reject('not an E.164 number')],
  ['tel:+1-555;ext=1', reject('not an E.164 number')], ['tel:++1555', reject('not an E.164 number')], ['tel:+1555x', reject('not an E.164 number')],
  ['tel:', reject('not an E.164 number')], ['tel:＋１５５５', reject('not an E.164 number')],
]));

test('judges acct and OpenPGP fingerprints, neither tappable', () => {
  check([
    ['acct:bloom@merveilles.town', OK], ['acct:henry_flower@example.ie', OK], ['acct:bloom', reject('not an acct address')],
    ['acct:@x', reject('not an acct address')], ['acct:bloom@', reject('empty host')],
    ['acct:bloom@mаstodon.social', reject('non-ASCII host, looks like “mastodon.social”')],
    ['OPENPGP4FPR:' + fp40, OK], ['openpgp4fpr:' + fp40.toLowerCase(), OK], ['OPENPGP4FPR:' + fp64, OK],
    ['OPENPGP4FPR:' + fp40.slice(0, -1), reject('not an OpenPGP fingerprint')], ['OPENPGP4FPR:' + fp40 + '0', reject('not an OpenPGP fingerprint')],
    ['OPENPGP4FPR:' + fp40.slice(0, -1) + 'G', reject('not an OpenPGP fingerprint')], ['OPENPGP4FPR:', reject('not an OpenPGP fingerprint')],
    ['OPENPGP4FPR:' + fp40 + ' ', reject('whitespace')],
  ]);
  assert.equal(isTappable('OPENPGP4FPR:' + fp40), false);
  assert.equal(isTappable('acct:bloom@merveilles.town'), false);
});

test('decides tappability', () => {
  for (const [url, tappable] of [
    ['https://github.com', true], ['http://example.com', true], ['mailto:a@b', true], ['tel:+1555', true], ['https://xn--mnchen-3ya.de', true],
    ['acct:bloom@merveilles.town', false], ['javascript:alert(1)', false], ['https://gіthub.com', false], ['https://user@host', false],
    ['', false], [' https://x', false], ['github.com', false], ['data:text/html,<script>', false], ['https://signal.me/#eu/abc-_=', true],
  ]) assert.equal(isTappable(url), tappable, url);
});

test('the byte cap comes first', () => {
  const prefix = 'https://example.com/';
  const exact = prefix + 'a'.repeat(URL_MAX_BYTES - prefix.length);
  assert.deepEqual(urlVerdict(exact), OK);
  assert.deepEqual(urlVerdict(exact + 'a'), reject('over 2048 bytes'));
  const multibyte = prefix + 'a'.repeat(URL_MAX_BYTES - prefix.length - 1) + 'é';
  assert.deepEqual(urlVerdict(multibyte), reject('over 2048 bytes'));
  assert.deepEqual(urlVerdict('‮'.repeat(1000)), reject('over 2048 bytes'));
});

test('scheme parsing, E.164, hosts and look-alikes', () => {
  assert.equal(urlScheme('https://x'), 'https');
  assert.equal(urlScheme('HTTPS://x'), 'https');
  assert.equal(urlScheme('a+b-c.d:'), 'a+b-c.d');
  for (const bad of ['+a:', 'a b:', 'a/b:', ':x', '']) assert.equal(urlScheme(bad), null);
  for (const good of ['+12', '+123456789012345']) assert.ok(isE164(good));
  for (const bad of ['+1', '+1234567890123456', '+0', '12', '', '+', '+-1', '+1 2']) assert.ok(!isE164(bad));
  assert.deepEqual(domainVerdict('GitHub.COM'), OK);
  assert.deepEqual(domainVerdict('xn--'), reject('invalid host label'));
  assert.deepEqual(domainVerdict('xn-ab'), OK);
  assert.deepEqual(domainVerdict('XN--a'), warning('punycode host label'));
  assert.equal(looksLikeASCII('gіthub'), 'github');
  assert.equal(looksLikeASCII('ｇithub。com'), 'github.com');
  assert.equal(looksLikeASCII('plain'), null);
  assert.equal(textProblem(0x41), null);
  assert.equal(textProblem(0x85), 'control character');
  assert.equal(textProblem(0xe0001), 'invisible character');
  assert.equal(textProblem(0xd800), 'unassigned or private-use character');
  assert.equal(textProblem(0x10fffe), 'unassigned or private-use character');
});
