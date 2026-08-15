# Iteration 12 — environment-agnostic release paths

- Status: `CLAUDE_COMPLETED`
- Repository: `talos-vsphere-gitops`
- Branch: `refactor/iteration-012-env-agnostic-release-paths`

## Contract

Remove the environment name from the content of `release.yaml`, so copying an
environment directory produces a working environment without editing files.
No change to any rendered manifest, chart, pinned version, release identity,
namespace, or Argo CD Application.

## What was wrong

Every `release.yaml` declared its own location, including the environment:

```yaml
valuesFile: environments/lab/helm/cert-manager/values.yaml
```

A file already sitting in `environments/lab/helm/cert-manager/` restating its
own path is redundant, and it is what made `cp -r environments/lab
environments/prod` produce five broken release files.

## Implementation summary

All five `release.yaml` files now use a release-dir-relative reference:

```yaml
valuesFile: values.yaml
```

No consumer code changed. Both consumers already supported this form:

- `talos-toolchain/scripts/talos/phase-network-bringup.sh:148-170` resolves
  `valuesFile` through a four-case cascade — absolute, repo-root relative,
  **release-dir relative**, then basename fallback. The relative form is
  case 3.
- `talos-toolchain/scripts/talos/validate-cilium-handoff.sh:90-109` has the
  same release-dir-relative case, and compares day-1 against day-2 by
  **sha256 of file content**, not by path string, so shortening the path
  cannot break the comparison.

## Verification

- `validate-cilium-handoff.sh --day1-release=.../cilium/release.yaml
  --gitops-repo-root=... --environment=lab` → `OK: day-1 Cilium release
  matches the GitOps adoption contract for environment 'lab'`. This is the
  real check, not a fixture: it proves day-1 resolves the relative path and
  that its content hash still matches what the Argo CD Application
  references.
- `./scripts/validate-values-overrides.sh` — 5/5 addons pass, 4 render.
- **Environment copy proven**: `cp -r environments/lab <tmp>/prod` followed by
  `validate-values-overrides.sh <tmp>/prod/helm` passes with **zero edits** to
  the copied tree.
- `talos-toolchain` offline suite — 10/10, no regression.
- No Kubernetes, Argo CD, Docker, Talos, VMware, or credential access.

## The Argo CD side cannot be fixed the same way

An earlier plan claimed the four Argo CD Applications could also drop the
embedded `lab`. **That was wrong**, and it is recorded here so the mistake is
not repeated.

Argo CD resolves `valueFiles` entries under a `$ref` source **from that
repository's root**. It has no "relative to this manifest" semantics, so
`$values/environments/lab/helm/<addon>/values.yaml` cannot be shortened. Two
further references are environment-coupled by deliberate design, not by
accident:

- `targetRevision: lab` on the values source of all four apps, and on
  `root-app.yaml` — this is the documented per-environment branch contract in
  `docs/en/branch-revision-promotion.md` (`lab` → `lab`, `main` → `main`).
- `root-app.yaml`'s `path: environments/lab/argocd/apps`.

So copying an environment still requires editing the Argo CD manifests: four
apps plus the root app. Making *that* environment-agnostic means moving to an
ApplicationSet with a generator that templates the environment — a different
management model, and an owner decision rather than a refactor.

The practical result of this iteration: the **Helm half** of an environment
copy is now free, and the **Argo CD half** is five files with a known,
documented reason.

## Owner decision — ApplicationSet parked

Decided 2026-08-06: **do not build the ApplicationSet yet.** Revisit when a
real `prod` environment is actually on the table. The trigger is a second
environment existing, not a date.

An ApplicationSet is an Argo CD controller that *generates* Applications from a
template plus a list, instead of storing one hand-written file per addon:

```yaml
kind: ApplicationSet
spec:
  generators:
    - list:
        elements:
          - {env: lab,  addon: cilium}
          - {env: prod, addon: cilium}
  template:
    spec:
      sources:
        - helm:
            valueFiles:
              - $values/environments/{{env}}/helm/{{addon}}/values.yaml
```

The `{{env}}` placeholder is the whole point. The path still resolves from the
repository root — Argo CD's limitation does not disappear — but the environment
name becomes a variable instead of literal text, so adding an environment
becomes list entries rather than copied and edited files.

Why it is parked: with only `lab` in existence, it trades four readable
Applications for one templated file, adds indirection, and solves a cost that
is not yet being paid. With a real second environment the arithmetic reverses.

## Independent review

- Reviewer: pending
- Verdict: pending
