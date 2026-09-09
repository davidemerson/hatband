#!/bin/sh
# Takes a build that release.yml has already uploaded and walks it through App
# Store Connect to a review submission: wait for processing, find or make the
# version, attach the build, set the release note, submit.
#
#   scripts/submit-release.sh --preflight VERSION    refuse if review is busy, then stop
#   scripts/submit-release.sh --dry-run VERSION BUILD  every read, no write
#   scripts/submit-release.sh VERSION BUILD
#
# Exit 2 means it refused because App Review already holds a submission for this
# app; that is the expected answer whenever a version is in flight, and it is
# what keeps a tag from disturbing a review already under way.
#
# Reads ASC_APP_ID, ASC_COPYRIGHT, ASC_WHATS_NEW, ASC_BUILD_TIMEOUT, ASC_POLL,
# and whatever scripts/asc.sh needs for the key.
set -eu
cd "$(dirname "$0")/.."

APP=${ASC_APP_ID:-6809843834}
POLL=${ASC_POLL:-30}
TIMEOUT=${ASC_BUILD_TIMEOUT:-2700}
DRY=no
PREFLIGHT=no

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY=yes; shift ;;
        --preflight) PREFLIGHT=yes; shift ;;
        --) shift; break ;;
        -*) echo "usage: submit-release.sh [--preflight] [--dry-run] VERSION [BUILD]" >&2; exit 1 ;;
        *) break ;;
    esac
done

VERSION=${1:?usage: submit-release.sh [--preflight] [--dry-run] VERSION [BUILD]}
BUILD=${2:-}

asc() { scripts/asc.sh "$@"; }

# Every write goes through here, so --dry-run is total rather than best effort.
# It answers with an id-shaped stub, which keeps the rest of the chain walking.
mutate() {
    if [ "$DRY" = yes ]; then
        printf 'would %s %s\n' "$1" "$2" >&2
        if [ -n "${3:-}" ]; then printf '  %s\n' "$3" >&2; fi
        printf '{"data":{"id":"DRY-RUN"}}\n'
        return 0
    fi
    asc "$@"
}

# --- 0. Refuse if App Review already holds something -------------------------
# Gate on the submission's state, never the item's: right now this app has a
# submission WAITING_FOR_REVIEW whose only item still reads READY_FOR_REVIEW.
busy='"WAITING_FOR_REVIEW","IN_REVIEW","UNRESOLVED_ISSUES","CANCELING","COMPLETING"'
subs=$(asc GET "/v1/reviewSubmissions?filter[app]=$APP&limit=200&fields[reviewSubmissions]=state,platform,submittedDate")
inflight=$(printf '%s' "$subs" | jq -r --argjson busy "[$busy]" \
    '.data[] | select(.attributes.state as $s | $busy | index($s))
     | "\(.id)  \(.attributes.state)  submitted \(.attributes.submittedDate // "never")"')
if [ -n "$inflight" ]; then
    echo "refusing: App Review already holds a submission for app $APP" >&2
    printf '  %s\n' "$inflight" >&2
    exit 2
fi
if [ "$PREFLIGHT" = yes ]; then
    echo "preflight: nothing in flight for app $APP"
    exit 0
fi

: "${BUILD:?a build number is required unless --preflight}"

# A never-sent draft from an aborted run is reusable rather than an obstacle.
draft=$(printf '%s' "$subs" | jq -r \
    '[.data[] | select(.attributes.state == "READY_FOR_REVIEW" and .attributes.submittedDate == null)][0].id // empty')

# --- 1. Wait for the build to finish processing ------------------------------
echo "waiting for build $VERSION ($BUILD) to process"
waited=0
buildid=
while :; do
    r=$(asc GET "/v1/builds?filter[app]=$APP&filter[version]=$BUILD&filter[preReleaseVersion.version]=$VERSION&fields[builds]=version,processingState")
    state=$(printf '%s' "$r" | jq -r '.data[0].attributes.processingState // empty')
    case "$state" in
        VALID) buildid=$(printf '%s' "$r" | jq -r '.data[0].id'); break ;;
        FAILED|INVALID) echo "build $BUILD is $state" >&2; exit 1 ;;
    esac
    if [ "$waited" -ge "$TIMEOUT" ]; then
        echo "build $BUILD is still ${state:-absent} after ${waited}s" >&2; exit 1
    fi
    if [ $((waited % (POLL * 5))) -eq 0 ]; then
        echo "  ${state:-not uploaded yet}, ${waited}s"
    fi
    sleep "$POLL"; waited=$((waited + POLL))
