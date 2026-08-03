#!/usr/bin/env bash
set -euo pipefail

# validate-cilium-values-overrides.test.sh
#
# Regression check for validate-cilium-values-overrides.sh: confirms it
# passes a minimal owned-override fixture and fails a fixture that still
# carries the chart's vendoring marker, one missing a documented override
# key, and one with a leftover values.base.yaml. Also exercises the real
# environments/lab/helm/cilium/values.yaml, which additionally triggers the
# pinned-chart Helm render when helm can resolve it. Two further cases use a
# fake `helm` on PATH to deterministically exercise the resolved-chart vs.
# render-failure distinction without depending on real network access:
# a chart-pull failure must be reported as a limitation (exit 0), while a
# resolved chart that fails to render must fail validation (exit 1).
#
# Usage: validate-cilium-values-overrides.test.sh

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="$dir/validate-cilium-values-overrides.sh"
missing_release="$dir/testdata/cilium-values/no-release-here.yaml"
status=0

echo "test: valid fixture should pass"
if out="$("$validator" "$dir/testdata/cilium-values/valid/values.yaml" "$missing_release" 2>&1)"; then
  echo "  ok"
else
  echo "  FAIL: expected valid fixture to pass"
  echo "$out"
  status=1
fi

echo "test: vendored-marker fixture should fail"
if out="$("$validator" "$dir/testdata/cilium-values/vendored-marker/values.yaml" "$missing_release" 2>&1)"; then
  echo "  FAIL: expected vendored-marker fixture to fail"
  echo "$out"
  status=1
else
  echo "  ok (marker detected)"
fi

echo "test: missing-key fixture should fail"
if out="$("$validator" "$dir/testdata/cilium-values/missing-key/values.yaml" "$missing_release" 2>&1)"; then
  echo "  FAIL: expected missing-key fixture to fail"
  echo "$out"
  status=1
else
  echo "  ok (missing key detected)"
fi

echo "test: leftover-base fixture should fail"
if out="$("$validator" "$dir/testdata/cilium-values/leftover-base/values.yaml" "$missing_release" 2>&1)"; then
  echo "  FAIL: expected leftover-base fixture to fail"
  echo "$out"
  status=1
else
  echo "  ok (leftover values.base.yaml detected)"
fi

echo "test: real lab values file should pass (and render if helm resolves the pinned chart)"
repo_root="$(cd "$dir/.." && pwd)"
if out="$("$validator" \
  "$repo_root/environments/lab/helm/cilium/values.yaml" \
  "$repo_root/environments/lab/helm/cilium/release.yaml" 2>&1)"; then
  echo "  ok"
  while IFS= read -r line; do echo "    $line"; done <<<"$out"
else
  echo "  FAIL: expected real lab values file to pass"
  echo "$out"
  status=1
fi

fake_release="$dir/testdata/cilium-values/fake-release.yaml"
valid_values="$dir/testdata/cilium-values/valid/values.yaml"

echo "test: chart-pull failure should be reported as a limitation, not a failure"
if out="$(PATH="$dir/testdata/cilium-values/fake-bin/helm-pull-fails:$PATH" \
  "$validator" "$valid_values" "$fake_release" 2>&1)"; then
  if grep -q 'note: pinned Cilium chart was not locally resolvable' <<<"$out"; then
    echo "  ok (unresolvable chart reported as limitation)"
  else
    echo "  FAIL: expected an unresolvable-chart limitation note"
    echo "$out"
    status=1
  fi
else
  echo "  FAIL: expected chart-pull failure to exit 0 (limitation, not a validation failure)"
  echo "$out"
  status=1
fi

echo "test: resolved chart that fails to render should fail validation"
if out="$(PATH="$dir/testdata/cilium-values/fake-bin/helm-render-fails:$PATH" \
  "$validator" "$valid_values" "$fake_release" 2>&1)"; then
  echo "  FAIL: expected a render failure on a resolved chart to fail validation"
  echo "$out"
  status=1
else
  if grep -q 'FAIL: resolved chart .* could not render' <<<"$out"; then
    echo "  ok (render failure on resolved chart detected)"
  else
    echo "  FAIL: expected a resolved-chart render-failure message"
    echo "$out"
    status=1
  fi
fi

exit "$status"
