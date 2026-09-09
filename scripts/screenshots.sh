#!/bin/sh
# App Store screenshots, driven on a 6.9" simulator through the app's own UI.
# Slow, and nothing to do with correctness: its own scheme keeps it out of CI.
#
#     sh scripts/screenshots.sh          # build/screenshots/*.png at 1320x2868
#
# The people it shows get there the way anyone's would — a card arrives by URL
# and the review sheet is saved — so the app needs no seeding seam. That is
# why this runs the test bundle several times with `simctl openurl` between.
set -eu
cd "$(dirname "$0")/.."
DEVICE="${DEVICE:-iPhone 17 Pro Max}"
OUT="${OUT:-$PWD/build/screenshots}"
CARDS="${CARDS:-spec/screenshots/cards.txt}"

id=$(xcrun simctl list devices available -j | python3 -c "
import json,sys
for _, devices in sorted(json.load(sys.stdin)['devices'].items(), reverse=True):
    for device in devices:
        if device['name'] == '$DEVICE':
            print(device['udid']); raise SystemExit
raise SystemExit('no \"$DEVICE\" simulator')
")
echo "device: $DEVICE ($id)"

# A screenshot of a half-migrated app is worth nothing; start from nothing.
xcrun simctl shutdown "$id" 2>/dev/null || true
xcrun simctl erase "$id"
xcrun simctl boot "$id"
xcrun simctl bootstatus "$id" -b >/dev/null
# Apple's own screenshots show a full status bar at 9:41.
xcrun simctl status_bar "$id" override --time "9:41" \
  --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
# Eccles Street, so "where you met" has somewhere to be.
xcrun simctl location "$id" set 53.3598,-6.2683
rm -rf "$OUT"; mkdir -p "$OUT"

export TEST_RUNNER_HATBAND_SHOTS="$OUT"
run() {
  xcodebuild test -project Hatband.xcodeproj -scheme HatbandScreenshots \
    -destination "platform=iOS Simulator,id=$id" -only-testing "HatbandScreenshots/ScreenshotTests/$1" \
    2>&1 | grep -E --line-buffered 'error:|✘|\*\* TEST' | cut -c1-200 || true
}

echo "onboarding"
run testAOnboards
# After the first run, because the app has to exist before it can be granted
# anything: the review sheet cannot answer a permission prompt on its own.
xcrun simctl privacy "$id" grant location link.hatband.ios

# Each line of the cards file is a card URL and the place it was collected.
while IFS='|' read -r url place; do
  [ -n "${url:-}" ] || continue
  case "$url" in \#*) continue ;; esac
  echo "card: $place"
  xcrun simctl openurl "$id" "$url"
  sleep 5
  TEST_RUNNER_HATBAND_PLACE="$place" run testBSavesThePendingReview
done < "$CARDS"

echo "photographs"
run testCTakesTheScreenshots
echo
ls -l "$OUT"
