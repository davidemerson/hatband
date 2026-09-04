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
put() { aws s3 cp "$tmp/$1" "s3://$bucket/$1" --content-type "$2" --cache-control "${3:-public, max-age=300}" --only-show-errors; }
for f in "$tmp"/*.html; do put "$(basename "$f")" "text/html; charset=utf-8"; done
put .well-known/apple-app-site-association "application/json" "public, max-age=3600"
put .well-known/security.txt "text/plain; charset=utf-8" "public, max-age=3600"
aws cloudfront create-invalidation --distribution-id "$dist" --paths "/*" --query 'Invalidation.Id' --output text
echo "deployed to $bucket via $dist"
