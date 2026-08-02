# Documentation Index (EN)

This is the English entrypoint for GitOps documentation.

## Repository Purpose

This repository owns Argo CD desired state, environment revision policy,
platform services, and workloads after Kubernetes bootstrap. It:

- Keeps day-2 platform manifests as source of truth.
- Is consumed by the Argo CD root app from cluster automation.

## Current Structure

- `environments/lab/argocd/root-app.yaml`
- `environments/lab/argocd/apps/*.yaml`
- `environments/lab/helm/<addon>/release.yaml`
- `environments/lab/helm/<addon>/values.yaml`

## Operational Notes

- Argo CD root app path currently points to:
  - `environments/lab/argocd/apps`
- Child applications render/addon lifecycle from this repo.
- Every environment's Argo CD sources pin `targetRevision` to that
  environment's own branch (`lab` -> `lab`, `main` -> `main`); see
  `docs/en/branch-revision-promotion.md` for the contract, the offline
  validator, and the promotion procedure.

## Milestones

- macOS Milestone A: a local cluster can be bootstrapped and reconciled
  through `talos-toolchain` without any VMware provisioning. This repository's
  Argo CD manifests apply the same way regardless of where the underlying
  Kubernetes cluster runs.
- vSphere provisioning and VIP validation are a later, deferred milestone
  owned by `provision-talos-vsphere`, not a dependency of local macOS work.

## Related Repositories

- Talos day-1/day-2 lifecycle CLI (canonical Talos CTL):
  - `talos-toolchain`
- vSphere/ESXi provisioning integration:
  - `provision-talos-vsphere`
- Cross-repository execution handoff:
  - `provision-talos-vsphere/docs/en/cross-repo-handoff.md`
