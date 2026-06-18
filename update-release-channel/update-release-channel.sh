#!/bin/bash
# Update release channel files at
# s3://downloads-cdn-eu-central-1-prod/<prefix>/<product>/<channel>.json
# and s3://downloads-cdn-eu-central-1-prod/<prefix>/<product>/<channel>.version
# (served at https://binaries.sonarsource.com/<prefix>/<product>/<channel>.json
# and https://binaries.sonarsource.com/<prefix>/<product>/<channel>.version).
#
# Required environment variables:
#   VERSION - Version the channel should point at (e.g. "0.9.0.977")
#   CHANNEL - Channel name (latest|stable|beta|rc|dogfood)
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
readonly CACHE_CONTROL="no-cache, no-store, max-age=0"

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
VERSION_KEY="$PREFIX/$PRODUCT/$CHANNEL.version"
VERSION_URL="$PUBLIC_BASE_URL/$VERSION_KEY"
UPDATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
JSON_BODY="$(jq -cn --arg v "$VERSION" --arg t "$UPDATED_AT" '{schemaVersion:1, version:$v, updatedAt:$t}')"
VERSION_BODY="$VERSION"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "Dry-run: aws s3api put-object --bucket $BUCKET --key $KEY --cache-control '$CACHE_CONTROL' --content-type application/json --body <generated-json-file>"
  echo "Dry-run body: $JSON_BODY"
  echo "Dry-run: aws s3api put-object --bucket $BUCKET --key $VERSION_KEY --cache-control '$CACHE_CONTROL' --content-type text/plain --body <generated-version-file>"
  echo "Dry-run version body: $VERSION_BODY"
else
  JSON_FILE="$(mktemp)"
  VERSION_FILE="$(mktemp)"
  trap 'rm -f "$JSON_FILE" "$VERSION_FILE"' EXIT
  printf '%s' "$JSON_BODY" > "$JSON_FILE"
  printf '%s' "$VERSION_BODY" > "$VERSION_FILE"

  aws s3api put-object \
    --bucket "$BUCKET" --key "$KEY" --body "$JSON_FILE" \
    --cache-control "$CACHE_CONTROL" --content-type "application/json" > /dev/null
  aws s3api put-object \
    --bucket "$BUCKET" --key "$VERSION_KEY" --body "$VERSION_FILE" \
    --cache-control "$CACHE_CONTROL" --content-type "text/plain" > /dev/null
  echo "Wrote $URL"
  echo "Wrote $VERSION_URL"
fi

{
  echo "bucket=$BUCKET"
  echo "key=$KEY"
  echo "url=$URL"
  echo "body=$JSON_BODY"
} >> "${GITHUB_OUTPUT:?}"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  echo "**update-release-channel** → [\`$KEY\`]($URL), [\`$VERSION_KEY\`]($VERSION_URL) (version \`$VERSION\`, dry-run \`$DRY_RUN\`)" >> "$GITHUB_STEP_SUMMARY"
fi
