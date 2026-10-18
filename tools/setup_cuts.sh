#!/usr/bin/env bash
# Install the local Diamond cuts, then keep only the ones Stash loads.
set -euo pipefail
cd "$(dirname "$0")/.."
../diamond/tools/install_local_cuts.sh . >/dev/null
for d in cuts/*; do
    case "${d##*/}" in arel|cookies|div|gremlin|http|logger|mjolnir|network_safety) ;; *) rm -rf "$d" ;; esac
done
ls cuts
