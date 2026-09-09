#!/bin/sh
# App Store Connect API client. Mints the ES256 JWT with openssl and wraps curl,
# because there is no pyjwt and no python cryptography on the Mac this is driven
# from and the house rule is to add neither.
#
#   scripts/asc.sh token                       print a JWT and exit
#   scripts/asc.sh GET /v1/apps/6809843834     any method and path under the host
#   scripts/asc.sh POST /v1/reviewSubmissions "$body"
#   scripts/asc.sh -i PATCH /v1/x "$body"      status on line 1, never exits non-zero
#   scripts/asc.sh --self-test                 sign, verify the shape, call the API
#
# Reads ASC_KEY_ID and ASC_ISSUER_ID from the environment, and the key from
# ASC_KEY_PATH, or ~/private_keys/AuthKey_$ASC_KEY_ID.p8, or base64 in ASC_KEY_P8
# -- that order so the release workflow's existing key step needs no change.
#
# POSIX sh. /usr/bin/openssl is LibreSSL on macOS and OpenSSL on the Linux
# runner; both sign this correctly.
set -eu

API=https://api.appstoreconnect.apple.com
OPENSSL=${OPENSSL:-/usr/bin/openssl}

TMPKEY=
trap 'if [ -n "$TMPKEY" ]; then rm -f "$TMPKEY"; fi' EXIT INT TERM HUP

b64url() { "$OPENSSL" base64 -A | tr '+/' '-_' | tr -d '='; }

# Hex to bytes. xxd is on macOS and on GitHub's images; perl is the fallback
# for anywhere it is not.
unhex() {
    if command -v xxd >/dev/null 2>&1; then xxd -r -p
    else perl -ne 'chomp; print pack "H*", $_'
    fi
}

# openssl emits ECDSA as DER SEQUENCE{INTEGER r, INTEGER s}; JWS wants raw
# r||s, 32 bytes each. asn1parse prints the integer's value, so DER's 0x00 sign
# pad is already gone -- but it also prints a short integer short, about one
# signature in 128, and that is the case that breaks a naive reader. Strip a
# pad if one ever survives, then left-pad to 64.
hex32() {
    v=$(printf %s "$1" | tr -d '[:space:]' | tr 'A-F' 'a-f')
    while [ "${#v}" -gt 64 ]; do
        case "$v" in
            00*) v=${v#00} ;;
            *) echo "asc: signature integer longer than 32 bytes" >&2; exit 1 ;;
        esac
    done
    while [ "${#v}" -lt 64 ]; do v=0$v; done
    printf %s "$v"
}

resolve_key() {
    : "${ASC_KEY_ID:?set ASC_KEY_ID}"
    if [ -n "${ASC_KEY_PATH:-}" ]; then
        KEYFILE=$ASC_KEY_PATH
    elif [ -r "$HOME/private_keys/AuthKey_$ASC_KEY_ID.p8" ]; then
        KEYFILE=$HOME/private_keys/AuthKey_$ASC_KEY_ID.p8
    elif [ -n "${ASC_KEY_P8:-}" ]; then
        umask 077
        TMPKEY=$(mktemp "${TMPDIR:-/tmp}/asc.XXXXXX")
        printf %s "$ASC_KEY_P8" | base64 --decode > "$TMPKEY"
        KEYFILE=$TMPKEY
    else
        echo "asc: no key: set ASC_KEY_PATH or ASC_KEY_P8" >&2; exit 1
    fi
    [ -r "$KEYFILE" ] || { echo "asc: cannot read $KEYFILE" >&2; exit 1; }
}

# No caching: a build poll can outlive any token Apple will accept, and minting
# is two openssl calls. Staleness is not worth the cleverness.
mint() {
    : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
    resolve_key
    now=$(date +%s)
    si="$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$ASC_KEY_ID" | b64url)"
    si="$si.$(printf '{"iss":"%s","iat":%s,"exp":%s,"aud":"appstoreconnect-v1"}' \
              "$ASC_ISSUER_ID" "$now" "$((now + 900))" | b64url)"
    rs=$(printf %s "$si" | "$OPENSSL" dgst -sha256 -sign "$KEYFILE" \
         | "$OPENSSL" asn1parse -inform DER | awk -F: '/INTEGER/{print $4}')
    [ "$(printf '%s\n' "$rs" | grep -c .)" -eq 2 ] || {
        echo "asc: expected two signature integers, got:" >&2
        printf '%s\n' "$rs" >&2; exit 1; }
    r=$(hex32 "$(printf '%s\n' "$rs" | sed -n 1p)")
    s=$(hex32 "$(printf '%s\n' "$rs" | sed -n 2p)")
    printf '%s.%s\n' "$si" "$(printf '%s%s' "$r" "$s" | unhex | b64url)"
}

self_test() {
    t=$(mint)
    n=$(printf %s "$t" | awk -F. '{print NF}')
    [ "$n" -eq 3 ] || { echo "asc: token has $n parts, want 3" >&2; exit 1; }
    # 64 bytes base64url with the padding stripped is 86 characters, always.
    sig=${t##*.}
    [ "${#sig}" -eq 86 ] || { echo "asc: signature is ${#sig} chars, want 86" >&2; exit 1; }
    id=$(ASC_TOKEN=$t "$0" GET "/v1/apps/${ASC_APP_ID:-6809843834}" | jq -r '.data.id')
    [ -n "$id" ] && [ "$id" != null ] || { echo "asc: the API did not return the app" >&2; exit 1; }
    echo "asc: ok, signed and read app $id"
}

if [ "${1:-}" = token ]; then mint; exit 0; fi
if [ "${1:-}" = --self-test ]; then self_test; exit 0; fi

inspect=no
if [ "${1:-}" = -i ]; then inspect=yes; shift; fi
method=${1:?usage: asc.sh [-i] METHOD PATH [BODY]}
path=${2:?usage: asc.sh [-i] METHOD PATH [BODY]}
body=${3:-}

token=${ASC_TOKEN:-$(mint)}

attempt=0
while :; do
    # -g, or curl reads the brackets of filter[app] as a glob range and dies.
    set -- -sS -g -X "$method" -H "Authorization: Bearer $token" \
           -H 'Accept: application/json' -w '\n%{http_code}'
    if [ -n "$body" ]; then
        set -- "$@" -H 'Content-Type: application/json' --data-binary "$body"
    fi
    out=$(curl "$@" "$API$path") || out=""
    code=$(printf '%s' "$out" | tail -n1)
    resp=$(printf '%s' "$out" | sed '$d')
    attempt=$((attempt + 1))
    case "$code" in
        429|5??|"") [ "$attempt" -lt 4 ] || break; sleep $((attempt * 20)) ;;
        *) break ;;
    esac
done

if [ "$inspect" = yes ]; then printf '%s\n%s\n' "$code" "$resp"; exit 0; fi
case "$code" in
    2??) printf '%s\n' "$resp"; exit 0 ;;
esac
echo "asc: $method $path -> HTTP $code" >&2
printf '%s\n' "$resp" \
  | jq -r '.errors[]? | "  \(.code // .status): \(.title)\n    \(.detail // "")"' >&2 \
  || printf '%s\n' "$resp" >&2
exit 1
