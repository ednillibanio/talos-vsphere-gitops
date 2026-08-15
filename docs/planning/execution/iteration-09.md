# Iteration 09 — Cilium/Argo CD adoption contract

- Status: `CLAUDE_COMPLETED — awaiting Codex review`
- Repository: `talos-vsphere-gitops`
- Issue: [#7](https://github.com/ednillibanio/talos-vsphere-gitops/issues/7)
- Branch: `docs/issue-007-cilium-adoption`
- Paired with: `talos-toolchain` issue #17
  (`feat/issue-017-cilium-handoff`), separate PR.

## Contract

The `addon-cilium` Argo CD Application adopts an already-running,
imperatively bootstrapped Cilium Helm release. Adoption is safe only when
Helm release identity (name/namespace), rendered chart/version/values, the
environment revision on the values-ref source, and the sync policy
(`prune`+`selfHeal` both `true`) all agree with what `talos-toolchain`
bootstrapped on day-1.

## Scope and acceptance

- Document the declarative readiness/adoption/rollback contract:
  `docs/en/cilium-adoption.md` + `docs/pt-br/cilium-adoption.md`, linked from
  both README indexes.
- Add an offline fixture validator,
  `scripts/validate-cilium-adoption-readiness.sh` (+
  `scripts/validate-cilium-adoption-readiness.test.sh` and
  `scripts/testdata/cilium-readiness/**`), following the same conventions as
  `scripts/validate-argocd-revisions.sh`.
- Do not contact a live Argo CD/Kubernetes cluster, and do not change any
  chart, values, or Application manifest's live behavior.

## Implementation summary

- `scripts/validate-cilium-adoption-readiness.sh` scans every
  `environments/<env>/argocd/apps/cilium.yaml` for: required Helm release
  identity fields (releaseName, namespace, chart repoURL/chart/version),
  existence of the referenced `$values/...` file in this repository,
  environment-revision agreement on the values-ref source (reusing the same
  `lab`/`main` contract as `validate-argocd-revisions.sh`), and a fully
  automated `syncPolicy` (`prune`+`selfHeal` both `true`).
- `scripts/validate-cilium-adoption-readiness.test.sh` exercises the
  validator against `scripts/testdata/cilium-readiness/{valid,
  missing-values-file,not-automated,wrong-revision}/environments/**`
  fixtures — one passing, three failing with the expected diagnostic.
- Real `environments/lab/argocd/apps/cilium.yaml` was validated as-is
  (unchanged) and passes.

### Commands run

- `bash scripts/validate-cilium-adoption-readiness.test.sh` — 4/4 assertions
  pass.
- `bash -n scripts/validate-cilium-adoption-readiness.sh` /
  `scripts/validate-cilium-adoption-readiness.test.sh` — clean.
- `shellcheck scripts/validate-cilium-adoption-readiness.sh
  scripts/validate-cilium-adoption-readiness.test.sh` — clean.
- `./scripts/validate-cilium-adoption-readiness.sh` (real `environments/`)
  — `OK`.
- `./scripts/validate-argocd-revisions.sh` (pre-existing, unaffected) —
  `OK`, rerun for regression safety.

### Deviations / known limitations

- No change to any Application/chart/values manifest; this iteration is
  docs + a new offline validator only.
- The validator parses the known two-source Cilium `Application` shape with
  a line-oriented `awk` scanner (same pragmatic approach as
  `validate-argocd-revisions.sh`), not a general YAML parser.
- No live Argo CD/Kubernetes/Helm operation was performed or authorized.
