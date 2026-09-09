#!/bin/sh
# Uploads site/ to the bucket with explicit content types and invalidates
# CloudFront. Needs: AWS_PROFILE (or ambient credentials), the stack name
# (default hatband-site) and TEAMID for the associated-domains file.
set -eu
cd "$(dirname "$0")/.."
STACK="${STACK:-hatband-site}"
: "${TEAMID:?set TEAMID to the Apple developer team id}"
bucket=$(aws cloudformation describe-stacks --stack-name "$STACK" --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" --output text)
dist=$(aws cloudformation describe-stacks --stack-name "$STACK" --query "Stacks[0].Outputs[?OutputKey=='DistributionId'].OutputValue" --output text)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.well-known"
cp site/*.html "$tmp/"
sed "s/TEAMID/$TEAMID/g" site/.well-known/apple-app-site-association > "$tmp/.well-known/apple-app-site-association"
cp site/.well-known/security.txt "$tmp/.well-known/security.txt"
cp site/robots.txt "$tmp/robots.txt"
keys=""
put() {
  aws s3 cp "$tmp/$1" "s3://$bucket/$1" --content-type "$2" --cache-control "${3:-public, max-age=300}" --only-show-errors
  keys="$keys$1
"
}
for f in "$tmp"/*.html; do
  name=$(basename "$f")
  put "$name" "text/html; charset=utf-8"
  [ "$name" = index.html ] || { cp "$f" "$tmp/${name%.html}"; put "${name%.html}" "text/html; charset=utf-8"; }
done
put .well-known/apple-app-site-association "application/json" "public, max-age=3600"
put .well-known/security.txt "text/plain; charset=utf-8" "public, max-age=3600"
put robots.txt "text/plain; charset=utf-8" "public, max-age=3600"

# `cp` only ever adds, so a page removed from site/ would go on being served.
# Anything in the bucket that this run did not just upload is gone from the
# site, and is deleted.
aws s3api list-objects-v2 --bucket "$bucket" --query 'Contents[].Key' --output text \
  | tr '\t' '\n' | while read -r key; do
  [ -n "$key" ] && [ "$key" != None ] || continue
  if printf '%s' "$keys" | grep -qxF "$key"; then
    continue
  fi
  echo "pruning $key"
  aws s3 rm "s3://$bucket/$key" --only-show-errors
done

aws cloudfront create-invalidation --distribution-id "$dist" --paths "/*" --query 'Invalidation.Id' --output text
echo "deployed to $bucket via $dist"
