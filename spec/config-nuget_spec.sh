#!/usr/bin/env bash
eval "$(shellspec - -c) exit 1"

export GITHUB_ENV=/dev/null
export ARTIFACTORY_URL="https://repox-internal.dev.sonar.build/artifactory"
export ARTIFACTORY_USERNAME="reader"
export ARTIFACTORY_ACCESS_TOKEN="reader-token"
export NUGET_CONFIG_FILES="NuGet.Config"

Describe 'config-nuget/nuget_config.sh'
  It 'does not run main when sourced'
    When run source config-nuget/nuget_config.sh
    The status should be success
    The output should equal ""
  End
End

Include config-nuget/nuget_config.sh

write_nuget_config() {
  local nuget_config="$1"
  cat > "$nuget_config" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="Repox proxy" value="https://repox.jfrog.io/artifactory/api/nuget/v3/nuget/index.json" protocolVersion="3" />
    <add key="Repox releases" value="https://repox.jfrog.io/artifactory/api/nuget/v3/sonarsource-nuget-releases/index.json" />
  </packageSources>
  <trustedSigners>
    <repository name="Repox" serviceIndex="https://repox.jfrog.io/artifactory/api/nuget/v3/nuget/index.json" />
  </trustedSigners>
</configuration>
EOF
  return
}

common_setup() {
  WORK_DIR=$(mktemp -d)
  cd "$WORK_DIR" || exit 1
  GITHUB_ENV=$(mktemp)
  export GITHUB_ENV
}

common_cleanup() {
  cd - > /dev/null || true
  rm -rf "$WORK_DIR" "$GITHUB_ENV"
  return
}

Describe 'export_credentials()'
  BeforeEach 'common_setup'
  AfterEach 'common_cleanup'

  It 'exports the reader credentials for NuGet and other tools'
    When call export_credentials
    The status should be success
    The contents of file "$GITHUB_ENV" should include "ARTIFACTORY_URL=https://repox-internal.dev.sonar.build/artifactory"
    The contents of file "$GITHUB_ENV" should include "ARTIFACTORY_USERNAME=reader"
    The contents of file "$GITHUB_ENV" should include "ARTIFACTORY_ACCESS_TOKEN=reader-token"
    The contents of file "$GITHUB_ENV" should include "ARTIFACTORY_USER=reader"
    The contents of file "$GITHUB_ENV" should include "ARTIFACTORY_PASSWORD=reader-token"
  End
End

Describe 'point_nuget_config()'
  BeforeEach 'common_setup'
  AfterEach 'common_cleanup'

  It 'points every Repox package source at ARTIFACTORY_URL'
    write_nuget_config NuGet.Config
    When call point_nuget_config NuGet.Config
    The status should be success
    The output should equal "Package sources of NuGet.Config now resolve through https://repox-internal.dev.sonar.build/artifactory"
    The contents of file NuGet.Config should include 'value="https://repox-internal.dev.sonar.build/artifactory/api/nuget/v3/nuget/index.json"'
    The contents of file NuGet.Config should include 'value="https://repox-internal.dev.sonar.build/artifactory/api/nuget/v3/sonarsource-nuget-releases/index.json"'
    The contents of file NuGet.Config should include 'serviceIndex="https://repox.jfrog.io/artifactory/api/nuget/v3/nuget/index.json"'
    The file NuGet.Config.bak should not be exist
  End

  It 'skips a file that already resolves through ARTIFACTORY_URL'
    write_nuget_config NuGet.Config
    point_nuget_config NuGet.Config > /dev/null
    When call point_nuget_config NuGet.Config
    The status should be success
    The output should equal "Package sources of NuGet.Config already resolve through https://repox-internal.dev.sonar.build/artifactory"
    The contents of file NuGet.Config should include 'value="https://repox-internal.dev.sonar.build/artifactory/api/nuget/v3/nuget/index.json"'
  End

  It 'fails when the file does not exist'
    When call point_nuget_config missing/NuGet.Config
    The status should be failure
    The stderr should equal "::error::NuGet configuration file not found: missing/NuGet.Config"
  End

  It 'fails when the file has no Repox package source'
    echo '<configuration><packageSources><add key="nuget.org" value="https://api.nuget.org/v3/index.json" /></packageSources></configuration>' > NuGet.Config
    When call point_nuget_config NuGet.Config
    The status should be failure
    The stderr should equal "::error::No package source on https://repox.jfrog.io/artifactory in NuGet.Config"
  End
End

Describe 'main()'
  BeforeEach 'common_setup'
  AfterEach 'common_cleanup'

  It 'updates every listed file and skips blank lines'
    mkdir -p a b
    write_nuget_config a/NuGet.Config
    write_nuget_config b/nuget.config
    export NUGET_CONFIG_FILES=$'a/NuGet.Config\r\n\n  b/nuget.config  \n'
    When call main
    The status should be success
    The line 1 should equal "::group::Configure NuGet"
    The line 2 should equal "Package sources of a/NuGet.Config now resolve through https://repox-internal.dev.sonar.build/artifactory"
    The line 3 should equal "Package sources of b/nuget.config now resolve through https://repox-internal.dev.sonar.build/artifactory"
    The line 4 should equal "::endgroup::"
    The contents of file b/nuget.config should not include 'value="https://repox.jfrog.io/'
  End

  It 'keeps backslashes and apostrophes in listed paths'
    write_nuget_config $'its\\NuGet.config'
    mkdir -p "owner's"
    write_nuget_config "owner's/NuGet.Config"
    export NUGET_CONFIG_FILES=$'its\\NuGet.config\nowner'"'"'s/NuGet.Config'
    When call main
    The status should be success
    The line 2 should equal $'Package sources of its\\NuGet.config now resolve through https://repox-internal.dev.sonar.build/artifactory'
    The line 3 should equal "Package sources of owner's/NuGet.Config now resolve through https://repox-internal.dev.sonar.build/artifactory"
  End

  It 'leaves the files unchanged with SaaS Repox'
    write_nuget_config NuGet.Config
    export ARTIFACTORY_URL="https://repox.jfrog.io/artifactory"
    export NUGET_CONFIG_FILES="NuGet.Config"
    When call main
    The status should be success
    The line 2 should equal "NuGet configuration files already resolve through https://repox.jfrog.io/artifactory"
    The contents of file NuGet.Config should include 'value="https://repox.jfrog.io/artifactory/api/nuget/v3/nuget/index.json"'
    The contents of file "$GITHUB_ENV" should include "ARTIFACTORY_URL=https://repox.jfrog.io/artifactory"
  End

  It 'fails when a listed file is missing'
    export NUGET_CONFIG_FILES="missing/NuGet.Config"
    When run main
    The status should be failure
    The line 1 should equal "::group::Configure NuGet"
    The stderr should equal "::error::NuGet configuration file not found: missing/NuGet.Config"
  End
End
