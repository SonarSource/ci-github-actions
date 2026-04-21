#!/bin/bash
# Verify that SonarQube SCA (Software Composition Analysis) ran for the project.
#
# Discovers project keys from config files, polls the SonarQube measures API
# on all three instances (next, sqc-us, sqc-eu), and fails if SCA data is
# missing after timeout.
#
# Required environment variables:
#   NEXT_URL, NEXT_TOKEN         - SonarQube Next credentials
#   SQC_US_URL, SQC_US_TOKEN     - SonarCloud US credentials
#   SQC_EU_URL, SQC_EU_TOKEN     - SonarCloud EU credentials
#   GITHUB_REPOSITORY            - GitHub repo (e.g. SonarSource/my-repo)
#   GITHUB_OUTPUT                - GitHub Actions output file
#
# Optional environment variables:
#   PROJECT_KEY_INPUT             - Explicit project key (additional to discovered keys)
#   POLL_TIMEOUT                  - Max polling time in seconds (default: 300)
#   POLL_INTERVAL                 - Seconds between polls (default: 15)
#   WORKING_DIRECTORY             - Directory to search for config files (default: .)

set -euo pipefail

: "${NEXT_URL:?}" "${NEXT_TOKEN:?}" "${SQC_US_URL:?}" "${SQC_US_TOKEN:?}" "${SQC_EU_URL:?}" "${SQC_EU_TOKEN:?}"
: "${GITHUB_REPOSITORY:?}" "${GITHUB_OUTPUT:?}"
: "${POLL_TIMEOUT:=300}" "${POLL_INTERVAL:=15}" "${WORKING_DIRECTORY:=.}"
: "${PROJECT_KEY_INPUT:=}"

readonly ENDGROUP="::endgroup::"

# Platform definitions: name:url_var:token_var
PLATFORMS=(
  "next:NEXT_URL:NEXT_TOKEN"
  "sqc-us:SQC_US_URL:SQC_US_TOKEN"
  "sqc-eu:SQC_EU_URL:SQC_EU_TOKEN"
)

# Discover candidate SonarQube project keys from config files.
# Returns one key per line, deduplicated, in priority order.
discover_project_keys() {
  local keys=()
  local work_dir="${WORKING_DIRECTORY:-.}"

  # 1. Explicit input takes highest priority
  if [[ -n "${PROJECT_KEY_INPUT:-}" ]]; then
    keys+=("$PROJECT_KEY_INPUT")
  fi

  # 2. .sonarlint/connectedMode.json
  local sonarlint_file="$work_dir/.sonarlint/connectedMode.json"
  if [[ -f "$sonarlint_file" ]]; then
    local key
    key=$(jq -r '.projectKey // empty' "$sonarlint_file" 2>/dev/null || true)
    if [[ -n "$key" ]]; then
      keys+=("$key")
    fi
  fi

  # 3. sonar-project.properties
  local sonar_props="$work_dir/sonar-project.properties"
  if [[ -f "$sonar_props" ]]; then
    local key
    key=$(grep -E '^sonar\.projectKey=' "$sonar_props" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '[:space:]')
    if [[ -n "$key" ]]; then
      keys+=("$key")
    fi
  fi

  # 4. pom.xml
  local pom_file="$work_dir/pom.xml"
  if [[ -f "$pom_file" ]]; then
    local key
    key=$(perl -ne 'print $1 if /<sonar\.projectKey>([^<]+)/' "$pom_file" 2>/dev/null | head -1 || true)
    if [[ -n "$key" ]]; then
      keys+=("$key")
    fi
  fi

  # 5. build.gradle / build.gradle.kts
  local gradle_file
  for gradle_file in "$work_dir/build.gradle" "$work_dir/build.gradle.kts"; do
    if [[ -f "$gradle_file" ]]; then
      local key
      key=$(perl -ne 'print $1 if /sonar\.projectKey[^"]*"([^"]+)"/' "$gradle_file" 2>/dev/null | head -1 || true)
      if [[ -n "$key" ]]; then
        keys+=("$key")
      fi
    fi
  done

  # 6. Derive from GITHUB_REPOSITORY (e.g. SonarSource/repo-name -> SonarSource_repo-name)
  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    local derived_key="${GITHUB_REPOSITORY/\//_}"
    keys+=("$derived_key")
  fi

  # Deduplicate while preserving order
  local seen=()
  for k in "${keys[@]+"${keys[@]}"}"; do
    local is_dup=false
    for s in "${seen[@]+"${seen[@]}"}"; do
      if [[ "$s" == "$k" ]]; then
        is_dup=true
        break
      fi
    done
    if [[ "$is_dup" == "false" ]]; then
      seen+=("$k")
      echo "$k"
    fi
  done
  return 0
}

