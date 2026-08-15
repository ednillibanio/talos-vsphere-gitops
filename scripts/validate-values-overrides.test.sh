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
# Also confirms that a pinned chart which cannot be resolved fails the run
# rather than printing a note and exiting zero, which previously let a green
# run silently skip an addon. Codex round-1 review (IR-01) found two more
# fail-open paths in that same render pass — a missing `helm` binary and a
# missing release.yaml both used to print a "note" and exit 0, which meant a
# green run did not actually prove every addon rendered. Both are covered
# below as explicit regression cases, and the "valid fixture" happy path now
# goes through a real (faked) render instead of skipping it via a missing
# release.yaml, so it protects the documented gate contract rather than the
# fail-open behavior.
#
# Fixtures omit release.yaml except for: valid, which pins a fake chart
# rendered by fake-bin/helm-render-succeeds; missing-values, whose release
# file is what proves the missing values file is detected; unresolvable-chart,
# which pins an alias that is never registered so helm rejects it locally; and
# no-release, which deliberately omits release.yaml to exercise the
# missing-release-file failure. None of these reach the network. The real
# repository render is exercised by running the validator directly.
#
# Usage: validate-values-overrides.test.sh

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="$dir/validate-values-overrides.sh"
fixtures="$dir/testdata/values-overrides"
succeeding_helm_path="$fixtures/fake-bin/helm-render-succeeds:$PATH"
status=0

echo "test: valid fixture should pass (chart resolves and renders)"
if out="$(PATH="$succeeding_helm_path" "$validator" "$fixtures/valid" 2>&1)"; then
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

echo "test: unresolvable pinned chart should fail, not pass with a note"
if command -v helm >/dev/null 2>&1; then
  if out="$("$validator" "$fixtures/unresolvable-chart" 2>&1)"; then
    echo "  FAIL: expected an unresolvable pinned chart to fail the run"
    echo "$out"
    status=1
  else
    if grep -q 'could not resolve pinned chart' <<<"$out"; then
      echo "  ok (unresolvable chart rejected)"
    else
      echo "  FAIL: expected a chart-resolution failure message"
      echo "$out"
      status=1
    fi
  fi
else
  echo "  skipped (helm not installed)"
fi

echo "test: nonexistent helm root should error"
if out="$("$validator" "$dir/testdata/definitely-not-here" 2>&1)"; then
  echo "  FAIL: expected a nonexistent helm root to error"
  echo "$out"
  status=1
else
  echo "  ok (nonexistent root rejected)"
fi

echo "test: missing release.yaml should fail validation, not skip with a note (IR-01)"
if out="$(PATH="$succeeding_helm_path" "$validator" "$fixtures/no-release" 2>&1)"; then
  echo "  FAIL: expected a missing release.yaml to fail validation"
  echo "$out"
  status=1
else
  if grep -q 'release file not found' <<<"$out"; then
    echo "  ok (missing release file detected)"
  else
    echo "  FAIL: expected a missing-release-file failure message"
    echo "$out"
    status=1
  fi
fi

echo "test: missing helm binary should fail validation, not skip with a note (IR-01)"
no_helm_path="$(printf '%s' "$PATH" | tr ':' '\n' | while IFS= read -r p; do
  [[ -x "$p/helm" ]] && continue
  printf '%s:' "$p"
done)"
if out="$(PATH="$no_helm_path" "$validator" "$fixtures/valid" 2>&1)"; then
  echo "  FAIL: expected a missing helm binary to fail validation"
  echo "$out"
  status=1
else
  if grep -q 'helm not installed' <<<"$out"; then
    echo "  ok (missing helm binary detected)"
  else
    echo "  FAIL: expected a missing-helm failure message"
    echo "$out"
    status=1
  fi
fi

echo "test: default (no-arg) invocation discovers every tracked environments/*/helm root and fails on an invalid target root"
# Build a throwaway git repo with a valid "base" root and an invalid "target"
# root, then run the validator (copied into that repo) with no argument. The
# default gate must discover both roots via `git ls-files` and fail because
# of the target root, proving a new environment is not silently skipped.
discovery_repo="$(mktemp -d)"
cleanup_discovery_repo() { rm -rf "$discovery_repo"; }
trap cleanup_discovery_repo EXIT

(
  cd "$discovery_repo"
  git init -q
  mkdir -p environments/base/helm/addon-a environments/target/helm/addon-b scripts
  cp -R "$fixtures/valid/addon-a/." environments/base/helm/addon-a/
  # No values.yaml here: the same "missing values file" defect AUD-02 requires
  # the default gate to catch on a target-specific root, not only on lab/helm.
  cp "$fixtures/missing-values/addon-a/release.yaml" environments/target/helm/addon-b/
  cp "$validator" scripts/validate-values-overrides.sh
  git add -A
)

if out="$(cd "$discovery_repo" && PATH="$succeeding_helm_path" ./scripts/validate-values-overrides.sh 2>&1)"; then
  echo "  FAIL: expected the default invocation to fail because of the target root"
  echo "$out"
  status=1
else
  if grep -q 'environments/target/helm/addon-b: values file not found' <<<"$out" &&
    grep -q 'environments/base/helm' <<<"$out"; then
    echo "  ok (default gate discovered both roots and failed on the target)"
  else
    echo "  FAIL: expected both roots to be discovered and the target failure reported"
    echo "$out"
    status=1
  fi
fi

cleanup_discovery_repo
trap - EXIT

exit "$status"
