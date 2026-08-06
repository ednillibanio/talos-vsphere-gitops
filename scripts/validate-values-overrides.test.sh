#!/usr/bin/env bash
set -euo pipefail

# validate-values-overrides.test.sh
#
# Regression check for validate-values-overrides.sh: confirms it passes a
# minimal owned-override fixture and fails fixtures that carry a chart
# vendoring marker, keep a leftover values.base.yaml, or have no values file
# at all. Also confirms an empty helm root is an error rather than a silent
# pass, which would otherwise let the check "succeed" while validating
# nothing.
#
# Every fixture omits release.yaml (except the missing-values one, whose
# release file is what proves the missing values file is detected), so no
# case here reaches the network. The real repository render is exercised by
# running the validator directly.
#
# Usage: validate-values-overrides.test.sh

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="$dir/validate-values-overrides.sh"
fixtures="$dir/testdata/values-overrides"
status=0

echo "test: valid fixture should pass"
if out="$("$validator" "$fixtures/valid" 2>&1)"; then
  echo "  ok"
else
  echo "  FAIL: expected valid fixture to pass"
  echo "$out"
  status=1
fi

echo "test: vendored-marker fixture should fail"
if out="$("$validator" "$fixtures/vendored-marker" 2>&1)"; then
  echo "  FAIL: expected vendored-marker fixture to fail"
  echo "$out"
  status=1
else
  if grep -q 'carries a chart vendoring marker' <<<"$out"; then
    echo "  ok (marker detected)"
  else
    echo "  FAIL: expected a vendoring-marker message"
    echo "$out"
    status=1
  fi
fi

echo "test: leftover-base fixture should fail"
if out="$("$validator" "$fixtures/leftover-base" 2>&1)"; then
  echo "  FAIL: expected leftover-base fixture to fail"
  echo "$out"
  status=1
else
  if grep -q 'unreferenced vendored defaults still present' <<<"$out"; then
    echo "  ok (leftover values.base.yaml detected)"
  else
    echo "  FAIL: expected a leftover-defaults message"
    echo "$out"
    status=1
  fi
fi

echo "test: missing values file should fail"
if out="$("$validator" "$fixtures/missing-values" 2>&1)"; then
  echo "  FAIL: expected missing values file to fail"
  echo "$out"
  status=1
else
  if grep -q 'values file not found' <<<"$out"; then
    echo "  ok (missing values file detected)"
  else
    echo "  FAIL: expected a missing-values message"
    echo "$out"
    status=1
  fi
fi

echo "test: empty helm root should error, not silently pass"
empty_root="$(mktemp -d)"
trap 'rm -rf "$empty_root"' EXIT
if out="$("$validator" "$empty_root" 2>&1)"; then
  echo "  FAIL: expected an empty helm root to error rather than pass"
  echo "$out"
  status=1
else
  if grep -q 'no addon directories found' <<<"$out"; then
    echo "  ok (empty root rejected)"
  else
    echo "  FAIL: expected a no-addons message"
    echo "$out"
    status=1
  fi
fi

echo "test: nonexistent helm root should error"
if out="$("$validator" "$dir/testdata/definitely-not-here" 2>&1)"; then
  echo "  FAIL: expected a nonexistent helm root to error"
  echo "$out"
  status=1
else
  echo "  ok (nonexistent root rejected)"
fi

exit "$status"