# Check if the sca_count_any_issue metric exists for a project on a SonarQube instance.
# Writes "platform_name:project_key" to result_file on success.
# Args: url token project_key platform_name result_dir
check_sca_metric() {
  local url="${1:?}" token="${2:?}" project_key="${3:?}" platform_name="${4:?}" result_dir="${5:?}"

  local api_url="${url}/api/measures/component?component=${project_key}&metricKeys=sca_count_any_issue"

  local response http_code body
  response=$(curl -s --max-time 10 -w "\n%{http_code}" \
    -H "Authorization: Bearer ${token}" \
    "${api_url}" 2>/dev/null) || return 1

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" != "200" ]]; then
    return 1
  fi

  local metric_value
  metric_value=$(echo "$body" | jq -r '
    .component.measures[]?
    | select(.metric == "sca_count_any_issue")
    | .value // empty
  ' 2>/dev/null) || return 1

  if [[ -n "$metric_value" ]]; then
    echo "${platform_name}:${project_key}" > "${result_dir}/match"
    return 0
  fi

  return 1
}

main() {
  echo "::group::Discover project keys"
  local project_keys=()
  while IFS= read -r line; do
    project_keys+=("$line")
  done < <(discover_project_keys)

  if [[ ${#project_keys[@]} -eq 0 ]]; then
    echo "::error title=No project keys::Could not discover any SonarQube project keys" >&2
    echo "$ENDGROUP"
    echo "sca-verified=false" >> "$GITHUB_OUTPUT"
    exit 1
  fi

  echo "Discovered project keys:"
  for key in "${project_keys[@]}"; do
    echo "  - $key"
  done
  echo "$ENDGROUP"

  echo "::group::Poll for SCA data"
  local start_time
  start_time=$(date +%s)
  local attempt=0
  local result_dir
  result_dir=$(mktemp -d)

  while true; do
    attempt=$((attempt + 1))
    local elapsed=$(( $(date +%s) - start_time ))

    if [[ $elapsed -ge $POLL_TIMEOUT ]]; then
      echo "::error title=SCA check timeout::Timed out after ${POLL_TIMEOUT}s waiting for SCA data" >&2
      echo "$ENDGROUP"
      echo "sca-verified=false" >> "$GITHUB_OUTPUT"
      rm -rf "$result_dir"
      exit 1
    fi

    echo "--- Poll attempt $attempt (${elapsed}s / ${POLL_TIMEOUT}s) ---"

    # Run all checks in parallel
    rm -f "${result_dir}/match"
    local pids=()
    for key in "${project_keys[@]}"; do
      for platform_def in "${PLATFORMS[@]}"; do
        IFS=':' read -r platform_name url_var token_var <<< "$platform_def"
        local url="${!url_var}" token="${!token_var}"

        echo "  Checking $platform_name / $key ..."
        check_sca_metric "$url" "$token" "$key" "$platform_name" "$result_dir" &
        pids+=($!)
      done
    done

    # Wait for all background jobs to finish
    for pid in "${pids[@]}"; do
      wait "$pid" 2>/dev/null || true
    done

    # Check if any succeeded
    if [[ -f "${result_dir}/match" ]]; then
      local match
      match=$(cat "${result_dir}/match")
      local found_platform="${match%%:*}"
      local found_key="${match#*:}"
      echo "  SCA verified on $found_platform for project key: $found_key"
      echo "$ENDGROUP"
      {
        echo "sca-verified=true"
        echo "platform=$found_platform"
        echo "project-key=$found_key"
      } >> "$GITHUB_OUTPUT"
      rm -rf "$result_dir"
      exit 0
    fi

    echo "SCA data not yet available. Waiting ${POLL_INTERVAL}s..."
    sleep "$POLL_INTERVAL"
  done
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
