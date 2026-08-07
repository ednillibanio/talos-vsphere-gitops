# Project Agent Instructions

## Purpose

This repository is the Argo CD source of truth for Talos cluster platform
applications. Everything here is desired state that a controller applies to a
live cluster without review, so a wrong file lands in production by design, not
by accident.

## Cross-Repository Planning

- Read `docs/planning/talos-projects-roadmap.md` in the workspace root
  (`talos-projects-orchestration`) before cross-repository or roadmap work.
  Treat it as the canonical decision and status document.
- Before implementing an iteration, create or update its local record under
  `docs/planning/execution/` with the implementer, reviewer, branch, baseline
  commit, scope, and acceptance criteria.
- The implementer and reviewer must be different agents. Do not edit the same
  branch concurrently.
- Pushes, pull requests, and merges require explicit owner authorization.

## Language Policy

- Operator-facing documentation is bilingual: English in `docs/en/`, Portuguese
  (Brazil) in `docs/pt-br/`. Never mix both languages in one file, and update
  both sides when changing a guide.
- Script internals — comments, CLI help, log and error messages — are
  English-only.

## GitOps Contracts

These are contracts, not conventions. Read the linked document before changing
anything it governs; do not restate or reinterpret it here.

- **Owned values only.** `environments/<env>/helm/<addon>/values.yaml` holds
  only the keys that diverge from the chart's defaults — never a vendored copy,
  never a `values.base.yaml` beside it. `release.yaml` references it relative to
  its own directory. See `docs/en/values-ownership.md`.
- **Cilium is adopted, not installed.** The `addon-cilium` Application takes
  over an already-running, imperatively bootstrapped release. Chart, version,
  and values must stay in step with what `talos-toolchain` bootstrapped. See
  `docs/en/cilium-adoption.md`.
- **Revisions are pinned per environment.** Every Argo CD source pointing at
  this repository pins `targetRevision` to that environment's own branch
  (`lab` -> `lab`). See `docs/en/branch-revision-promotion.md`.

## Change Proof

This repository has no CI. The offline validators are the only gate that
exists, so running them is mandatory, not recommended. They need no cluster and
no credentials — they pull the pinned charts and render them.

Run the relevant validators before opening a pull request and paste their
output into it:

```bash
./scripts/validate-values-overrides.sh          # any values change
./scripts/validate-cilium-values-overrides.sh   # any Cilium values change
./scripts/validate-cilium-adoption-readiness.sh # any Cilium chart/version change
./scripts/validate-argocd-revisions.sh          # any Application or branch change
```

Known hole: `longhorn`'s pinned chart is not resolvable from the registries the
validator uses, so it reports that limitation instead of rendering. A green run
does not mean Longhorn's values were proven. Render it by hand before changing
them.

For a values change, a passing validator is not enough on its own — prove the
effect with a before/after `helm template` render, as
`docs/en/values-ownership.md` describes. "It renders" is not "it renders what I
intended".

## Scope Boundaries

- Never commit a real Argo CD repository Secret, kubeconfig, or talosconfig.
  The `.gitignore` is a backstop for a mistake, not a workflow, and it does not
  help a file that is already tracked. Only `*.example.yaml` templates belong
  in Git.
- Do not add a chart's full upstream defaults back into a values file. Roughly
  255 KB of vendored YAML was removed for this reason;
  `scripts/validate-values-overrides.sh` guards it.
- Do not propose an Argo CD ApplicationSet to deduplicate environments. The
  owner parked that decision deliberately while only `lab` exists; the trigger
  to revisit it is a real `prod` environment. See
  `docs/planning/execution/iteration-012.md`.
- Talos and Kubernetes lifecycle belong to `talos-toolchain`; VM and network
  provisioning belongs to `provision-talos-vsphere`. Neither is edited from
  here.
