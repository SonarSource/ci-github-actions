#!/bin/bash
# Verify that SonarQube SCA (Software Composition Analysis) ran for the project.
#
# Discovers project keys from config files, polls the SonarQube measures API
# on all three instances (next, sqc-us, sqc-eu), and fails if SCA data is
# missing after timeout. On timeout it reports an actionable diagnosis based on
# what was observed (project not found, found-but-no-SCA-data, or API errors).
#
# Required environment variables:
#   NEXT_URL, NEXT_TOKEN         - SonarQube Next credentials
#   SQC_US_URL, SQC_US_TOKEN     - SonarCloud US credentials
#   SQC_EU_URL, SQC_EU_TOKEN     - SonarCloud EU credentials
#   GITHUB_REPOSITORY            - GitHub repo (e.g. SonarSource/my-repo)
#   GITHUB_OUTPUT                - GitHub Actions output file
#
# Optional environment variables:
#   PROJECT_KEY_INPUT             - Comma- or newline-separated explicit project keys
#   PROJECT_KEY_MODE_INPUT        - any (default) or all; overrides metadata
#   REPOSITORY_KEY_FALLBACK_INPUT  - true (default) or false; overrides metadata
#   POLL_TIMEOUT                  - Max polling time in seconds (default: 300)
#   POLL_INTERVAL                 - Seconds between polls (default: 15)
#   PULL_REQUEST                  - PR number; when set, also checks PR-specific analysis
#   WORKING_DIRECTORY             - Directory to search for config files (default: .)

set -euo pipefail

: "${NEXT_URL:?}" "${NEXT_TOKEN:?}" "${SQC_US_URL:?}" "${SQC_US_TOKEN:?}" "${SQC_EU_URL:?}" "${SQC_EU_TOKEN:?}"
: "${GITHUB_REPOSITORY:?}" "${GITHUB_OUTPUT:?}"
: "${POLL_TIMEOUT:=300}" "${POLL_INTERVAL:=15}" "${WORKING_DIRECTORY:=.}"
: "${PROJECT_KEY_INPUT:=}" "${PULL_REQUEST:=}"

readonly MAX_CONCURRENT_PROBES=16
readonly ENDGROUP="::endgroup::"

# Platform definitions: name:url_var:token_var
PLATFORMS=(
  "next:NEXT_URL:NEXT_TOKEN"
  "sqc-us:SQC_US_URL:SQC_US_TOKEN"
  "sqc-eu:SQC_EU_URL:SQC_EU_TOKEN"
)

# Parse a key=value property from a file. Returns the trimmed value or empty string.
parse_property_value() {
  local file="$1" key="$2"
  grep -E "^${key}=" "$file" | head -1 | cut -d= -f2- | tr -d '[:space:]' || true
}

# Read a value from .github/repo-metadata.yaml under a given top-level section.
# Usage: read_repo_metadata <file> <section> <key>
# Example: read_repo_metadata repo-metadata.yaml "check-sca" "project-key"
read_repo_metadata() {
  local file="$1" section="$2" key="$3"
  sed -n "/^${section}:/,/^[^ ]/{ /^  ${key}:/{ s/^  ${key}:[ ]*//; s/^['\"]//; s/['\"]$//; p; q; }; }" "$file" | tr -d '[:space:]'
}

