# Hatband

Hatband shows your contact details as a QR code, from the iPhone Lock Screen if you like, and remembers where you met the people you scan. No account, no server, nothing collected.

Named for the card Bloom keeps in his hatband in *Ulysses*, bearing the name of his other self, Henry Flower.

## Status

The format library, its vectors, the iPhone app and the site at hatband.link all exist. The app runs on a phone and has been through TestFlight. What device testing showed is under Validation.

## Layout

| Path | Contents | License |
|---|---|---|
| `Packages/HatbandCore` | Model, HB1 codec, crypto, QR encoder. Swift package; builds on Linux and Apple platforms. | Apache-2.0 |
| `spec` | Test vectors for the wire format, which is specified below. | CC-BY-4.0 |
| `site` | The static page at hatband.link. | GPL-3.0-or-later; the Jost faces it carries are OFL 1.1, `site/fonts/Jost-OFL.txt` |
| `Hatband`, `HatbandWidgets`, `HatbandMessages` | The iOS app, its Live Activity extension and its Messages extension. | GPL-3.0-or-later, see `COPYING.iOS` |

## Build and test

```
swift test --package-path Packages/HatbandCore          # core, Linux or macOS
brew install xcodegen && xcodegen generate              # writes Hatband.xcodeproj
xcodebuild test -project Hatband.xcodeproj -scheme Hatband \
  -destination 'platform=iOS Simulator,name=iPhone 17'
node --test site/test/*.test.mjs                        # site
sh scripts/lint-boundaries.sh --no-stubs
```

The app needs Xcode 26. `project.yml` is the only source of the project: `Hatband.xcodeproj`, every `Info.plist` and every entitlements file are generated and never committed. CI lints the boundaries, generates, tests, and refuses any package beyond swift-crypto and swift-asn1. `ITSAppUsesNonExemptEncryption` is false, on the publicly-available-source exemption.

## App

- **Card.** Your selected persona as a QR code. Brightness rises while it shows; the code hides while the screen is recorded. Share it as a hatband.link URL or a `.hatband` file, or print it as SVG, PNG or a PDF card. "What's in this QR" lists every field and the code's size on screen.
- **Profile and personas.** Fields commit through the library's normalizers, so nothing unnormalized is stored. A persona shares a subset of your profile under its own derived key and colour, or is an alias with a profile of its own. Key indices are never reused. `seq` rises only when a card's content changes.
- **Lock Screen.** "Share my card" runs a Live Activity for 30 minutes, 2 hours or 8. Only the Lock Screen presentation carries the QR; the Dynamic Island, Watch, CarPlay and paired Mac show a hat glyph at most. The Home Screen widget is opt-in and reads one file in the App Group container.
- **Messages.** Hatband appears in the Messages `+` menu. The card goes into the conversation as a bubble rather than a link, so nothing truncates it. A recipient with the app lands on the review sheet; one without gets hatband.link.
- **Scanning.** The camera reads QR codes; a screenshot goes through Vision. Every payload is screened field by field before you see it, and any field can be switched off before saving. Saving notes one reduced-accuracy fix, about a city. Forget deletes at once, with ten seconds to undo.
- **Trust.** A person is pinned to the first key seen for their persona id. A later card updates the record only under that key with a higher `seq`; a different key is a warning and replaces nothing unless you accept it. A GPG certificate is kept only when it hashes to the card's fingerprint.
- **Storage and lock.** One SwiftData store in a Class A directory. Your own card is plaintext, so showing it never prompts; each scanned person is AES-GCM sealed under a Keychain key bound to their persona id. App lock, on by default, puts that key behind Face ID or the passcode. The store stays out of backups unless you opt in. Two files sit outside it in the App Group container, for the widget and the Messages extension; both are excluded from backups and both go when you erase. Neither extension can sign a card, because the seed never leaves the app.
- **Export, import, erase.** A `.hatband-export` holds the seed, your card and every person, sealed under six EFF words or a passphrase of your own. Restore replaces; merge keeps the local seed and pins and takes the higher `seq`. Erase deletes the Keychain keys first, then the activities, the widget file, the share-sheet temporaries and the store.
- **What leaves the phone.** Nothing, unless you tap a button that names its host: WKD, keys.openpgp.org, GitHub and Mastodon for key and link checks; Safari for a tapped link; Apple's map tiles when the Where tab opens. One ephemeral session: no cookies, 15 seconds, TLS 1.2, same-host redirects, 256 KB. `scripts/lint-boundaries.sh` keeps networking, storage, pasteboard, screen and location behind one file each and forbids `UserDefaults`, so `PrivacyInfo.xcprivacy` declares nothing.

