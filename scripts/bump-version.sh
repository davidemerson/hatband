#!/bin/sh
# Moves MARKETING_VERSION and the assertion that pins it, which must never
# disagree: project.yml sets what the bundle carries, BundleInfoTests refuses a
# bundle that carries anything else, and every release so far has moved the two
# by hand in one commit.
#
#   scripts/bump-version.sh 1.0.1     rewrite both, print the diff
#   scripts/bump-version.sh --test    also run the iOS tests, which takes minutes
#   scripts/bump-version.sh --self-test  prove the rewrite on copies
#
# It deliberately does not tag. A tag is a release, and release notes are the
# part a person has to write.
set -eu
cd "$(dirname "$0")/.."

spec=project.yml
test_file=HatbandTests/BundleInfoTests.swift

usage() { echo "usage: bump-version.sh [--test] VERSION | --self-test" >&2; exit 1; }

# Rewrites $1 (a project.yml) and $2 (a BundleInfoTests.swift) to version $3.
# Via a temp file, because sed -i is spelled differently on the two platforms.
rewrite() {
    y=$1; s=$2; v=$3
    sed "s/^\\( *MARKETING_VERSION: *\\).*/\\1$v/" "$y" > "$y.new" && mv "$y.new" "$y"
    sed "/CFBundleShortVersionString/ s/\"[0-9][0-9.]*\"/\"$v\"/" "$s" > "$s.new" && mv "$s.new" "$s"
}

# What each file says the version is. Also the drift check.
version_of() { sed -n 's/^ *MARKETING_VERSION: *//p' "$1" | head -1 | tr -d "\"' "; }
pinned_in() { sed -n '/CFBundleShortVersionString/ s/.*"\([0-9][0-9.]*\)".*/\1/p' "$1" | head -1; }

self_test() {
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    cp "$spec" "$tmp/project.yml"
    cp "$test_file" "$tmp/BundleInfoTests.swift"
    rewrite "$tmp/project.yml" "$tmp/BundleInfoTests.swift" 9.9.9
    got=$(version_of "$tmp/project.yml")
    [ "$got" = 9.9.9 ] || { echo "self-test: project.yml says $got"; exit 1; }
    got=$(pinned_in "$tmp/BundleInfoTests.swift")
    [ "$got" = 9.9.9 ] || { echo "self-test: the test pins $got"; exit 1; }
    # Exactly one line of each file may differ, or the patterns are too greedy.
    n=$(diff "$spec" "$tmp/project.yml" | grep -c '^[<>]' || true)
    [ "$n" -eq 2 ] || { echo "self-test: project.yml changed $n lines, want 2"; exit 1; }
    n=$(diff "$test_file" "$tmp/BundleInfoTests.swift" | grep -c '^[<>]' || true)
    [ "$n" -eq 2 ] || { echo "self-test: the test file changed $n lines, want 2"; exit 1; }
    echo "bump-version: ok"
}

run_tests=no
case "${1:-}" in
    --self-test) self_test; exit 0 ;;
    --test) run_tests=yes; shift ;;
    -*) usage ;;
    "") usage ;;
esac

new=${1:-}
[ -n "$new" ] || usage
printf '%s' "$new" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$' || {
    echo "not a version Apple will take: $new" >&2; exit 1; }

old=$(version_of "$spec")
[ "$old" != "$new" ] || { echo "already $new" >&2; exit 1; }
was=$(pinned_in "$test_file")
[ "$was" = "$old" ] || echo "note: the test pinned $was while project.yml said $old" >&2

rewrite "$spec" "$test_file" "$new"

# Prove they agree now, which is the whole point of the script.
a=$(version_of "$spec"); b=$(pinned_in "$test_file")
[ "$a" = "$new" ] && [ "$b" = "$new" ] || {
    echo "rewrite failed: project.yml $a, test $b" >&2; exit 1; }

git --no-pager diff -- "$spec" "$test_file"
echo
echo "$old -> $new"

if [ "$run_tests" = yes ]; then
    xcodegen generate --spec project.yml
    xcodebuild test -project Hatband.xcodeproj -scheme Hatband \
        -destination "$(scripts/ios-destination.sh)"
else
    echo "run the tests before committing:"
    echo "  xcodegen generate && xcodebuild test -project Hatband.xcodeproj -scheme Hatband \\"
    echo "    -destination \"\$(scripts/ios-destination.sh)\""
fi
