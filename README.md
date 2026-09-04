# Hatband

A business card in your hat. Hatband shows your contact details as a QR code, from the iPhone Lock Screen if you like, and remembers where you met the people you scan. No account, no server, nothing collected.

Named for the card Bloom keeps in his hatband in *Ulysses*, bearing the name of his other self, Henry Flower.

## Status

Under construction. Nothing runs on a phone yet.

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

## License

GPL-3.0-or-later for the app, with the App Store permission in `COPYING.iOS`. Components carry their own license as listed above. Contributions are accepted under the Developer Certificate of Origin: sign off your commits.
