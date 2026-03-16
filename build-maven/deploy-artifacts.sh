#!/bin/bash
# Deploy to public and private Artifactory repositories using JFrog CLI
#
# Required environment variables:
# - ARTIFACTORY_URL: URL to Artifactory repository. Set by 'build-maven'.
# - ARTIFACTORY_DEPLOY_REPO: Repository to deploy public artifacts.
# - ARTIFACTORY_DEPLOY_ACCESS_TOKEN: Access token to deploy to public repository.
# - ARTIFACTORY_PRIVATE_DEPLOY_REPO: Repository to deploy private artifacts
# - ARTIFACTORY_PRIVATE_DEPLOY_ACCESS_TOKEN: Access token to deploy to private repository
# - INSTALLED_ARTIFACTS: Artifacts produced by Maven and installed in the local repository.
# - MAVEN_CONFIG: Path to the Maven configuration directory (typically $HOME/.m2). Set by 'build-maven'.

set -euo pipefail

: "${ARTIFACTORY_URL:?}" "${INSTALLED_ARTIFACTS:?}" "${MAVEN_CONFIG:?}"
: "${ARTIFACTORY_DEPLOY_REPO:?}" "${ARTIFACTORY_DEPLOY_ACCESS_TOKEN:?}"
: "${ARTIFACTORY_PRIVATE_DEPLOY_REPO:?}" "${ARTIFACTORY_PRIVATE_DEPLOY_ACCESS_TOKEN:?}"

public_artifacts=()
private_artifacts=()
for artifact in $INSTALLED_ARTIFACTS; do
  if [[ $artifact == "org/"* ]]; then
    public_artifacts+=("$artifact")
  elif [[ $artifact == "com/"* ]]; then
    private_artifacts+=("$artifact")
  else
    echo "::warning title=Unrecognized artifact::Unrecognized artifact path: $artifact" >&2
  fi
done

build_name="${GITHUB_REPOSITORY#*/}"
pushd "$MAVEN_CONFIG/repository"

echo "::group::Configure JFrog deployment"
jf config remove deploy > /dev/null 2>&1 || true # Ignore inexistent configuration
jf config add deploy --url "${ARTIFACTORY_URL%/artifactory*}" --artifactory-url "$ARTIFACTORY_URL" --access-token "$ARTIFACTORY_DEPLOY_ACCESS_TOKEN"
jf config use deploy
echo "::endgroup::"

echo "::group::Deploy public artifacts"
echo "Deploying public artifacts..."
for artifact in "${public_artifacts[@]}"; do
  jf rt u --build-name "$build_name" --build-number "$BUILD_NUMBER" "$artifact" "${ARTIFACTORY_DEPLOY_REPO}"
done
echo "::endgroup::"

echo "::group::Deploy private artifacts"
echo "Deploying private artifacts..."
jf config edit deploy --artifactory-url "$ARTIFACTORY_URL" --access-token "$ARTIFACTORY_PRIVATE_DEPLOY_ACCESS_TOKEN"
for artifact in "${private_artifacts[@]}"; do
  jf rt u --build-name "$build_name" --build-number "$BUILD_NUMBER" "$artifact" "${ARTIFACTORY_PRIVATE_DEPLOY_REPO}"
done
echo "::endgroup::"

popd
