# Iteration 11 — minimal cert-manager and prometheus-stack overrides

- Status: `CLAUDE_COMPLETED`
- Repository: `talos-vsphere-gitops`
- Branch: `refactor/iteration-011-minimal-values-overrides`

## Contract

Extend the owned-override contract that iteration 10 applied to Cilium so it
covers every addon in `environments/lab/helm/`, without changing any rendered
manifest, chart, pinned version, release identity, namespace, values-file
path, or Argo CD Application.

## What was actually wrong

Two of the five addons carried a vendored copy of their chart's default
values:

| Addon | `values.yaml` before | Real overrides |
| --- | --- | --- |
| `cert-manager` | 63,496 bytes | `installCRDs: true` and `crds.enabled: true` — 2 lines |
| `prometheus-stack` | 191,908 bytes | **none** — byte-identical to the chart defaults apart from one trailing blank line |

`argocd` (476 B), `longhorn` (263 B) and `cilium` (2,662 B) were already small
owned override files, so the pattern was inconsistent across the repo.

## Implementation summary

- Diffed each vendored `values.base.yaml` against its `values.yaml` to
  enumerate the real overrides, then rewrote both files as owned override
  sets with `# --` comments explaining each divergence, matching the Cilium
  file's established style.
- `prometheus-stack/values.yaml` became `{}` plus a header recording that the
  lab overrides nothing, and that this is a finding rather than a design.
- Deleted both now-unreferenced `values.base.yaml` files (255 KB total).
- Added `scripts/validate-values-overrides.sh` — the addon-agnostic
  counterpart to the Cilium-specific validator. It asserts, for every addon
  under a Helm root, that a values file exists, carries no chart vendoring
  marker, and has no leftover `values.base.yaml`, then renders each addon
  against its pinned chart when Helm can resolve it.
- Added `scripts/validate-values-overrides.test.sh` with six fixture cases.
- Added EN/PT-BR `values-ownership.md` and linked both from the doc indexes.

## Verification

**Render equivalence was proven, not assumed.** Both addons were rendered
against their pinned charts before and after the change:

- `cert-manager` v1.20.0 — 13,855 lines, **byte-identical** before and after.
- `kube-prometheus-stack` 82.13.6 — 6,772 lines, identical except two lines:
  the Grafana `admin-password` and its dependent `checksum/secret`. Rendering
  the **unmodified original** file twice produces the same two-line
  difference, which proves the chart generates a random password per render
  and that the difference is not caused by this change.

Other checks:

- `./scripts/validate-values-overrides.sh` — all 5 addons pass; 4 render
  against their pinned charts. `longhorn` reports a limitation because the
  `longhorn/longhorn` repo alias is not configured locally, which is the
  intended not-a-failure path.
- `./scripts/validate-values-overrides.test.sh` — 6/6.
- The validator was run against the **pre-refactor** files and correctly
  failed them on the vendoring markers, confirming the guard is not vacuous.
- `bash -n` and ShellCheck clean on both new scripts.
- No Kubernetes, Argo CD, Docker, Colima, Talos, VMware, or credential access.
  Chart pulls are registry reads only.

## Known limitations and follow-up

- `cert-manager/values.yaml` keeps both `installCRDs` and `crds.enabled`. The
  chart deprecates the former, but the two are not interchangeable at render
  time and the vendored file set both. Migrating off the deprecated key needs
  its own render proof and is deliberately out of scope here.
- `prometheus-stack` overriding nothing is recorded, not resolved. Either the
  chart defaults genuinely suit this lab, or tuning was intended and never
  done. That is an owner decision, not a refactor.
- `release.yaml` still hardcodes `valuesFile: environments/lab/...` for every
  addon, so creating a second environment means editing all five files. This
  is the remaining half of the model→materialize idea and was explicitly left
  for separate work.
- This repository has no CI workflow, so both validators are manual. Worth
  wiring up alongside the rename work.

## Independent review

- Reviewer: pending
- Verdict: pending