# Read a scalar, block sequence, or literal block from the metadata key setting.
read_metadata_keys() {
  local metadata_file="$1"
  awk '
    function emit(value) {
      sub(/^[[:space:]]+/, "", value); sub(/[[:space:]]+$/, "", value)
      sub(/^[\047\042]/, "", value); sub(/[\047\042]$/, "", value)
      if (value != "") print value
    }
    /^check-sca:/ { section=1; next }
    section && /^[^ ]/ { section=0 }
    section && /^  project-keys:/ {
      print "::error::Use check-sca.project-key instead of project-keys" > "/dev/stderr"
      invalid=1
    }
    section && /^  project-key:/ {
      value=$0; sub(/^  project-key:[ ]*/, "", value)
      if (value ~ /^\[/) {
        print "::error::Use a scalar or block sequence for check-sca.project-key" > "/dev/stderr"
        invalid=1
      } else if (value == "" || value ~ /^\|[-+]?$/) {
        collecting=1
        literal=(value ~ /^\|[-+]?$/)
      } else emit(value)
      next
    }
    section && collecting && /^  -([ ]|$)/ && !literal {
      value=$0; sub(/^  -[ ]*/, "", value); emit(value); next
    }
    section && collecting && /^  #/ { next }
    collecting && /^  [^ ]/ { collecting=0 }
    section && collecting && /^    / {
      value=$0
      if (literal) sub(/^    /, "", value)
      else {
        if (value !~ /^    -([ ]|$)/) next
        sub(/^    -[ ]*/, "", value)
      }
      emit(value)
    }
    END { if (invalid) exit 1 }
  ' "$metadata_file"
}

# Normalize explicit keys without changing their order.
normalize_keys() {
  tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | awk 'NF && !seen[$0]++'
}

# Action options override metadata; empty option inputs allow metadata defaults.
resolve_configuration() {
  local repo_root="${GITHUB_WORKSPACE:-${WORKING_DIRECTORY:-.}}" metadata_file
  METADATA_FILE=""
  for metadata_file in "$repo_root/.github/repo-metadata.yaml" "$repo_root/.github/repo-metadata.yml"; do
    if [[ -f "$metadata_file" ]]; then
      METADATA_FILE="$metadata_file"
      break
    fi
  done
  local metadata_mode="" metadata_fallback=""
  if [[ -n "$METADATA_FILE" ]]; then
    metadata_mode=$(read_repo_metadata "$METADATA_FILE" check-sca project-key-mode)
    metadata_fallback=$(read_repo_metadata "$METADATA_FILE" check-sca repository-key-fallback)
  fi
  PROJECT_KEY_MODE="${PROJECT_KEY_MODE_INPUT:-${metadata_mode:-any}}"
  REPOSITORY_KEY_FALLBACK="${REPOSITORY_KEY_FALLBACK_INPUT:-${metadata_fallback:-true}}"
  case "$PROJECT_KEY_MODE" in
    any|all) ;;
    *) echo "::error::project-key-mode must be any or all" >&2; return 1 ;;
  esac
  case "$REPOSITORY_KEY_FALLBACK" in
    true|false) ;;
    *) echo "::error::repository-key-fallback must be true or false" >&2; return 1 ;;
  esac
  EXPLICIT_KEYS=$(explicit_project_keys | normalize_keys) || return 1
  if [[ ( "$PROJECT_KEY_MODE" == all || "$REPOSITORY_KEY_FALLBACK" == false ) && -z "$EXPLICIT_KEYS" ]]; then
    echo "::error::Explicit project keys are required for all mode or disabled repository fallback" >&2
    return 1
  fi
}

explicit_project_keys() {
  if [[ -n "${PROJECT_KEY_INPUT:-}" ]]; then
    printf '%s\n' "$PROJECT_KEY_INPUT"
  elif [[ -n "${METADATA_FILE:-}" ]]; then
    read_metadata_keys "$METADATA_FILE"
  fi
}

