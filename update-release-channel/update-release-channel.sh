#!/bin/bash
# Update a release channel pointer at
# s3://downloads-cdn-eu-central-1-prod/<prefix>/<product>/<channel>.json
# (served at https://binaries.sonarsource.com/<prefix>/<product>/<channel>.json).
#
# Required environment variables:
#   VERSION - Version the channel should point at (e.g. "0.9.0.977")
#   CHANNEL - Channel name (latest|stable|beta|rc)
#   PREFIX  - S3 key prefix (default in action.yml: "Distribution")
#   PRODUCT - Product folder on S3 (default in action.yml: GitHub repo name)
#   DRY_RUN - "true" to skip the AWS call and just print the planned PutObject
#
# Non-dry-run additionally requires AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
# AWS_SESSION_TOKEN (provided by the Vault step in action.yml).

set -euo pipefail

: "${VERSION:?}" "${CHANNEL:?}" "${PREFIX:?}" "${PRODUCT:?}"
: "${DRY_RUN:=false}"

readonly BUCKET="downloads-cdn-eu-central-1-prod"
readonly PUBLIC_BASE_URL="https://binaries.sonarsource.com"

[[ "$CHANNEL" =~ ^(latest|stable|beta|rc|dogfood)$ ]] \
  || { echo "::error::Invalid channel '$CHANNEL'. Must be one of: latest, stable, beta, rc, dogfood." >&2; exit 1; }
[[ "$PRODUCT" =~ ^[a-z0-9][a-z0-9._-]*$ ]] \
  || { echo "::error::Invalid product '$PRODUCT'. Must match ^[a-z0-9][a-z0-9._-]*\$." >&2; exit 1; }
[[ "$PREFIX" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
  || { echo "::error::Invalid prefix '$PREFIX'. Must match ^[A-Za-z0-9][A-Za-z0-9._-]*\$." >&2; exit 1; }
[[ "$PREFIX" == "Distribution" ]] \
  || echo "::warning::Custom prefix '$PREFIX' (default is 'Distribution')." >&2

KEY="$PREFIX/$PRODUCT/$CHANNEL.json"
URL="$PUBLIC_BASE_URL/$KEY"
UPDATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
BODY="$(jq -cn --arg v "$VERSION" --arg t "$UPDATED_AT" '{schemaVersion:1, version:$v, updatedAt:$t}')"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "Dry-run: aws s3api put-object --bucket $BUCKET --key $KEY --cache-control max-age=60 --content-type application/json --body <generated-json-file>"
  echo "Dry-run body: $BODY"
else
  BODY_FILE="$(mktemp)"
  trap 'rm -f "$BODY_FILE"' EXIT
  printf '%s' "$BODY" > "$BODY_FILE"

  aws s3api put-object \
    --bucket "$BUCKET" --key "$KEY" --body "$BODY_FILE" \
    --cache-control "max-age=60" --content-type "application/json" > /dev/null
  echo "Wrote $URL"
fi

{
  echo "bucket=$BUCKET"
  echo "key=$KEY"
  echo "url=$URL"
  echo "body=$BODY"
} >> "${GITHUB_OUTPUT:?}"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  echo "**update-release-channel** → [\`$KEY\`]($URL) (version \`$VERSION\`, dry-run \`$DRY_RUN\`)" >> "$GITHUB_STEP_SUMMARY"
fi
