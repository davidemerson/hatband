#!/bin/sh
# Boundaries lint. Each row of scripts/boundaries.txt is `regex<TAB>allowed`,
# allowed being space-separated path prefixes or `-`. Every hit of the regex
# in Hatband, HatbandWidgets or Shared outside an allowed prefix is printed,
# and the exit status is 1 if there were any.
#
#   scripts/lint-boundaries.sh             lint the tree
#   scripts/lint-boundaries.sh --self-test plant a violation, expect it caught, then lint
#   scripts/lint-boundaries.sh --no-stubs  also refuse any remaining `// STUB:` marker
#
# POSIX sh and grep -E only, so it runs on the Linux and macOS runners alike.
set -u

cd "$(dirname "$0")/.." || exit 2
rules=scripts/boundaries.txt
dirs="Hatband HatbandWidgets Shared"
tab=$(printf '\t')

# Prints every hit of $1 not under a prefix in $2.
violations() {
    regex=$1
    allowed=$2
    grep -rnE --include='*.swift' -e "$regex" $dirs 2>/dev/null | while IFS= read -r hit; do
        file=${hit%%:*}
        ok=0
        if [ "$allowed" != "-" ]; then
            for prefix in $allowed; do
                case "$file" in
                    "$prefix"*) ok=1 ;;
                esac
            done
        fi
        [ "$ok" -eq 1 ] || printf '%s\n' "$hit"
    done
}

lint() {
    while IFS="$tab" read -r regex allowed; do
        case "$regex" in
            '' | '#'*) continue ;;
        esac
        [ -n "$allowed" ] || allowed=-
        violations "$regex" "$allowed"
    done < "$rules"
    if [ "${1:-}" = "--no-stubs" ]; then
        violations '// STUB:' -
    fi
}

report() {
    if [ -n "$1" ]; then
        printf '%s\n' "$1"
        printf 'boundaries: %s\n' "$(printf '%s\n' "$1" | wc -l | tr -d ' ') hit(s) outside their allowed files"
        return 1
    fi
    printf 'boundaries: clean\n'
    return 0
}

case "${1:-}" in
    --self-test)
        planted=Hatband/Views/Zz.swift
        trap 'rm -f "$planted"' EXIT INT TERM
        printf 'import Foundation\nlet session = URLSession.shared\n' > "$planted"
        output=$(lint)
        if printf '%s\n' "$output" | grep -q "^$planted:"; then
            printf 'self-test: planted %s was caught\n' "$planted"
        else
            printf 'self-test: planted %s was NOT caught\n' "$planted"
            exit 1
        fi
        rm -f "$planted"
        trap - EXIT INT TERM
        report "$(lint)"
        ;;
    --no-stubs)
        report "$(lint --no-stubs)"
        ;;
    '')
        report "$(lint)"
        ;;
    *)
        printf 'usage: %s [--self-test | --no-stubs]\n' "$0" >&2
        exit 2
        ;;
esac