# Discover candidate SonarQube project keys from config files.
# Returns one key per line, deduplicated, in priority order.
discover_project_keys() {
  local keys=()
  local explicit_key
  while IFS= read -r explicit_key; do
    [[ -n "$explicit_key" ]] && keys+=("$explicit_key")
  done < <(printf '%s\n' "${EXPLICIT_KEYS:-}" | normalize_keys)
  if [[ "${PROJECT_KEY_MODE:-any}" == all ]]; then
    printf '%s\n' "${keys[@]}"
    return 0
  fi
  local work_dir="${WORKING_DIRECTORY:-.}"

  # 1. Explicit input takes highest priority
  if [[ -n "${PROJECT_KEY_INPUT:-}" ]]; then
    keys+=("$PROJECT_KEY_INPUT")
  fi

  # 2. .github/repo-metadata.yaml or .yml (always at repo root, not working-directory)
  local repo_root="${GITHUB_WORKSPACE:-$work_dir}"
  local metadata_file
  for metadata_file in "$repo_root/.github/repo-metadata.yaml" "$repo_root/.github/repo-metadata.yml"; do
    if [[ -f "$metadata_file" ]]; then
      local key
      key=$(read_metadata_keys "$metadata_file") || return 1
      if [[ -n "$key" ]]; then
        keys+=("$key")
      fi
      break
    fi
  done

  # 3. .sonarlint/connectedMode.json
  local sonarlint_file="$work_dir/.sonarlint/connectedMode.json"
  if [[ -f "$sonarlint_file" ]]; then
    local key
    key=$(jq -r '.projectKey // empty' "$sonarlint_file" 2>/dev/null || true)
    if [[ -n "$key" ]]; then
      keys+=("$key")
    fi
  fi

  # 4. sonar-project.properties
  local sonar_props="$work_dir/sonar-project.properties"
  if [[ -f "$sonar_props" ]]; then
    local key
    key=$(parse_property_value "$sonar_props" 'sonar\.projectKey')
    if [[ -n "$key" ]]; then
      keys+=("$key")
    fi
  fi

  # 5. pom.xml
  local pom_file="$work_dir/pom.xml"
  if [[ -f "$pom_file" ]]; then
    # 5a. Explicit sonar.projectKey property (highest priority within pom.xml)
    local key
    key=$(perl -0777 -ne '
      if (/<sonar\.projectKey>([^<]+)/s) {
        my $key = $1;
        $key =~ s/^\s+|\s+$//g;
        print $key;
      }
    ' "$pom_file" 2>/dev/null || true)
    if [[ -n "$key" ]]; then
      keys+=("$key")
    fi

    # 5b. Derive groupId:artifactId (Maven default project key)
    local maven_key
    maven_key=$(perl -0777 -ne '
      sub trim {
        my ($value) = @_;
        $value = "" unless defined $value;
        $value =~ s/^\s+|\s+$//g;
        return $value;
      }

      my $parent_gid = ($_ =~ /<parent>.*?<groupId>([^<]+)/s) ? $1 : "";
      (my $proj = $_) =~ s/<parent>.*?<\/parent>//s;
      $proj =~ s/<dependencyManagement>.*?<\/dependencyManagement>//s;
      $proj =~ s/<dependencies>.*?<\/dependencies>//sg;
      $proj =~ s/<build>.*?<\/build>//s;
      $proj =~ s/<profiles>.*?<\/profiles>//s;
      $proj =~ s/<reporting>.*?<\/reporting>//s;
      $proj =~ s/<modules>.*?<\/modules>//s;
      $parent_gid = trim($parent_gid);
      my $gid = ($proj =~ /<groupId>([^<]+)/s) ? $1 : $parent_gid;
      my $aid = ($proj =~ /<artifactId>([^<]+)/s) ? $1 : "";
      $gid = trim($gid);
      $aid = trim($aid);
      print "$gid:$aid" if $gid ne "" && $aid ne "";
    ' "$pom_file" 2>/dev/null || true)
    if [[ -n "$maven_key" ]]; then
      keys+=("$maven_key")
    fi
  fi

  # 6. build.gradle / build.gradle.kts
  local gradle_file
  for gradle_file in "$work_dir/build.gradle" "$work_dir/build.gradle.kts"; do
    if [[ -f "$gradle_file" ]]; then
      local key
      key=$(perl -ne '
        if (/sonar\.projectKey\s*[=:]\s*["\x27]([^"\x27]+)["\x27]/ ||
            /sonar\.projectKey["\x27]\s*,\s*["\x27]([^"\x27]+)["\x27]/) {
          print "$1\n";
          exit;
        }
      ' "$gradle_file" 2>/dev/null || true)
      if [[ -n "$key" ]]; then
        keys+=("$key")
      fi
    fi
  done

  # 7. Derive from GITHUB_REPOSITORY (e.g. SonarSource/repo-name -> SonarSource_repo-name)
  if [[ "${REPOSITORY_KEY_FALLBACK:-true}" == true && -n "${GITHUB_REPOSITORY:-}" ]]; then
    local derived_key="${GITHUB_REPOSITORY/\//_}"
    keys+=("$derived_key")
  fi

  printf '%s\n' "${keys[@]+"${keys[@]}"}" | normalize_keys
  return 0
}

# Record a diagnostic observation from a probe so a timeout can be explained.
# States, from least to most informative (see state_rank): NOT_FOUND < API_ERROR
# < MEASURE_MISSING. Each probe drops a unique file under "<result_dir>/states";
# main() folds them into the best state seen and tailors the timeout message.
record_state() {
  local result_dir="$1" state="$2"
  local states_dir="${result_dir}/states"
  mkdir -p "$states_dir" 2>/dev/null || return 0
  local state_file
  state_file=$(mktemp "${states_dir}/s.XXXXXX" 2>/dev/null) || return 0
  printf '%s' "$state" > "$state_file"
  return 0
}

# Check if the sca_count_any_issue metric exists for a project on a SonarQube instance.
# Writes "platform_name:project_key" to result_file on success. On failure, records a
# diagnostic state (NOT_FOUND / MEASURE_MISSING / API_ERROR) for timeout reporting.
# Args: url token project_key platform_name result_dir [qualifiers]
#   qualifiers - optional extra query parameters (e.g. "&pullRequest=123")
check_sca_metric() {
  local url="${1:?}" token="${2:?}" project_key="${3:?}" platform_name="${4:?}" result_dir="${5:?}" qualifiers="${6:-}"

  local api_url="${url}/api/measures/component?component=${project_key}&metricKeys=sca_count_any_issue${qualifiers}"

  local response http_code body
  # Network failure / unreachable host: the API never answered.
  response=$(curl -s --max-time 10 -w "\n%{http_code}" \
    -H "Authorization: Bearer ${token}" \
    "${api_url}" 2>/dev/null) || { record_state "$result_dir" "API_ERROR"; return 1; }

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" != "200" ]]; then
    # 404 means the component/branch/PR isn't known to this platform (likely a
    # wrong/absent project key); anything else (401/403/5xx) is an API error.
    if [[ "$http_code" == "404" ]]; then
      record_state "$result_dir" "NOT_FOUND"
    else
      record_state "$result_dir" "API_ERROR"
    fi
    return 1
  fi

  local metric_value
  metric_value=$(echo "$body" | jq -r '
    .component.measures[]?
    | select(.metric == "sca_count_any_issue")
    | .value // empty
  ' 2>/dev/null) || { record_state "$result_dir" "API_ERROR"; return 1; }

  if [[ -n "$metric_value" ]]; then
    local match_file
    match_file=$(mktemp "${result_dir}/match.XXXXXX")
    printf '%s:%s' "$platform_name" "$project_key" > "$match_file"
    # The hard link publishes a complete record once, even with parallel probes.
    if ! { ln "$match_file" "${result_dir}/match" 2>/dev/null || [[ -e "${result_dir}/match" ]]; }; then
      rm -f "$match_file"
      echo "::error::Could not publish the SCA result for $project_key" >&2
      return 2
    fi
    rm -f "$match_file"
    return 0
  fi

  # HTTP 200 but no SCA measure: the project exists and was analyzed, but the SCA
  # portion produced no data (SCA disabled, or analysis still running / failed).
  record_state "$result_dir" "MEASURE_MISSING"
  return 1
}

# Numeric rank for a diagnostic state, so the most informative observation wins.
# A project lives on a single platform, so the other two always answer 404
# (NOT_FOUND); that 404 is routine noise and must rank below a genuine API_ERROR
# (auth/5xx/network) on the hosting platform. NOT_FOUND therefore only wins as the
# final diagnosis when every probe 404s — i.e. the key truly exists nowhere.
state_rank() {
  local state="$1"
  case "$state" in
    MEASURE_MISSING) echo 3 ;; # a platform has the project but no SCA data
    API_ERROR) echo 2 ;;       # could not determine existence (auth/5xx/network)
    NOT_FOUND) echo 1 ;;       # expected 404 from non-hosting platforms
    *) echo 0 ;;               # NONE / unknown
  esac
}

# Return whichever of two states is more informative.
higher_state() {
  local current="$1" candidate="$2"
  if (( $(state_rank "$current") >= $(state_rank "$candidate") )); then
    echo "$current"
  else
    echo "$candidate"
  fi
}

# Emit an actionable error explaining *why* the poll timed out, based on the best
# state observed across all probes. Keeps the "SCA check timeout" annotation title
# so existing alerting/grouping continues to work.
report_timeout() {
  local state="$1" keys_csv="$2"
  local msg detail
  case "$state" in
    MEASURE_MISSING)
      msg="Timed out after ${POLL_TIMEOUT}s — SonarQube project found but no SCA data was published"
      detail="The project exists and was analyzed, but no 'sca_count_any_issue' measure was produced. SCA may be disabled for this project, or the SCA analysis is still running or failed. Check the SonarQube SCA analysis for project key(s): ${keys_csv}."
      ;;
    NOT_FOUND)
      msg="Timed out after ${POLL_TIMEOUT}s — no matching SonarQube project was found"
      detail="None of the discovered project key(s) (${keys_csv}) were found on any platform (next, sqc-us, sqc-eu). Verify the project key — set 'check-sca.project-key' in .github/repo-metadata.yaml — and confirm the project exists and has been analyzed at least once."
      ;;
    API_ERROR)
      msg="Timed out after ${POLL_TIMEOUT}s — the SonarQube API was unreachable or returned errors"
      detail="Every request to the SonarQube measures API failed (network error, authentication failure, or 5xx). Check Vault/token access and SonarQube availability, then re-run."
      ;;
    *)
      msg="Timed out after ${POLL_TIMEOUT}s waiting for SCA data"
      detail="No response was observed from the SonarQube measures API within the timeout. If this repository's SCA analysis is legitimately slow, raise the 'poll-timeout' input; otherwise verify the project key(s) (${keys_csv}) and that SCA is enabled."
      ;;
  esac
  echo "::error title=SCA check timeout::${msg}" >&2
  echo "Diagnosis: project key(s) ${keys_csv}. ${detail}"
}