done
echo "build $BUILD is VALID: $buildid"

# --- 2. Find or create the App Store version ---------------------------------
versions=$(asc GET "/v1/apps/$APP/appStoreVersions?limit=200&fields[appStoreVersions]=versionString,appVersionState,releaseType,copyright")
total=$(printf '%s' "$versions" | jq -r '.data | length')
vid=$(printf '%s' "$versions" | jq -r --arg v "$VERSION" \
    '.data[] | select(.attributes.versionString == $v) | .id' | head -1)

if [ -n "$vid" ]; then
    existed=yes
    vstate=$(printf '%s' "$versions" | jq -r --arg i "$vid" '.data[] | select(.id == $i) | .attributes.appVersionState')
    case "$vstate" in
        PREPARE_FOR_SUBMISSION|DEVELOPER_REJECTED|REJECTED|METADATA_REJECTED|INVALID_BINARY) ;;
        *) echo "refusing: version $VERSION is $vstate, which is not editable" >&2; exit 2 ;;
    esac
    echo "version $VERSION exists ($vstate): $vid"
else
    existed=no
    copyright=${ASC_COPYRIGHT:-$(printf '%s' "$versions" | jq -r '[.data[].attributes.copyright | select(. != null)][0] // empty')}
    body=$(jq -nc --arg v "$VERSION" --arg app "$APP" --arg c "$copyright" \
        '{data:{type:"appStoreVersions",
                attributes:({platform:"IOS",versionString:$v,releaseType:"MANUAL"}
                            + (if $c == "" then {} else {copyright:$c} end)),
                relationships:{app:{data:{type:"apps",id:$app}}}}}')
    vid=$(mutate POST /v1/appStoreVersions "$body" | jq -r '.data.id')
    echo "created version $VERSION: $vid"
fi

# --- 3. Decide the release note before anything is written -------------------
# whatsNew rejects the whole PATCH on an app's first version, so it is skipped
# there and isolated in its own request everywhere else. $total counted the
# app's versions before this run may have added one, so the target is the app's
# first if it was the only one there was, or if there were none.
if [ "$total" -eq 0 ] || { [ "$total" -eq 1 ] && [ "$existed" = yes ]; }; then
    first=yes
else
    first=no
fi

notes=${ASC_WHATS_NEW:-$(git tag -l --format='%(contents:body)' "v$VERSION" 2>/dev/null || true)}
notes=$(printf '%s\n' "$notes" | awk 'NF{last=NR} {line[NR]=$0} END{for(i=1;i<=last;i++) print line[i]}')

if [ "$first" = yes ]; then
    echo "first version of this app: skipping whatsNew, which would reject the PATCH"
elif [ -z "$notes" ]; then
    echo "no release note: tag v$VERSION has no message body, and whatsNew is required after the first version" >&2
    echo "  cut the tag with: git tag -s v$VERSION -F notes.txt" >&2
    exit 1
fi

# --- 4. Attach the build, hold the release, set the note ---------------------
# Three requests rather than one, so a failure names which of them failed.
mutate PATCH "/v1/appStoreVersions/$vid/relationships/build" \
    "$(jq -nc --arg b "$buildid" '{data:{type:"builds",id:$b}}')" >/dev/null
echo "attached build $BUILD"

