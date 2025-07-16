#!/bin/bash
# Reusable script to detect GitHub repository visibility
# Returns: public, private, or internal
#
# Usage: ./detect-repo-visibility.sh
#
# Environment variables:
# - GITHUB_TOKEN: GitHub token for API access
# - GITHUB_REPOSITORY: Repository name (e.g., owner/repo)
# - GITHUB_OUTPUT: Path to GitHub Actions output file (optional)

set -euo pipefail

detect_repo_visibility() {
  local repo_visibility="${GITHUB_EVENT_REPOSITORY_VISIBILITY:-}"

  # Try to get visibility from GitHub event context first
  if [[ -n "${repo_visibility}" && "${repo_visibility}" != "null" ]]; then
    echo "Repository visibility from event: $repo_visibility" >&2
  else
    # Fall back to GitHub API
    echo "Fetching repository visibility from GitHub API..." >&2
    repo_visibility=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
      "https://api.github.com/repos/${GITHUB_REPOSITORY}" | \
      jq -r '.visibility // "private"')
  fi

  echo "Repository visibility: $repo_visibility" >&2

  # Set GitHub output if GITHUB_OUTPUT is available
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "repo-visibility=$repo_visibility" >> "$GITHUB_OUTPUT"
  fi

  # Return the visibility
  echo "$repo_visibility"
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  : "${GITHUB_TOKEN:?Required environment variable not set}"
  : "${GITHUB_REPOSITORY:?Required environment variable not set}"

  detect_repo_visibility
fi
