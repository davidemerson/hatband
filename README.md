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

## License

GPL-3.0-or-later for the app, with the App Store permission in `COPYING.iOS`. Components carry their own license as listed above. Contributions are accepted under the Developer Certificate of Origin: sign off your commits.
