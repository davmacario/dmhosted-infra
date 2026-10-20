#!/usr/bin/env bash
# Fail if any staged YAML file contains a plain Kubernetes Secret with data.
# SealedSecrets are fine; Secrets without data (e.g. service-account tokens) are fine.
set -euo pipefail

status=0
for file in "$@"; do
  if ! awk '
    function check() {
      if (is_secret && has_data) { found = 1 }
      is_secret = 0; has_data = 0
    }
    /^---/ { check(); next }
    /^kind:[[:space:]]*Secret[[:space:]]*$/ { is_secret = 1 }
    /^(data|stringData):/ { has_data = 1 }
    END { check(); exit found }
  ' "$file"; then
    echo "Plain Secret with data found in $file (use a SealedSecret instead)"
    status=1
  fi
done
exit $status
