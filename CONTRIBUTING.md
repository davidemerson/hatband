# Contributing

## Sign off your commits

Contributions are accepted under the [Developer Certificate of
Origin](https://developercertificate.org/). It is a statement that you wrote the
patch or otherwise have the right to submit it under the licence. Say so by
signing off:

    git commit -s

which appends `Signed-off-by: Your Name <you@example.com>` to the message. Use
your real name.

## Before you open a pull request

    xcodegen generate                                  # Hatband.xcodeproj; never commit it
    xcodebuild test -project Hatband.xcodeproj -scheme Hatband \
      -destination "$(sh scripts/ios-destination.sh)"
    swift test --package-path Packages/HatbandCore
    node site/build.mjs && git diff --exit-code -- site/
    node --test site/test/*.test.mjs
    sh scripts/lint-boundaries.sh --no-stubs

Tests ship in the same commit as the code they cover.

## What the shape of the project asks of a patch

- **No third-party code in the app.** CI fails on any package but `swift-crypto`
  and `swift-asn1`, both Apple's, and the first is linked on Linux only.
- **One file per capability.** Networking, storage, pasteboard, screen and
  location each live behind a single file, and `UserDefaults` is forbidden
  outright. `scripts/boundaries.txt` is the list; `scripts/lint-boundaries.sh`
  enforces it. That discipline is why `PrivacyInfo.xcprivacy` can declare
  nothing.
- **`site/*.html` is generated.** Edit `site/src/`, then run `node site/build.mjs`.
  CI checks the committed output is current.
- **`Packages/HatbandCore` is the wire format**, shared with the site. Change it
  only through `spec/` and regenerate the vectors — on Linux, where Ed25519
  signing is deterministic. Do not run `scripts/gen-vectors.sh` on a Mac.
- **Documentation lives in `README.md`** and nowhere else.

## Licences

The app and the site are GPL-3.0-or-later, with the App Store permission in
`COPYING.iOS`. `Packages/HatbandCore` is Apache-2.0 and `spec/` is CC-BY-4.0.
A patch is offered under the licence of the file it touches.
