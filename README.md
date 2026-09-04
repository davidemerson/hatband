# Hatband

A business card in your hat. Hatband shows your contact details as a QR code, from the iPhone Lock Screen if you like, and remembers where you met the people you scan. No account, no server, nothing collected.

Named for the card Bloom keeps in his hatband in *Ulysses*, bearing the name of his other self, Henry Flower.

## Status

The format library, its test vectors and the fallback site exist; the iPhone app does not yet.

## Layout

| Path | Contents | License |
|---|---|---|
| `Packages/HatbandCore` | Model, HB1 codec, crypto, QR encoder. Swift package; builds on Linux and Apple platforms. | Apache-2.0 |
| `spec` | HB1 wire format and test vectors. | CC-BY-4.0 |
| `site` | The static page at hatband.link. | GPL-3.0-or-later |
| `Hatband`, `HatbandWidgets` | The iOS app and its Live Activity extension. | GPL-3.0-or-later, see `COPYING.iOS` |

## Build and test

Core, on Linux or macOS:

```
swift test --package-path Packages/HatbandCore
```

The app requires Xcode 26 and is generated from `project.yml` with XcodeGen.

## Wire format (HB1)

A card is a CBOR map with small integer keys, encoded deterministically (RFC 8949 §4.2.1). It travels three ways:

- **QR**: `https://hatband.link/#1<base32>` — the fragment is a format tag and unpadded Base32 of the map. The fragment never reaches the host; the page at hatband.link decodes it in the browser for people without the app.
- **File**: `.hatband`, the map behind the magic bytes `HB1\0`.
- **Lock Screen**: the same URL form, restricted to the compact tier (name, up to two channels, persona id, key fingerprint) so it fits about QR version 10 at 23 mm.

| Key | Field | Type | Notes |
|---|---|---|---|
| 0 | flags | uint | bit 0 compact tier, bit 1 photo available, bit 2 alias card, bit 3 website is http |
| 1 | name | text | |
| 2 | company | text | |
| 3 | phone | text | E.164 |
| 4 | email | text | |
| 5 | website | text | host and path, no scheme |
| 6 | github | text | username |
| 7 | linkedin | text | slug after `/in/` |
| 8 | mastodon | text | `user@instance` |
| 9 | signal | bytes or text | 48-byte username link, or E.164 |
| 10 | calendly | text | path after `calendly.com/` |
| 11 | ssh | bytes | kind byte then raw key; RSA carries kind then SHA-256 fingerprint |
| 12 | gpg fingerprint | bytes | 20 (v4) or 32 (v6) |
| 13 | custom | array | `[label, value, kind]`; kind 0 text, 1 url, 2 email, 3 phone, 4 key |
| 14 | public key | bytes 32 | Ed25519, per persona |
| 15 | signature | bytes 64 | over the map without key 15, domain `hatband-card-v1` |
| 16 | persona id | bytes 8 | random; identifies re-scans |
| 17 | issued day | uint | days since 2020-01-01 |
| 18 | color | uint | palette index |
| 19 | key fingerprint | bytes 8 | compact tier only |
| 20 | photo | bytes | JPEG; file and URL only |
| 21 | seq | uint | update counter; a recipient accepts only a higher one |
| 22 | min reader | uint | |
| 23 | gpg key | bytes | binary certificate; file and URL only; must hash to key 12 |

Readers ignore unknown keys. Keys 24 and up are reserved. Every form is signed over exactly its own content; a full card is about 256 bytes, the ceiling for any form is 32 KB. Test vectors live in `spec/vectors`.

## Core

`Packages/HatbandCore` is the whole format and holds no UI. It builds on Linux, where its tests run first.

- **Model.** One `Profile` holds every field in stored form. A `Persona` selects fields from it, or for an alias from a profile of its own, and carries a colour, an 8-byte id, a key index and up to two Lock Screen channels. `CardBuilder` renders a persona for a form: the Lock Screen tier is compact and unsigned, the full QR drops the photo and GPG key, the file form carries everything.
- **Codec.** Deterministic CBOR (RFC 8949 §4.2.1; decoding is strict: shortest forms, ordered keys, no tags or floats, text compared by bytes), unpadded Base32, the HB1 URL and file forms, and a `Budget` that reports the QR version a card needs. Version 10 at medium correction is the Lock Screen ceiling, 25 the full-screen one; a name-only card is version 5.
- **Crypto.** One 32-byte seed. Persona keys are HKDF-SHA256 of it with salt `hatband` and info `hatband/v1/persona/<index>`, derived on demand, never stored. `Card.signed(with:)` signs `hatband-card-v1` plus the canonical map; verification refuses small-order and non-canonical public keys. Exports are PBKDF2-HMAC-SHA256 (600 000 rounds) into ChaCha20-Poly1305, in a CBOR container whose header is authenticated; passphrases are six EFF words. Signatures may differ between runs, so compare them by verifying.
- **QR.** An ISO 18004 encoder written for this project: segments, Reed–Solomon, every function pattern, masks scored by the reference N1–N4 rules. The URL prefix goes in a byte segment and the Base32 fragment in an alphanumeric one, at 5.5 bits per character. It renders SVG, PBM and path data; the app draws modules itself.
- **Vectors.** `spec/vectors/cards.json` holds ten cards with their CBOR, URL, file bytes, signing bytes, keys and signatures, generated from the seed `00…1f` by `scripts/gen-vectors.sh`. Every implementation is tested against it; CI regenerates it and fails on any drift.

## Security

- **Assets.** Your card; the people you scanned and where you met; your signing seed.
- **Adversaries.** A bystander photographing your Lock Screen. A thief with your phone, locked or unlocked. A contact who turns hostile. A hostile card. Anyone who can read a backup.
- **Mitigations.** The Lock Screen shows a compact card, name only by default, that expires; compact and mirrored views carry no card at all. Received cards live in a Class A store, sealed under a key the app lock guards, and stay out of backups unless you opt in. Every scanned payload is parsed strictly and screened for hidden characters, look-alike domains and disallowed links before you see it; nothing opens by itself. An update is accepted only when signed by the pinned key with a higher sequence number. Nothing leaves the phone unless you tap a button that names where it goes.
- **Non-goals.** A jailbroken or already compromised phone. Someone who photographs your card and keeps it: that is what a card is for.

Report a vulnerability privately at https://github.com/davidemerson/hatband/security/advisories/new. The site's `security.txt` points here.

## Site

hatband.link is one static page. A QR or link carries the card in the URL fragment, which browsers never send; the page decodes it in JavaScript, verifies the signature with WebCrypto and offers Add to contacts as a vCard. It loads nothing from anywhere, and its Content-Security-Policy allows only its own hashed inline code. The host sees a request's address, user agent and time, never the card.

Hosting is a private S3 bucket behind CloudFront with logging off, described in `infra/site.yaml`. `infra/deploy-stack.sh` creates the stack; `scripts/deploy-site.sh` uploads the page with explicit content types and invalidates the cache. Tests: `node --test site/test`.

## License

GPL-3.0-or-later for the app, with the App Store permission in `COPYING.iOS`. Components carry their own license as listed above. Contributions are accepted under the Developer Certificate of Origin: sign off your commits.