# MANUAL, not AFTER_APPROVAL: with a public app, an approval at three in the
# morning should not ship itself.
mutate PATCH "/v1/appStoreVersions/$vid" \
    "$(jq -nc --arg i "$vid" '{data:{type:"appStoreVersions",id:$i,attributes:{releaseType:"MANUAL"}}}')" >/dev/null
echo "release is manual"

if [ "$first" = no ]; then
    locs=$(asc GET "/v1/appStoreVersions/$vid/appStoreVersionLocalizations?fields[appStoreVersionLocalizations]=locale,whatsNew")
    lid=$(printf '%s' "$locs" | jq -r '.data[] | select(.attributes.locale == "en-US") | .id' | head -1)
    if [ -n "$lid" ]; then
        b=$(jq -nc --arg i "$lid" --arg t "$notes" \
            '{data:{type:"appStoreVersionLocalizations",id:$i,attributes:{whatsNew:$t}}}')
        mutate PATCH "/v1/appStoreVersionLocalizations/$lid" "$b" >/dev/null \
            || echo "warning: whatsNew was refused; the version is otherwise ready" >&2
    else
        b=$(jq -nc --arg v "$vid" --arg t "$notes" \
            '{data:{type:"appStoreVersionLocalizations",
                    attributes:{locale:"en-US",whatsNew:$t},
                    relationships:{appStoreVersion:{data:{type:"appStoreVersions",id:$v}}}}}')
        mutate POST /v1/appStoreVersionLocalizations "$b" >/dev/null \
            || echo "warning: whatsNew was refused; the version is otherwise ready" >&2
    fi
    echo "release note set from the tag"
fi

# --- 5. Submit ---------------------------------------------------------------
# appStoreVersionSubmissions is deprecated in favour of reviewSubmissions.
if [ -n "$draft" ]; then
    sid=$draft
    echo "reusing draft submission $sid"
else
    sid=$(mutate POST /v1/reviewSubmissions \
        "$(jq -nc --arg app "$APP" '{data:{type:"reviewSubmissions",attributes:{platform:"IOS"},relationships:{app:{data:{type:"apps",id:$app}}}}}')" \
        | jq -r '.data.id')
    echo "opened submission $sid"
fi

# From here a failure would strand a half-built submission, which would block
# the next run's preflight. Cancel it on the way out unless we get to submitted.
submitted=no
cancel_draft() {
    if [ "$submitted" = no ] && [ "$DRY" = no ] && [ -n "${sid:-}" ] && [ "$sid" != DRY-RUN ]; then
        echo "cancelling submission $sid" >&2
        scripts/asc.sh -i PATCH "/v1/reviewSubmissions/$sid" \
            "$(jq -nc --arg i "$sid" '{data:{type:"reviewSubmissions",id:$i,attributes:{canceled:true}}}')" >/dev/null 2>&1 || true
    fi
}
trap cancel_draft EXIT INT TERM HUP

mutate POST /v1/reviewSubmissionItems \
    "$(jq -nc --arg s "$sid" --arg v "$vid" \
       '{data:{type:"reviewSubmissionItems",relationships:{reviewSubmission:{data:{type:"reviewSubmissions",id:$s}},appStoreVersion:{data:{type:"appStoreVersions",id:$v}}}}}')" >/dev/null
echo "added version $VERSION to the submission"

mutate PATCH "/v1/reviewSubmissions/$sid" \
    "$(jq -nc --arg i "$sid" '{data:{type:"reviewSubmissions",id:$i,attributes:{submitted:true}}}')" >/dev/null
submitted=yes

if [ "$DRY" = yes ]; then
    echo "dry run: nothing was sent"
    exit 0
fi

state=$(asc GET "/v1/reviewSubmissions/$sid?fields[reviewSubmissions]=state,submittedDate" \
        | jq -r '"\(.data.attributes.state) \(.data.attributes.submittedDate // "")"')
echo "submitted $VERSION ($BUILD) for review: $state"
