#!/usr/bin/env bash
set -euo pipefail

# validate-argocd-revisions.sh
#
# Offline check that every Argo CD Application source pointing at this
# GitOps repository resolves the same Git revision as the environment
# directory it lives under (environments/lab -> lab, environments/main ->
# main). Detects mixed lab/main revisions without contacting a live Argo CD
# or Kubernetes cluster.
#
# Usage: validate-argocd-revisions.sh [environments-dir]
#
# Actions:
#   (default) Scan <environments-dir>/*/argocd/**/*.yaml (default: environments)
#
# Options:
#   -h, --help   Show this help and exit
#
# Examples:
#   ./scripts/validate-argocd-revisions.sh
#   ./scripts/validate-argocd-revisions.sh scripts/testdata/mixed/environments

usage() {
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
fail=0

for env_dir in "$root"/*/; do
  [[ -d "$env_dir" ]] || continue
  env_name="$(basename "$env_dir")"
  argocd_dir="${env_dir}argocd"
  [[ -d "$argocd_dir" ]] || continue

  while IFS= read -r -d '' file; do
    repo=""
    while IFS= read -r line; do
      if [[ "$line" =~ repoURL:[[:space:]]*(.+)[[:space:]]*$ ]]; then
        repo="${BASH_REMATCH[1]}"
        continue
      fi
      if [[ "$line" =~ targetRevision:[[:space:]]*(.+)[[:space:]]*$ ]]; then
        rev="${BASH_REMATCH[1]}"
        if [[ -n "$repo" && "$repo" =~ $self_repo_pattern ]]; then
          if [[ "$rev" != "$env_name" ]]; then
            echo "mismatch: $file -> repoURL=$repo targetRevision=$rev (expected $env_name)" >&2
            fail=1
          fi
        fi
        repo=""
      fi
    done <"$file"
  done < <(find "$argocd_dir" -type f -name '*.yaml' -print0 | sort -z)
done

if [[ "$fail" -ne 0 ]]; then
  echo "FAIL: revision mismatches detected" >&2
  exit 1
fi

echo "OK: all Argo CD sources resolve environment-consistent revisions"