# Publish compact JSON so project names cannot inject extra action outputs.
write_results() {
  local result_dir="$1" verified="$2"
  shift 2
  local project_keys=("$@") index match platform project_key
  local results='[]' unresolved='[]' diagnoses='[]'
  local state
  for index in "${!project_keys[@]}"; do
    project_key="${project_keys[index]}"
    if [[ -f "$result_dir/$index/match" ]]; then
      match=$(cat "$result_dir/$index/match")
      platform="${match%%:*}"
      results=$(jq -c --arg key "$project_key" --arg platform "$platform" '. + [{"project-key": $key, platform: $platform}]' <<< "$results")
    elif [[ "$PROJECT_KEY_MODE" != any || "$verified" != true ]]; then
      unresolved=$(jq -c --arg key "$project_key" '. + [$key]' <<< "$unresolved")
      state=NONE
      if [[ -f "$result_dir/$index/best-state" ]]; then
        state=$(cat "$result_dir/$index/best-state")
      fi
      diagnoses=$(jq -c --arg key "$project_key" --arg state "$state" '. + [{"project-key": $key, diagnosis: $state}]' <<< "$diagnoses")
    fi
  done
  {
    echo "verified-projects=$results"
    echo "unresolved-projects=$unresolved"
    echo "project-diagnoses=$diagnoses"
  } >> "$GITHUB_OUTPUT"
}

