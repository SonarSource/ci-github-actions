#!/usr/bin/env bash
# pipefail is deliberately omitted: extraction pipelines (e.g. grep|tail|sed) can
# legitimately have no matches, and pipefail would trip the ERR trap below.
set -u
trap 'echo "::warning::report-ci-metrics failed (fail-open)"; exit 0' ERR
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=SCRIPTDIR/lib.sh
. "$here/lib.sh"
main "$@"
exit 0
