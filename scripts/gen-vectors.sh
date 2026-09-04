#!/bin/sh
# Regenerates spec/vectors/cards.json. Run on Linux: Ed25519 signatures are
# deterministic there, so the file only changes when the format does.
set -e
cd "$(dirname "$0")/.."
swift run --package-path Packages/HatbandCore -c release hatband-vectors > spec/vectors/cards.json
echo "wrote spec/vectors/cards.json ($(wc -c < spec/vectors/cards.json) bytes)"
