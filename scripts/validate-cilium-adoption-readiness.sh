#!/usr/bin/env bash
set -euo pipefail

# validate-cilium-adoption-readiness.sh
#
# Offline check that each environment's addon-cilium Argo CD Application
# declares a self-consistent, fully-automated adoption contract: required
# Helm release identity fields are present, the referenced values file
# exists in this repository, the environment revision on the values-ref
# source matches the environment directory (same lab/main contract as
# validate-argocd-revisions.sh), and the sync policy is fully automated
# (prune + selfHeal), so Argo CD actually takes over reconciliation of the
# already-running day-1 Cilium release instead of leaving it half-adopted.
# Contacts no live Argo CD, Kubernetes, or Helm endpoint.
#
# Usage: validate-cilium-adoption-readiness.sh [environments-dir]
#
# Actions:
#   (default) Scan <environments-dir>/*/argocd/apps/cilium.yaml (default: environments)
#
# Options:
#   -h, --help   Show this help and exit
#
# Examples:
#   ./scripts/validate-cilium-adoption-readiness.sh
#   ./scripts/validate-cilium-adoption-readiness.sh scripts/testdata/cilium-readiness/valid/environments

usage() {
  sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

root="${1:-environments}"

if [[ ! -d "$root" ]]; then
  echo "error: environments directory not found: $root" >&2
  exit 2
fi

self_repo_pattern='talos-vsphere-gitops(\.git)?$'
repo_root="$(cd "$root/.." && pwd)"
fail=0
checked=0

parse_cilium_app() {
  local app_file="$1"
  awk '
    function emit(key, val) { printf "%s=%s\n", key, val }
    /^[[:space:]]*sources:[[:space:]]*$/ { in_sources=1; next }
    /^[[:space:]]*destination:[[:space:]]*$/ { in_sources=0; in_dest=1; next }
    /^[[:space:]]*syncPolicy:[[:space:]]*$/ { in_dest=0; in_sync=1; next }
    in_sources && /^[[:space:]]*-[[:space:]]*repoURL:/ {
      idx++
      line=$0; sub(/^[[:space:]]*-[[:space:]]*repoURL:[[:space:]]*/, "", line); repo[idx]=line
      cur=idx
      next
    }
    in_sources && /^[[:space:]]*chart:/ { line=$0; sub(/^[[:space:]]*chart:[[:space:]]*/, "", line); chart[cur]=line; next }
    in_sources && /^[[:space:]]*targetRevision:/ { line=$0; sub(/^[[:space:]]*targetRevision:[[:space:]]*/, "", line); rev[cur]=line; next }
    in_sources && /^[[:space:]]*releaseName:/ { line=$0; sub(/^[[:space:]]*releaseName:[[:space:]]*/, "", line); relname[cur]=line; next }
    in_sources && /^[[:space:]]*-[[:space:]]*\$values\// {
      line=$0; sub(/^[[:space:]]*-[[:space:]]*\$values\//, "", line); valuesfile[cur]=line; next
    }
    in_dest && /^[[:space:]]*namespace:/ { line=$0; sub(/^[[:space:]]*namespace:[[:space:]]*/, "", line); namespace=line; next }
    in_sync && /^[[:space:]]*prune:/ { line=$0; sub(/^[[:space:]]*prune:[[:space:]]*/, "", line); prune=line; next }
    in_sync && /^[[:space:]]*selfHeal:/ { line=$0; sub(/^[[:space:]]*selfHeal:[[:space:]]*/, "", line); selfheal=line; next }
    END {
      emit("CHART_REPO", repo[1])
      emit("CHART_NAME", chart[1])
      emit("CHART_VERSION", rev[1])
      emit("RELEASE_NAME", relname[1])
      emit("VALUES_FILE", valuesfile[1])
      emit("VALUES_REPO_URL", repo[2])
      emit("VALUES_REPO_REV", rev[2])
      emit("NAMESPACE", namespace)
      emit("SYNC_PRUNE", prune)
      emit("SYNC_SELFHEAL", selfheal)
    }
  ' "$app_file"
}

for env_dir in "$root"/*/; do
  [[ -d "$env_dir" ]] || continue
  env_name="$(basename "$env_dir")"
  app_file="${env_dir}argocd/apps/cilium.yaml"
  [[ -f "$app_file" ]] || continue
  checked=$((checked + 1))

  # shellcheck disable=SC2153,SC2154
  eval "$(parse_cilium_app "$app_file")"

  if [[ -z "$CHART_REPO" || -z "$CHART_NAME" || -z "$CHART_VERSION" ]]; then
    echo "readiness: $app_file -> missing chart repoURL/chart/targetRevision" >&2
    fail=1
  fi
  if [[ -z "$RELEASE_NAME" ]]; then
    echo "readiness: $app_file -> missing helm.releaseName" >&2
    fail=1
  fi
  if [[ -z "$NAMESPACE" ]]; then
    echo "readiness: $app_file -> missing destination.namespace" >&2
    fail=1
  fi
  if [[ -z "$VALUES_FILE" ]]; then
    echo "readiness: $app_file -> missing \$values valueFiles reference" >&2
    fail=1
  elif [[ ! -f "${repo_root}/${VALUES_FILE}" ]]; then
    echo "readiness: $app_file -> referenced values file not found: ${VALUES_FILE}" >&2
    fail=1
  fi

  if [[ -z "$VALUES_REPO_URL" || -z "$VALUES_REPO_REV" ]]; then
    echo "readiness: $app_file -> missing self-repo values-ref source" >&2
    fail=1
  elif [[ "$VALUES_REPO_URL" =~ $self_repo_pattern ]]; then
    if [[ "$VALUES_REPO_REV" != "$env_name" ]]; then
      echo "readiness: $app_file -> values-ref targetRevision=$VALUES_REPO_REV (expected $env_name)" >&2
      fail=1
    fi
  else
    echo "readiness: $app_file -> values-ref repoURL '$VALUES_REPO_URL' does not match expected GitOps repo pattern" >&2
    fail=1
  fi

  if [[ "$SYNC_PRUNE" != "true" || "$SYNC_SELFHEAL" != "true" ]]; then
    echo "readiness: $app_file -> adoption sync policy not fully automated (prune=$SYNC_PRUNE selfHeal=$SYNC_SELFHEAL)" >&2
    fail=1
  fi
done

if [[ "$checked" -eq 0 ]]; then
  echo "error: no environments/*/argocd/apps/cilium.yaml found under $root" >&2
  exit 2
fi

if [[ "$fail" -ne 0 ]]; then
  echo "FAIL: Cilium adoption readiness violations detected" >&2
  exit 1
fi

echo "OK: all Cilium Applications are adoption-ready ($checked environment(s) checked)"
