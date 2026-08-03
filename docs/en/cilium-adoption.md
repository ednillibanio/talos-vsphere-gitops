# Cilium Adoption Contract (EN)

## Contract

`environments/<env>/argocd/apps/cilium.yaml` (the `addon-cilium` Application)
adopts an already-running, imperatively-installed Cilium Helm release rather
than installing a fresh one. `talos-toolchain` bootstraps Cilium day-1
(before Argo CD exists, because Cilium provides the CNI Kubernetes and Argo
CD both need) using the same chart, chart version, and values file this
repository declares; see `talos-toolchain`'s
`docs/en/cilium-gitops-handoff.md` for the day-1 side of this contract.

Adoption is declarative and readiness-checked, not imperative:

- **Same Helm release identity.** The `Application`'s
  `helm.releaseName` and `destination.namespace` must match the release
  day-1 created, so Argo CD's first sync recognizes and takes ownership of
  the existing release instead of creating a conflicting second one.
- **Same rendered content.** The chart source (`repoURL` + `chart` +
  `targetRevision`) and the referenced values file
  (`$values/environments/<env>/helm/cilium/values.yaml`) must be the exact
  ones day-1 rendered from, so the first Argo sync is a no-op diff, not an
  unplanned change to a live CNI.
- **Environment revision agreement.** The values-ref source (the source
  pointing back at this repository) must pin `targetRevision` to the
  environment directory name (`lab` -> `lab`, `main` -> `main`), per
  `docs/en/branch-revision-promotion.md`.
- **Fully automated sync policy.** `syncPolicy.automated.prune` and
  `selfHeal` must both be `true`, so Argo CD actually reconciles Cilium
  going forward instead of leaving it in a manual-sync-only state.

## Validating readiness offline

`scripts/validate-cilium-adoption-readiness.sh` checks every
`environments/<env>/argocd/apps/cilium.yaml` present in this repository for
the properties above, with no live Argo CD, Kubernetes, or Helm access:

```bash
./scripts/validate-cilium-adoption-readiness.sh
```

Run `scripts/validate-cilium-adoption-readiness.test.sh` to confirm the
validator itself still passes a complete fixture and fails fixtures missing
the values file, with a non-automated sync policy, or with a mismatched
environment revision:

```bash
./scripts/validate-cilium-adoption-readiness.test.sh
```

This complements `scripts/validate-argocd-revisions.sh` (which checks
revision agreement across every Application in every environment) with
Cilium-specific adoption-readiness checks, and complements
`talos-toolchain`'s `validate-cilium-handoff.sh` (which additionally compares
against the actual synced day-1 release on the toolchain side).

## Adoption sequence

1. `talos-toolchain` bootstraps Cilium day-1 from this repository's
   `environments/<env>/helm/cilium/` values (imperative `helm upgrade
   --install`).
2. `talos-toolchain` runs `validate-cilium-handoff.sh` to confirm the synced
   day-1 release still matches this repository's `cilium.yaml` before
   proceeding.
3. `talos-toolchain` deploys the Argo CD root app
   (`talos-gitops.sh deploy-argocd-root-app`).
4. Argo CD's `addon-cilium` Application performs its first sync. Because the
   release identity, chart, version, and values already match, this sync is
   a no-op (or a benign metadata adoption), not a reinstall.
5. From this point on, Argo CD exclusively reconciles Cilium; no repository
   or script should perform another imperative Cilium install.

## Values-file ownership

`environments/<env>/helm/cilium/values.yaml` holds only this lab's owned
overrides — the keys where the desired state intentionally diverges from the
Cilium chart's own defaults (e.g. `k8sServiceHost`/`k8sServicePort`,
`ingressController`, `gatewayAPI`, `encryption`, `ipam.mode`,
`kubeProxyReplacement`, `cgroup`). It is not, and must not become again, a
vendored copy of the chart's full default `values.yaml`: every key this file
does not set falls back to the chart's own built-in default at render time,
same as day-1's `helm upgrade --install` and Argo CD's render resolve it.
`scripts/validate-cilium-values-overrides.sh` checks this contract offline —
that the file still declares every documented override key, carries none of
the chart's generated "DO NOT EDIT" vendoring marker, and has no leftover
`values.base.yaml` sitting next to it — and renders the file against the
pinned chart version with `helm template` when Helm can resolve that chart
from the registry (no live cluster, no credentials). Run
`scripts/validate-cilium-values-overrides.test.sh` to confirm the validator
itself still passes a minimal fixture and fails one carrying the vendoring
marker, one missing a documented key, and one with a leftover
`values.base.yaml`.

## Rollback / recovery

If Cilium reconciliation fails or degrades networking after adoption:

1. Do not fall back to an imperative reinstall. `talos-toolchain`'s
   `talos-gitops.sh` hard-excludes `cilium` from both
   `install-platform-helm` and `install-addon` once Argo owns the release,
   specifically to prevent a second imperative Helm write from racing Argo
   CD's reconciliation loop.
2. Fix forward declaratively in this repository: correct
   `environments/<env>/helm/cilium/values.yaml` or the chart
   `targetRevision` in `cilium.yaml`, and let `syncPolicy.automated.selfHeal`
   reconcile the change.
3. To roll back, revert the offending commit on the environment's branch
   (`lab` or `main`) rather than hand-editing live cluster state; Argo CD's
   `selfHeal` converges the cluster back to the reverted, last-known-good
   manifest.
4. Re-run `validate-cilium-adoption-readiness.sh` (and, from
   `talos-toolchain`, `validate-cilium-handoff.sh`) after any fix or
   rollback to confirm the adoption contract holds again before considering
   the cluster healthy.
