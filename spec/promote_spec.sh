#!/bin/bash
eval "$(shellspec - -c) exit 1"

Mock jf
  if [[ "$*" == 'rt curl "api/build'* ]]; then
    cat <<EOF
{
  "buildInfo" : {
    "properties" : {
      "buildInfo.env.ARTIFACTORY_DEPLOY_REPO" : "sonarsource-deploy-qa",
      "buildInfo.env.BUILD_NUMBER" : "42"
      "buildInfo.env.PROJECT_VERSION" : "1.2.3.42",
    }
}
EOF
  else
    echo "jf $*"
  fi
End
Mock gh
  if [[ "$*" =~ "defaultBranchRef" ]]; then
    echo "default-branch"
  else
    echo "gh $*"
  fi
End
Mock jq
  if [[ "$*" == *"buildInfo.env.ARTIFACTORY_DEPLOY_REPO"* ]]; then
    echo "sonarsource-deploy-qa"
  elif [[ "$*" == *"buildInfo.env.PROJECT_VERSION"* ]]; then
    echo "1.2.3.42"
  elif [[ "$*" == *"buildInfo.env.NON_EXISTING_PROPERTY"* ]]; then
    echo "null"
  else
    echo "jq $*"
  fi
End

# Minimal environment variables
export ARTIFACTORY_PROMOTE_ACCESS_TOKEN="dummy promote token"
export ARTIFACTORY_URL="https://dummy.repox"
export BUILD_NAME="dummy-project"
export BUILD_NUMBER="42"
export DEFAULT_BRANCH="main"
export GITHUB_EVENT_NAME="push"
export GITHUB_REF="refs/heads/dummy-branch"
export GITHUB_REF_NAME="dummy-branch"
export GITHUB_REPOSITORY="SonarSource/dummy-project"
export GITHUB_SHA="abc123"
export GITHUB_TOKEN="promotion token"
export PROJECT_VERSION="1.2.3"
export PROMOTE_PULL_REQUEST="false"
GITHUB_EVENT_PATH=$(mktemp)
export GITHUB_EVENT_PATH
GITHUB_STEP_SUMMARY=$(mktemp)
export GITHUB_STEP_SUMMARY

Describe 'promote/promote.sh'
  It 'does not run promote() if the script is sourced'
    When run source promote/promote.sh
    The status should be success
    The output should equal ""
  End

  It 'skips promotion for merge queue branches'
    export GITHUB_REF_NAME="gh-readonly-queue/main"
    When run script promote/promote.sh
    The status should be success
    The output should include "promotion skipped"
  End

  It 'fails on working branch'
    When run script promote/promote.sh
    The status should be failure
    The line 1 should include "gh"
    The line 2 should include "gh"
    The line 3 should include "jq"
    The line 4 should include "jq"
    The line 5 should include "jf"
    The line 6 should include "jf"
    The error should start with "Promotion is only available for"
  End

  It 'runs promote() on pull_request when promotion is enabled'
    export ARTIFACTORY_TARGET_REPO="artifactory-target"
    export GITHUB_EVENT_NAME="pull_request"
    export GITHUB_REF_NAME="123/merge"
    export PROMOTE_PULL_REQUEST="true"
    When run script promote/promote.sh
    The status should be success
    The lines of stdout should equal 12
    The line 1 should include "gh"
    The line 2 should include "gh"
    The line 3 should include "jq"
    The line 4 should include "jq"
    The line 5 should include "jf"
    The line 6 should include "jf"
    The line 7 should equal "jf config remove repox"
    The line 8 should equal "jf config add repox --artifactory-url https://dummy.repox --access-token dummy promote token"
    The line 9 should equal "Promoting build dummy-project/$BUILD_NUMBER (version: 1.2.3.42)"
    The line 10 should equal "Target repository: $ARTIFACTORY_TARGET_REPO"
    The line 11 should equal "jf rt bpr --status it-passed-pr dummy-project $BUILD_NUMBER $ARTIFACTORY_TARGET_REPO"
    The line 12 should include "gh api -X POST"
  End

  It 'skips promotion on pull_request when promotion is disabled'
    export GITHUB_EVENT_NAME="pull_request"
    export GITHUB_REF_NAME="123/merge"
    export PROMOTE_PULL_REQUEST="false"
    When run script promote/promote.sh
    The status should be success
    The output should include "Pull request promotion is disabled"
  End
End

Include promote/promote.sh

Describe 'set_build_env()'
  It 'sets the default branch'
    unset DEFAULT_BRANCH
    When call set_build_env
    The variable DEFAULT_BRANCH should equal "default-branch"
  End
End

Describe 'check_branch()'
  # merge queue branches use case is handled in promote.sh, due to the exit 0 in check_branch
  It 'allows pull requests when promotion is enabled'
    export GITHUB_EVENT_NAME="pull_request"
    export GITHUB_REF_NAME="123/merge"
    export PROMOTE_PULL_REQUEST="true"
    When call check_branch
    The status should be success
  End


  It 'allows main branch'
    export GITHUB_REF_NAME="main"
    When call check_branch
    The status should be success
  End

  It 'allows maintenance branches'
    export GITHUB_REF_NAME="branch-123"
    When call check_branch
    The status should be success
  End

  It 'allows dogfood branches'
    export GITHUB_REF_NAME="dogfood-on-123"
    When call check_branch
    The status should be success
  End

  It 'fails on working branch'
    export GITHUB_REF_NAME="feat/jdoe/JIRA-123-something"
    When call check_branch
    The status should be failure
    The error should start with "Promotion is only available for"
  End
End

Describe 'jfrog_config_repox()'
  It 'configures Repox using JFrog CLI'
    When call jfrog_config_repox
    The line 1 should equal "jf config remove repox"
    The line 2 should start with "jf config add repox"
  End
End

Describe 'get_target_repos()'
  It 'returns target repositories for pull requests'
    export GITHUB_EVENT_NAME="pull_request"
    export GITHUB_REF_NAME="123/merge"
    When call get_target_repos
    The status should be success
    The variable targetRepo1 should equal "sonarsource-private-dev"
    The variable targetRepo2 should equal "sonarsource-public-dev"
    The variable TARGET_REPOS should equal "sonarsource-private-dev, sonarsource-public-dev"
  End

  It 'returns target repositories for main branch'
    export GITHUB_REF_NAME="main"
    When call get_target_repos
    The status should be success
    The variable targetRepo1 should equal "sonarsource-private-builds"
    The variable targetRepo2 should equal "sonarsource-public-builds"
    The variable TARGET_REPOS should equal "sonarsource-private-builds, sonarsource-public-builds"
  End

  It 'returns target repositories for maintenance branch'
    export GITHUB_REF_NAME="branch-123"
    When call get_target_repos
    The status should be success
    The variable targetRepo1 should equal "sonarsource-private-builds"
    The variable targetRepo2 should equal "sonarsource-public-builds"
    The variable TARGET_REPOS should equal "sonarsource-private-builds, sonarsource-public-builds"
  End

  It 'returns target repositories for dogfood branch'
    export GITHUB_REF_NAME="dogfood-on-123"
    When call get_target_repos
    The status should be success
    The variable targetRepo1 should equal "sonarsource-dogfood-builds"
    The variable targetRepo2 should equal "sonarsource-dogfood-builds"
    The variable TARGET_REPOS should equal "sonarsource-dogfood-builds, sonarsource-dogfood-builds"
  End
End

Describe 'promote_multi()'
  It 'calls the multiRepoPromote plugin with version display'
    export GITHUB_REF_NAME="main"
    export status='it-passed'
    export PROJECT_VERSION="1.2.3.42"
    get_target_repos
    When call promote_multi
    The line 1 should equal "Promoting build dummy-project/$BUILD_NUMBER (version: 1.2.3.42)"
    The line 2 should equal "Target repositories: sonarsource-private-builds and sonarsource-public-builds"
    The line 3 should match pattern "jf rt curl */multiRepoPromote?*;src1=*;target1=*;src2=*;target2=*"
  End
End

Describe 'get_build_info_property()'
  It 'returns the ARTIFACTORY_DEPLOY_REPO property'
    When call get_build_info_property "ARTIFACTORY_DEPLOY_REPO"
    The status should be success
    The output should equal "sonarsource-deploy-qa"
  End

  It 'returns an error for a non-existing property'
    When call get_build_info_property "NON_EXISTING_PROPERTY"
    The status should be failure
    The error should include "Failed to retrieve NON_EXISTING_PROPERTY from buildInfo for build dummy-project/42"
  End
End

Describe 'get_target_repo()'
  It 'returns the target repository for pull requests'
    export GITHUB_EVENT_NAME="pull_request"
    export GITHUB_REF_NAME="123/merge"
    When call get_target_repo
    The status should be success
    The output should equal "ARTIFACTORY_DEPLOY_REPO=sonarsource-deploy-qa"
    The variable targetRepo should equal "sonarsource-deploy-dev"
    The variable TARGET_REPOS should equal "sonarsource-deploy-dev"
  End

  It 'returns the target repository for main branch'
    export GITHUB_REF_NAME="main"
    When call get_target_repo
    The status should be success
    The output should equal "ARTIFACTORY_DEPLOY_REPO=sonarsource-deploy-qa"
    The variable targetRepo should equal "sonarsource-deploy-builds"
    The variable TARGET_REPOS should equal "sonarsource-deploy-builds"
  End

  It 'returns the target repository for maintenance branch'
    export GITHUB_REF_NAME="branch-123"
    When call get_target_repo
    The status should be success
    The output should equal "ARTIFACTORY_DEPLOY_REPO=sonarsource-deploy-qa"
    The variable targetRepo should equal "sonarsource-deploy-builds"
    The variable TARGET_REPOS should equal "sonarsource-deploy-builds"
  End

  It 'returns the target repository for dogfood branch'
    export GITHUB_REF_NAME="dogfood-on-123"
    When call get_target_repo
    The status should be success
    The output should equal "ARTIFACTORY_DEPLOY_REPO=sonarsource-deploy-qa"
    The variable targetRepo should equal "sonarsource-dogfood-builds"
    The variable TARGET_REPOS should equal "sonarsource-dogfood-builds"
  End
End

Describe 'jfrog_promote()'
  It 'sets the status for pull requests then promotes with version display'
    export GITHUB_EVENT_NAME="pull_request"
    export GITHUB_REF_NAME="123/merge"
    export ARTIFACTORY_DEPLOY_REPO="artifactory-deploy-repo-qa"
    When call jfrog_promote
    The status should be success
    The variable PROJECT_VERSION should equal "1.2.3.42"
    The line 1 should equal "ARTIFACTORY_DEPLOY_REPO=artifactory-deploy-repo-qa"
    The line 2 should equal "Promoting build dummy-project/$BUILD_NUMBER (version: 1.2.3.42)"
    The line 3 should equal "Target repository: artifactory-deploy-repo-dev"
    The line 4 should equal "jf rt bpr --status it-passed-pr dummy-project $BUILD_NUMBER artifactory-deploy-repo-dev"
  End

  It 'promotes the build artifacts to the specified target with version display'
    export ARTIFACTORY_TARGET_REPO="artifactory-target"
    When call jfrog_promote
    The variable PROJECT_VERSION should equal "1.2.3.42"
    The line 1 should equal "Promoting build dummy-project/$BUILD_NUMBER (version: 1.2.3.42)"
    The line 2 should equal "Target repository: artifactory-target"
    The line 3 should equal "jf rt bpr --status it-passed dummy-project $BUILD_NUMBER artifactory-target"
  End

  It 'does multi-promotion when MULTI_REPO_PROMOTE is true with version display'
    export GITHUB_REF_NAME="main"
    export MULTI_REPO_PROMOTE="true"
    When call jfrog_promote
    The status should be success
    The variable PROJECT_VERSION should equal "1.2.3.42"
    The line 1 should equal "Promoting build dummy-project/$BUILD_NUMBER (version: 1.2.3.42)"
    The line 2 should equal "Target repositories: sonarsource-private-builds and sonarsource-public-builds"
    The line 3 should match pattern "jf rt curl */multiRepoPromote?*;src1=*;target1=*;src2=*;target2=*"
  End

End

Describe 'github_notify_promotion()'
  It 'calls gh api with correct parameters'
    When call github_notify_promotion
    The output should include "gh api -X POST -H X-GitHub-Api-Version: 2022-11-28"
    The output should include "https://api.github.com/repos/$GITHUB_REPOSITORY/statuses/$GITHUB_SHA"
    The output should include "-H Content-Type: application/json --input -"
  End
End

Describe 'promote()'
  Mock check_tool
  End
  Mock set_build_env
  End
  Mock jfrog_config_repox
  End
  Mock github_notify_promotion
  End

  It 'runs the full promotion process for the main branch'
    export GITHUB_REF_NAME="main"
    When call promote
    The status should be success
    The line 1 should equal "ARTIFACTORY_DEPLOY_REPO=sonarsource-deploy-qa"
    The line 2 should equal "Promoting build dummy-project/$BUILD_NUMBER (version: 1.2.3.42)"
    The line 3 should equal "Target repository: sonarsource-deploy-builds"
  End

  It 'customizes the build name with BUILD_NAME not equal to the repository name'
    export BUILD_NAME="dummy-project-abc"
    export GITHUB_REF_NAME="main"
    When call promote
    The status should be success
    The variable BUILD_NAME should equal "dummy-project-abc"
    The line 2 should equal "Promoting build $BUILD_NAME/$BUILD_NUMBER (version: 1.2.3.42)"
    The line 3 should equal "Target repository: sonarsource-deploy-builds"
    The line 4 should equal "jf rt bpr --status it-passed dummy-project-abc 42 sonarsource-deploy-builds"
  End
End
