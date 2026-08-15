#!/usr/bin/env bash
set -euo pipefail

# validate-argocd-revisions.test.sh
#
# Regression check for validate-argocd-revisions.sh: confirms it passes on a
# fixture with consistent lab revisions and fails on a fixture with a mixed
# (main) revision inside the lab environment.
#
# Usage: validate-argocd-revisions.test.sh

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="$dir/validate-argocd-revisions.sh"
status=0

echo "test: valid fixture should pass"
if out="$("$validator" "$dir/testdata/valid/environments" 2>&1)"; then
  echo "  ok"
else
  echo "  FAIL: expected valid fixture to pass"
  echo "$out"
  status=1
fi

echo "test: target-suffixed environment should resolve to its stage branch"
if out="$("$validator" "$dir/testdata/targets/environments" 2>&1)"; then
  echo "  ok (environments/lab-container accepts targetRevision: lab)"
else
  echo "  FAIL: expected lab-container to pin the lab branch, not a lab-container branch"
  echo "$out"
  status=1
fi

echo "test: mixed fixture should fail"
if out="$("$validator" "$dir/testdata/mixed/environments" 2>&1)"; then
  echo "  FAIL: expected mixed fixture to fail"
  echo "$out"
  status=1
else
  echo "  ok (mismatch detected)"
fi

exit "$status"
