# Hatband

A business card in your hat. Hatband shows your contact details as a QR code, from the iPhone Lock Screen if you like, and remembers where you met the people you scan. No account, no server, nothing collected.

Named for the card Bloom keeps in his hatband in *Ulysses*, bearing the name of his other self, Henry Flower.

## Status

The format library, its test vectors, the fallback site and the iPhone app exist. The app has only ever been built by CI; it has not run on a phone.

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

## App

- **Card.** The selected persona's signed card as a QR in a white panel, brightness raised while it shows and hidden while the screen is recorded. A byte meter warns past version 20 and offers the file form when no code fits. Share as a hatband.link link or a `.hatband` file; print as SVG, PNG or a PDF card. "What's in this QR" lists every field and the exact size of the code on screen.
- **Profile and personas.** Every field commits through the library's normalizers and validators, so nothing unnormalized is stored. SSH keys are pasted as an `authorized_keys` line; a GPG certificate is kept only when it hashes to the typed fingerprint; a headshot is reduced to 256 pixels and 12 KB with its Exif stripped. A persona shares a subset of the profile under its own derived key and colour, or is an alias with a profile of its own. Key indices are never reused; `seq` rises only when a card's content changes.
- **Lock Screen.** "Share my card" starts a Live Activity for 30 minutes, 2 or 8 hours. Only the Lock Screen presentation carries the compact QR and, if you choose, your name; the Dynamic Island, Watch, CarPlay and paired-Mac presentations show a hat glyph and "Sharing" at most. The activity goes stale at its end time and stopping in the app ends it at once. Always-On shows "Tap to show card" unless you allow the QR there. The Home Screen widget is opt-in and reads one file in the App Group container, deleted when the widget is turned off.
- **Scanning.** The camera reads QR codes only; a screenshot goes through Vision instead. Every payload is screened field by field before the review sheet shows it: rejected fields are listed, warnings stay on their field, and any field can be switched off before saving. Saving notes one reduced-accuracy fix, about a city, with a place, a note and tags. Where draws one circle per meeting over a map that loads only when the tab opens. Forget deletes at once with ten seconds to undo.
- **Trust.** A person is pinned to the first key seen for their persona id, or to the 8-byte fingerprint of a Lock Screen card. A later card updates the record only under the pinned key with a higher sequence number; a different key is a warning and replaces nothing unless you choose "Trust new key". A GPG certificate riding in a file or link is kept only when it hashes to the card's fingerprint.
- **Storage and lock.** One SwiftData store in a Class A directory. Your own card sits in one plaintext blob, so showing it never prompts; each scanned person is AES-GCM sealed under a 32-byte key in the Keychain, bound to its persona id. App lock, on by default, puts that key behind Face ID or the passcode; People, Where and Settings stay locked until then, and the key leaves memory in the background. The store stays out of backups unless you opt in, and the toggle says what that means without Advanced Data Protection.
- **Export, import, erase.** A `.hatband-export` holds the seed, your card and every person, sealed under six EFF words or a passphrase of your own. Restore makes a fresh install into that phone; merge keeps the local seed and pins and takes the higher `seq`. Erase deletes the Keychain keys first, then activities, the widget file (and reloads the widget), the share-sheet temp files and the store.
- **What leaves the phone.** Nothing, unless you tap a button that names its host: WKD, keys.openpgp.org, GitHub and a Mastodon instance for key and link checks; Safari for a tapped link; Apple's map tiles for the area around your coarse meeting places when the Where tab opens. One ephemeral session, no cookies, 15 seconds, TLS 1.2, same-host redirects only, 256 KB. `scripts/lint-boundaries.sh` keeps networking, storage, pasteboard, screen and location behind one file each and forbids UserDefaults, so `PrivacyInfo.xcprivacy` declares nothing. MetricKit diagnostics stay on the phone and show in About.
- **Building and testing.** `brew install xcodegen && xcodegen generate`, then Xcode 26; `Info.plist` and the entitlements are generated, never committed. `xcodebuild test -project Hatband.xcodeproj -scheme Hatband -destination 'platform=iOS Simulator,name=iPhone 17'`. CI lints the boundaries, generates, tests, and refuses any package beyond swift-crypto and swift-asn1. Device validation, TestFlight and the export-compliance question are still open.

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
- **Interop.** `Normalize` turns pasted input into stored forms (E.164 phone, lowercase-domain email, scheme-less website with an http flag, GitHub user, LinkedIn slug, `user@instance`, Calendly path, GPG fingerprint) and `CanonicalURI` renders them as links; `SSHPublicKey` reads OpenSSH lines and writes `authorized_keys`, `allowed_signers` and randomart; `VCard` builds vCard 3.0 for Contacts. Everything parses Unicode scalars, never grapheme clusters, so a combining mark or joiner can neither hide a delimiter nor ride into a stored value. Hostnames follow IDNA 2008's shape: letters, digits, marks and hyphens, 63 octets a label and 253 in all.
- **Validate.** Every scanned field passes `FieldValidator` under `Limits.qr` or `Limits.file` before any UI sees it and comes back `ok`, `warning` or `reject`; nothing is repaired. Rejected: controls, bidi controls, format and default-ignorable characters (a variation selector after its base, a joiner inside an emoji sequence and a non-joiner inside an Arabic word excepted), values with no visible base, IP addresses in any spelling, `mailto` headers other than subject and body, and links outside https, http, mailto, tel, acct and OPENPGP4FPR. Hosts are judged label by label: a label whose every letter has an ASCII twin is a homograph (аpple, gіthub, also behind punycode) and is refused naming the ASCII it imitates; a label that keeps a letter no ASCII host has (москва, ελλάδα) is an honest IDN and merely warned. Which characters count as assigned follows the reader's Unicode tables, so a very new emoji in a name may be refused by an older phone.
- **Vectors.** `spec/vectors/cards.json` holds ten cards with their CBOR, URL, file bytes, signing bytes, keys and signatures, generated from the seed `00…1f` by `scripts/gen-vectors.sh`. Every implementation is tested against it; CI regenerates it and fails on any drift.

