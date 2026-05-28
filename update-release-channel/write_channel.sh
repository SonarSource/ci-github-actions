#!/bin/bash
# Resolve inputs for the update-release-channel action and write the channel pointer to S3.
#
# Required environment variables (provided by action.yml):
# - VERSION: Version the channel should point at.
# - CHANNEL: Channel name (`latest`, `stable`, `beta`, `rc`).
# - PREFIX:  S3 key prefix (e.g. `Distribution`).
# - PRODUCT: Product folder name on S3 (defaults to the GitHub repository name).
# - DRY_RUN: `true` to skip any real AWS call.

set -euo pipefail

: "${VERSION:?}" "${CHANNEL:?}" "${PREFIX:?}" "${PRODUCT:?}"
: "${DRY_RUN:=false}"

BUCKET="downloads-cdn-eu-central-1-prod"
KEY="${PREFIX}/${PRODUCT}/${CHANNEL}.json"

echo "::group::Resolved inputs"
echo "version: ${VERSION}"
echo "channel: ${CHANNEL}"
echo "prefix:  ${PREFIX}"
echo "product: ${PRODUCT}"
echo "dryRun:  ${DRY_RUN}"
echo "bucket:  ${BUCKET}"
echo "key:     ${KEY}"
echo "::endgroup::"

{
  echo "bucket=${BUCKET}"
  echo "key=${KEY}"
  echo "etag="
} >> "${GITHUB_OUTPUT:?}"
