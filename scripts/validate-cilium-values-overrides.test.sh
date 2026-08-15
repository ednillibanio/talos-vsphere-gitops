#!/usr/bin/env bash
set -euo pipefail

# validate-cilium-values-overrides.test.sh
#
# Regression check for validate-cilium-values-overrides.sh: confirms it
# passes a minimal owned-override fixture and fails a fixture that still
# carries the chart's vendoring marker, one missing a documented override
# key, and one with a leftover values.base.yaml. Also exercises the real
# environments/lab/helm/cilium/values.yaml, which additionally triggers the
# pinned-chart Helm render.
#
# The render step is a mandatory, fail-closed gate (AUD-03): missing release
# metadata, an unparseable chart/version, a missing `helm` binary, a
# chart-pull failure, and a missing pull archive must all fail validation
# rather than degrade to a "note" and exit 0. Several cases use a fake `helm`
# on PATH, or a PATH stripped of the real `helm`, to exercise each of those
# failure modes deterministically without depending on real network access.
#
# Usage: validate-cilium-values-overrides.test.sh

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="$dir/validate-cilium-values-overrides.sh"
missing_release="$dir/testdata/cilium-values/no-release-here.yaml"
succeeding_helm_path="$dir/testdata/cilium-values/fake-bin/helm-render-succeeds:$PATH"
status=0

echo "test: valid fixture should pass (chart resolves and renders)"
if out="$(PATH="$succeeding_helm_path" \
  "$validator" "$dir/testdata/cilium-values/valid/values.yaml" \
  "$dir/testdata/cilium-values/fake-release.yaml" 2>&1)"; then
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

echo "test: real lab values file should pass and render against the pinned chart"
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

echo "test: chart-pull failure must fail validation, not degrade to a note"
if out="$(PATH="$dir/testdata/cilium-values/fake-bin/helm-pull-fails:$PATH" \
  "$validator" "$valid_values" "$fake_release" 2>&1)"; then
  echo "  FAIL: expected chart-pull failure to fail validation (exit non-zero)"
  echo "$out"
  status=1
else
  if grep -q 'FAIL: could not resolve pinned chart' <<<"$out"; then
    echo "  ok (unresolvable chart fails the run)"
  else
    echo "  FAIL: expected a chart-resolution failure message"
    echo "$out"
    status=1
  fi
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

echo "test: missing chart archive after a successful pull should fail validation"
if out="$(PATH="$dir/testdata/cilium-values/fake-bin/helm-pull-no-archive:$PATH" \
  "$validator" "$valid_values" "$fake_release" 2>&1)"; then
  echo "  FAIL: expected a missing pull archive to fail validation"
  echo "$out"
  status=1
else
  if grep -q 'FAIL: helm pull produced no archive' <<<"$out"; then
    echo "  ok (missing archive detected)"
  else
    echo "  FAIL: expected a missing-archive failure message"
    echo "$out"
    status=1
  fi
fi

echo "test: missing release file should fail validation, not skip with a note"
if out="$("$validator" "$valid_values" "$missing_release" 2>&1)"; then
  echo "  FAIL: expected a missing release file to fail validation"
  echo "$out"
  status=1
else
  if grep -q 'FAIL: release file not found' <<<"$out"; then
    echo "  ok (missing release file detected)"
  else
    echo "  FAIL: expected a missing-release-file failure message"
    echo "$out"
    status=1
  fi
fi

echo "test: release file with no parseable chart/version should fail validation"
if out="$("$validator" "$valid_values" "$dir/testdata/cilium-values/malformed-release.yaml" 2>&1)"; then
  echo "  FAIL: expected an unparseable release file to fail validation"
  echo "$out"
  status=1
else
  if grep -q 'FAIL: could not parse chart/version' <<<"$out"; then
    echo "  ok (unparseable release metadata detected)"
  else
    echo "  FAIL: expected a chart/version parse-failure message"
    echo "$out"
    status=1
  fi
fi

echo "test: missing helm binary should fail validation, not skip with a note"
no_helm_path="$(printf '%s' "$PATH" | tr ':' '\n' | while IFS= read -r p; do
  [[ -x "$p/helm" ]] && continue
  printf '%s:' "$p"
done)"
if out="$(PATH="$no_helm_path" "$validator" "$valid_values" "$fake_release" 2>&1)"; then
  echo "  FAIL: expected a missing helm binary to fail validation"
  echo "$out"
  status=1
else
  if grep -q 'FAIL: helm not installed' <<<"$out"; then
    echo "  ok (missing helm binary detected)"
  else
    echo "  FAIL: expected a missing-helm failure message"
    echo "$out"
    status=1
  fi
fi

exit "$status"