## Validation

Measured on an iPhone 15 Pro, iOS 26.6.1, Xcode 26.6. Lock Screen symbols were read from a display calibrated against a ruler at the Live Activity's geometry: a 136 pt panel, 6 pt of padding, a two-module quiet zone.

| Card | Version | Module | Read at |
|---|---|---|---|
| Name only, the default | 5 | 0.50 mm | 10 cm |
| Two channels | 8 | 0.39 mm | 10 cm |
| The most the trim loop allows | 10 | 0.34 mm | 10 cm |
| The same with the URL prefix dropped | 9 | 0.36 mm | 10 cm |

The Camera app and Hatband's scanner read all four at 10 cm and none at 20. You hold the card out; it does not read across a table. The version-10 ceiling is never reached in practice, so dropping the URL prefix — the fallback the plan reserved — stays unused: it buys one version, no distance, and would cost the Camera app.

The codes carry the hat in a cleared square, 3.4 to 3.9 per cent of the symbol against the 15 per cent medium correction recovers. Every vector still decodes with it there, checked with zbar. Distance was measured before the hat existed and is not settled until it is measured again.

The Live Activity renders on the Lock Screen and under Always-On, the widget renders while locked, the Dynamic Island carries no card, and a universal link opens the app and its review sheet.

A 32 KB card is 52,452 characters as a URL, and both decoders read one back. Pasted as plain text it does not survive: the system's data detectors linkify `hatband.link` and drop the fragment. "Share as link" shares a `URL` rather than a string, which the receiving app keeps whole.

Google Safe Browsing listed hatband.link as a phishing site four days after the domain was registered, so Chrome and Safari both put an interstitial in front of every card link. Nothing on the page is what it was flagged for; a new domain that decodes a stranger's name, photo and telephone number out of an opaque blob in the URL and hands over a `data:` vCard is a shape a classifier knows, and it is not wrong about the shape. Reported for review; the page carries a description and no longer asks not to be indexed.

Not tested: iPhone 12 through 14, and scanning a Lock Screen end to end, which needs a second camera.

## Wire format (HB1)

A card is a CBOR map with small integer keys, encoded deterministically (RFC 8949 §4.2.1). It travels three ways:

- **QR**: `https://hatband.link/#1<base32>` — a format tag and unpadded Base32 of the map. The fragment never reaches the host; the page at hatband.link decodes it in the browser.
- **File**: `.hatband`, the map behind the magic bytes `HB1\0`.
- **Lock Screen**: the same URL form, restricted to the compact tier — name, up to two channels, persona id, key fingerprint — so it fits about QR version 10 at 23 mm.

Three forms sit behind those three ways. The Lock Screen tier is unsigned and carries a key fingerprint instead of a key. The in-app full QR is signed and drops the photo and the GPG certificate. The file form is signed and carries everything; its bytes travel as a `.hatband` file or in the URL fragment, which is why the table below marks the heavy fields "file and URL only".

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

Readers ignore unknown keys but carry them through unchanged, so a signature over a newer card still verifies. Keys 24 and up are reserved. Every form is signed over exactly its own content. A full card is about 256 bytes; the ceiling for any form is 32 KB. Vectors live in `spec/vectors`.

## Core

`Packages/HatbandCore` is the whole format and holds no UI. It builds on Linux, where its tests run first.

