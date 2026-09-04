#!/bin/sh
# Creates or updates the hatband-site stack. Run once from a machine with the
# scoped profile; ACM validation records are written to the zone automatically.
set -eu
cd "$(dirname "$0")"
STACK="${STACK:-hatband-site}"
zone=$(aws route53 list-hosted-zones-by-name --dns-name hatband.link --query "HostedZones[?Name=='hatband.link.'].Id | [0]" --output text | sed 's#/hostedzone/##')
aws cloudformation deploy --stack-name "$STACK" --template-file site.yaml \
  --parameter-overrides DomainName=hatband.link HostedZoneId="$zone" \
  --no-fail-on-empty-changeset
aws cloudformation describe-stacks --stack-name "$STACK" --query 'Stacks[0].Outputs' --output table
