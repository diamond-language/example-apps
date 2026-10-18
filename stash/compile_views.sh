#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
DIAMOND_BIN="${DIAMOND_BIN:-diamond}" cuts/div/bin/divc_all.sh views