- **Codec.** Deterministic CBOR, decoded strictly: shortest forms, ordered keys, no tags or floats, text compared by bytes. Unpadded Base32. `Budget` reports the QR version a card needs — version 10 at medium correction is the Lock Screen ceiling, 25 the full-screen one, and a name-only card is version 5.
- **Crypto.** One 32-byte seed. Persona keys are HKDF-SHA256 of it, salt `hatband`, info `hatband/v1/persona/<index>`, derived on demand and never stored. Signing covers `hatband-card-v1` plus the canonical map; verification refuses small-order and non-canonical public keys. Exports are PBKDF2-HMAC-SHA256 at 600,000 rounds into ChaCha20-Poly1305, in a CBOR container whose header is authenticated. CryptoKit randomises Ed25519 signatures, so compare them by verifying, not by bytes.
- **QR.** An ISO 18004 encoder written for this project: segments, Reed–Solomon, every function pattern, masks scored by the reference N1–N4 rules. The URL prefix goes in a byte segment and the Base32 fragment in an alphanumeric one, at 5.5 bits per character.
- **Interop.** `Normalize` turns pasted input into stored forms and `CanonicalURI` renders them back as links. `SSHPublicKey` reads OpenSSH lines and writes `authorized_keys`, `allowed_signers` and randomart. `VCard` builds vCard 3.0. Everything parses Unicode scalars rather than grapheme clusters, so a combining mark or joiner can neither hide a delimiter nor ride into a stored value. Hostnames follow IDNA 2008's shape.
- **Validate.** Every scanned field passes `FieldValidator` under `Limits.qr` or `Limits.file` and comes back `ok`, `warning` or `reject`. Nothing is repaired. Rejected: controls, bidi controls, format and default-ignorable characters, values with no visible base, IP addresses in any spelling, `mailto` headers other than subject and body, and links outside https, http, mailto, tel, acct and OPENPGP4FPR. Hosts are judged label by label: a label whose every letter has an ASCII twin is a homograph and is refused naming the ASCII it imitates; a label keeping a letter no ASCII host has is an honest IDN and is only warned.
- **Vectors.** `spec/vectors/cards.json` holds ten cards with their CBOR, URL, file bytes, signing bytes, keys and signatures, generated from the seed `00…1f` by `scripts/gen-vectors.sh`. Run it on Linux only; CI regenerates it there and fails on drift.

## Security

- **Assets.** Your card; the people you scanned and where you met them; your signing seed.
- **Adversaries.** A bystander photographing your Lock Screen. A thief with your phone, locked or unlocked. A contact who turns hostile. A hostile card. Anyone who can read a backup.
- **Mitigations.** The Lock Screen shows a compact card, name only by default, that expires; mirrored views carry no card at all. Received cards live in a Class A store, sealed under a key the app lock guards, and stay out of backups unless you opt in. Every scanned payload is parsed strictly and screened for hidden characters, look-alike domains and disallowed links before you see it; nothing opens by itself. An update is accepted only when signed by the pinned key with a higher sequence number. Nothing leaves the phone unless you tap a button that names where it goes.
- **Non-goals.** A jailbroken or already compromised phone. Someone who photographs your card and keeps it: that is what a card is for.

Report a vulnerability privately at https://github.com/davidemerson/hatband/security/advisories/new. The site's `security.txt` points here.

## Privacy

Hatband collects nothing. There is no Hatband server, no account, and no analytics,
cookies, trackers or third-party SDKs; the app links no code it did not write except
Apple's own. Nothing about you reaches the developer, who has no way to learn that you
installed it.

Your card, your signing seed, the people you have scanned and where you met them stay on
your phone. Received cards live in a Class A store sealed under a key the app lock
guards, and stay out of your backups unless you turn that on. Nothing leaves the phone
unless you tap a button that names where it goes.

Four permissions, each asked for at the moment it is used and none of them required:

- **Camera**, to read a card's QR code. Frames are decoded and discarded.
- **Contacts**, write-only, when you add someone you scanned. Hatband writes the card in
  front of you and never reads your contacts.
- **Location**, reduced accuracy, when you save a scanned card and choose to note where
  you met. It stays on the phone.
- **Face ID**, to unlock the people you have scanned.

hatband.link carries the card after the `#`, which browsers never send to a server. The
page reads it with JavaScript in your browser and can fetch nothing: its
Content-Security-Policy forbids it. What the host sees is what any web server sees — an
address, a user agent, a time — never the card, never who is on it. Access logging is off.

Crash and performance reports from MetricKit stay on the phone; About lists them and you
choose whether to share one. The App Store's own download and crash reporting is Apple's,
not Hatband's, and is aggregate.

Questions: d@nnix.com.

## Site

hatband.link is one static page. It decodes the card from the URL fragment, which browsers never send, verifies the signature with WebCrypto and offers Add to contacts as a vCard. It loads nothing from anywhere: the script, the styles and the Jost typeface are all in the file, and the Content-Security-Policy admits the first two by hash and the rest only as `data:`. The host sees a request's address, user agent and time, never the card.

Hosting is a private S3 bucket behind CloudFront with logging off, described in `infra/site.yaml`.

```
node site/build.mjs                             # inlines site/src, writes the CSP hashes
infra/deploy-stack.sh                           # creates the stack
TEAMID=JKXH9239G4 sh scripts/deploy-site.sh     # uploads and invalidates
```

The build output is committed, and CI checks it is current.

## License

GPL-3.0-or-later for the app, with the App Store permission in `COPYING.iOS`. Components carry their own license as listed above. Contributions are accepted under the Developer Certificate of Origin: sign off your commits.