## Security

- **Assets.** Your card; the people you scanned and where you met; your signing seed.
- **Adversaries.** A bystander photographing your Lock Screen. A thief with your phone, locked or unlocked. A contact who turns hostile. A hostile card. Anyone who can read a backup.
- **Mitigations.** The Lock Screen shows a compact card, name only by default, that expires; compact and mirrored views carry no card at all. Received cards live in a Class A store, sealed under a key the app lock guards, and stay out of backups unless you opt in. Every scanned payload is parsed strictly and screened for hidden characters, look-alike domains and disallowed links before you see it; nothing opens by itself. An update is accepted only when signed by the pinned key with a higher sequence number. Nothing leaves the phone unless you tap a button that names where it goes.
- **Non-goals.** A jailbroken or already compromised phone. Someone who photographs your card and keeps it: that is what a card is for.

Report a vulnerability privately at https://github.com/davidemerson/hatband/security/advisories/new. The site's `security.txt` points here.

## Site

hatband.link is one static page. A QR or link carries the card in the URL fragment, which browsers never send; the page decodes it in JavaScript, verifies the signature with WebCrypto and offers Add to contacts as a vCard. It loads nothing from anywhere, and its Content-Security-Policy allows only its own hashed inline code. The host sees a request's address, user agent and time, never the card.

Hosting is a private S3 bucket behind CloudFront with logging off, described in `infra/site.yaml`. `node site/build.mjs` inlines `site/src` into `site/index.html` and writes the CSP hashes; the output is committed and CI checks it is current. `infra/deploy-stack.sh` creates the stack; `scripts/deploy-site.sh` uploads the pages with explicit content types and invalidates the cache. Tests: `node --test site/test/*.test.mjs`.

## License

GPL-3.0-or-later for the app, with the App Store permission in `COPYING.iOS`. Components carry their own license as listed above. Contributions are accepted under the Developer Certificate of Origin: sign off your commits.
