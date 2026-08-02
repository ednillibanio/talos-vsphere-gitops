#!/usr/bin/env bash
set -euo pipefail

# validate-cilium-adoption-readiness.test.sh
#
# Regression check for validate-cilium-adoption-readiness.sh: confirms it
# passes on a fixture with a complete, fully-automated Cilium adoption
# contract, and fails on fixtures missing the referenced values file, with a
# non-automated sync policy, and with a mismatched environment revision.
#
# Usage: validate-cilium-adoption-readiness.test.sh

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="$dir/validate-cilium-adoption-readiness.sh"
status=0

assert_pass() {
  local name="$1" fixture="$2"
  echo "test: $name should pass"
  if out="$("$validator" "$dir/testdata/cilium-readiness/$fixture/environments" 2>&1)"; then
    echo "  ok"
  else
    echo "  FAIL: expected $fixture fixture to pass"
    echo "$out"
    status=1
  fi
}

assert_fail() {
  local name="$1" fixture="$2" expected_substring="$3"
  echo "test: $name should fail"
  if out="$("$validator" "$dir/testdata/cilium-readiness/$fixture/environments" 2>&1)"; then
    echo "  FAIL: expected $fixture fixture to fail"
    echo "$out"
    status=1
  elif [[ "$out" == *"$expected_substring"* ]]; then
    echo "  ok (expected diagnostic present)"
  else
    echo "  FAIL: failed but diagnostic did not match '$expected_substring'"
    echo "$out"
    status=1
  fi
}

assert_pass "valid fixture" "valid"
assert_fail "missing values file fixture" "missing-values-file" "referenced values file not found"
assert_fail "non-automated sync policy fixture" "not-automated" "adoption sync policy not fully automated"
assert_fail "mismatched environment revision fixture" "wrong-revision" "expected lab"

exit "$status"