# Retain each PID for final status checks, including jobs reaped by wait -n.
wait_for_probe_slot() {
  local running
  while true; do
    mapfile -t running < <(jobs -pr)
    [[ ${#running[@]} -lt $MAX_CONCURRENT_PROBES ]] && return 0
    wait -n || true
  done
}

main() {
  echo "sca-verified=false" >> "$GITHUB_OUTPUT"
  resolve_configuration || exit 1
  echo "::group::Discover project keys"
  local project_keys=() discovered_keys
  discovered_keys=$(discover_project_keys) || exit 1
  while IFS= read -r line; do
    [[ -n "$line" ]] && project_keys+=("$line")
  done <<< "$discovered_keys"

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
  local index
  local best_states=()
  for index in "${!project_keys[@]}"; do
    mkdir -p "$result_dir/$index"
    best_states[index]=NONE
  done

  while true; do
    attempt=$((attempt + 1))
    local elapsed=$(( $(date +%s) - start_time ))

    if [[ $elapsed -ge $POLL_TIMEOUT ]]; then
      if [[ "$PROJECT_KEY_MODE" == any ]]; then
        local best_state=NONE keys_csv
        for index in "${!project_keys[@]}"; do
          best_state=$(higher_state "$best_state" "${best_states[index]}")
        done
        keys_csv=$(IFS=,; echo "${project_keys[*]}")
        report_timeout "$best_state" "$keys_csv"
      else
        for index in "${!project_keys[@]}"; do
          [[ -f "$result_dir/$index/match" ]] && continue
          echo "Unresolved project: ${project_keys[index]}"
          report_timeout "${best_states[index]}" "${project_keys[index]}"
        done
      fi
      write_results "$result_dir" false "${project_keys[@]}"
      echo "$ENDGROUP"
      echo "sca-verified=false" >> "$GITHUB_OUTPUT"
      rm -rf "$result_dir"
      exit 1
    fi

    echo "--- Poll attempt $attempt (${elapsed}s / ${POLL_TIMEOUT}s) ---"

    # Keep completed keys between rounds and isolate diagnostics by numeric index.
    local pids=()
    for index in "${!project_keys[@]}"; do
      key="${project_keys[index]}"
      [[ -f "$result_dir/$index/match" ]] && continue
      for platform_def in "${PLATFORMS[@]}"; do
        IFS=':' read -r platform_name url_var token_var <<< "$platform_def"
        local url="${!url_var}" token="${!token_var}"

        # Check SQ project's primary branch (no qualifier = SQ default, may differ from main/master)
        echo "  Checking $platform_name / $key ..."
        wait_for_probe_slot
        check_sca_metric "$url" "$token" "$key" "$platform_name" "$result_dir/$index" &
        pids+=($!)

        # Also check well-known branch names explicitly
        for branch_name in main master; do
          echo "  Checking $platform_name / $key (branch: $branch_name) ..."
          wait_for_probe_slot
          check_sca_metric "$url" "$token" "$key" "$platform_name" "$result_dir/$index" "&branch=${branch_name}" &
          pids+=($!)
        done

        # Check PR-specific analysis when running on a pull request
        if [[ -n "${PULL_REQUEST:-}" ]]; then
          echo "  Checking $platform_name / $key (PR #${PULL_REQUEST}) ..."
          wait_for_probe_slot
          check_sca_metric "$url" "$token" "$key" "$platform_name" "$result_dir/$index" "&pullRequest=${PULL_REQUEST}" &
          pids+=($!)
        fi
      done
    done

    # Wait for all background jobs to finish
    for pid in "${pids[@]}"; do
      local probe_status=0
      wait "$pid" || probe_status=$?
      if [[ $probe_status -eq 2 ]]; then
        echo "::error::SCA result publication failed" >&2
        # Finish the remaining probes before removing their result directory.
        wait || true
        rm -rf "$result_dir"
        exit 1
      fi
    done

    local verified_count=0 found_platform="" found_key="" match
    for index in "${!project_keys[@]}"; do
      if [[ -f "$result_dir/$index/match" ]]; then
        verified_count=$((verified_count + 1))
        match=$(cat "$result_dir/$index/match")
        found_platform="${match%%:*}"
        found_key="${match#*:}"
        echo "  SCA verified on $found_platform for project key: $found_key"
      else
        local state_file observed
        for state_file in "$result_dir/$index/states"/*; do
          [[ -e "$state_file" ]] || continue
          observed=$(cat "$state_file")
          best_states[index]=$(higher_state "${best_states[index]}" "$observed")
        done
        printf '%s' "${best_states[index]}" > "$result_dir/$index/best-state"
        rm -rf "$result_dir/$index/states"
      fi
    done
    if [[ ( "$PROJECT_KEY_MODE" == any && $verified_count -gt 0 ) || $verified_count -eq ${#project_keys[@]} ]]; then
      echo "$ENDGROUP"
      write_results "$result_dir" true "${project_keys[@]}"
      {
        echo "sca-verified=true"
        if [[ "$PROJECT_KEY_MODE" == any ]]; then
          echo "platform=$found_platform"
          echo "project-key=$found_key"
        fi
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
