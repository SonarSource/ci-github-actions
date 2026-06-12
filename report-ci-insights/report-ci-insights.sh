#!/usr/bin/env bash
set -u
trap 'echo "::warning::report-ci-insights failed (fail-open)"; exit 0' ERR
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=SCRIPTDIR/lib.sh
. "$here/lib.sh"
main "$@"
exit 0
