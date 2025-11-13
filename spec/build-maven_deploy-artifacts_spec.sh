#!/bin/bash
eval "$(shellspec - -c) exit 1"

Mock jfrog
  echo "jfrog $*"
End

# Set required environment variables
export ARTIFACTORY_URL="https://dummy.repox"
export ARTIFACTORY_DEPLOY_REPO="deploy-repo-qa"
export ARTIFACTORY_DEPLOY_ACCESS_TOKEN="deploy-token"
export ARTIFACTORY_PRIVATE_DEPLOY_REPO="private-repo-qa"
export ARTIFACTORY_PRIVATE_DEPLOY_ACCESS_TOKEN="private-token"
export GITHUB_REPOSITORY="sonarsource/test-repo"
export BUILD_NUMBER="42"

Describe 'build-maven/deploy-artifacts.sh'
  It 'deploys public and private artifacts correctly'
    MAVEN_CONFIG=$(mktemp -d)
    export MAVEN_CONFIG
    mkdir -p "$MAVEN_CONFIG/repository"
    export INSTALLED_ARTIFACTS="org/sonarsource/app/1.0/app-1.0.pom
org/sonarsource/app/1.0/app-1.0.jar
com/sonarsource/private/app/1.0/app-1.0.pom
com/sonarsource/private/app/1.0/app-1.0.jar"

    When run script build-maven/deploy-artifacts.sh
    The status should be success
    The lines of stdout should equal 11
    The line 2 of output should equal "jfrog config add deploy --artifactory-url https://dummy.repox --access-token deploy-token"
    The line 3 of output should equal "jfrog config use deploy"
    The line 4 of output should include "Deploying public artifacts..."
    The line 5 of output should include "org/sonarsource/app/1.0/app-1.0.pom deploy-repo-qa"
    The line 6 of output should include "org/sonarsource/app/1.0/app-1.0.jar deploy-repo-qa"
    The line 7 of output should equal "Deploying private artifacts..."
    The line 8 of output should equal "jfrog config edit deploy --artifactory-url https://dummy.repox --access-token private-token"
    The line 9 of output should include "com/sonarsource/private/app/1.0/app-1.0.pom private-repo-qa"
    The line 10 of output should include "com/sonarsource/private/app/1.0/app-1.0.jar private-repo-qa"

    rm -rf "$MAVEN_CONFIG"
  End

  It 'warns about unrecognized artifact paths'
    MAVEN_CONFIG=$(mktemp -d)
    export MAVEN_CONFIG
    mkdir -p "$MAVEN_CONFIG/repository"
    export INSTALLED_ARTIFACTS="org/sonarsource/app/1.0/app-1.0.pom
unknown/artifact/path.jar
com/sonarsource/private/app/1.0/app-1.0.pom"

    When run script build-maven/deploy-artifacts.sh
    The status should be success
    The stderr should include "WARN: Unrecognized artifact path: unknown/artifact/path.jar"
    The output should include "org/sonarsource/app/1.0/app-1.0.pom"
    The output should include "com/sonarsource/private/app/1.0/app-1.0.pom"

    rm -rf "$MAVEN_CONFIG"
  End
End
