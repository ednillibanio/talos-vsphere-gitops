# Documentation Index (EN)

This is the English entrypoint for GitOps documentation.

## Repository Purpose

- Keep day-2 platform manifests as source of truth.
- Be consumed by Argo CD root app from cluster automation.

## Current Structure

- `environments/lab/argocd/root-app.yaml`
- `environments/lab/argocd/apps/*.yaml`
- `environments/lab/helm/<addon>/release.yaml`
- `environments/lab/helm/<addon>/values.yaml`

## Operational Notes

- Argo CD root app path currently points to:
  - `environments/lab/argocd/apps`
- Child applications render/addon lifecycle from this repo.

## Related Repositories

- Day-1 bootstrap/tooling integration:
  - `talos-vsphere-lab`
- Future reusable Talos toolchain:
  - separate toolchain repository (in preparation)
