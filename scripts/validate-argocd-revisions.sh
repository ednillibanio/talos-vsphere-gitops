#!/usr/bin/env bash
set -euo pipefail

# validate-argocd-revisions.sh
#
# Offline check that every Argo CD Application source pointing at this
# GitOps repository resolves the Git revision of its promotion stage.
#
# An environment directory is named <stage>[-<target>]. The stage is the part
# before the first dash and is what pins the branch; the optional target names
# the infrastructure the same desired state runs on:
#
#   environments/lab           -> lab
#   environments/lab-container -> lab
#   environments/lab-vsphere   -> lab
#   environments/main          -> main
#
# Stage is a promotion concept: lab is promoted to main. Target is not.
# Container and vSphere are the same stage on different infrastructure, so
# they share a branch deliberately -- putting them on separate branches would
# make them diverge and force every addon change to be applied twice.
#
# Detects mixed revisions without contacting a live Argo CD or Kubernetes
# cluster.
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
  # The promotion stage is the directory name up to the first dash. A name
  # with no dash is its own stage, which keeps environments/lab and
  # environments/main behaving exactly as before.
  stage_name="${env_name%%-*}"
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
          if [[ "$rev" != "$stage_name" ]]; then
            echo "mismatch: $file -> repoURL=$repo targetRevision=$rev (expected $stage_name, the stage of environment $env_name)" >&2
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
