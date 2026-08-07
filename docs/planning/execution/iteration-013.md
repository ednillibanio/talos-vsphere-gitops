# Iteration 13 — first live day-2 test

- Status: `CLAUDE_COMPLETED`
- Repository: `talos-vsphere-gitops` (with one fix in `talos-toolchain`)
- Branch: `docs/iteration-013-day2-live-test`
- Date: 2026-08-07

## Why

Everything this repository had been verified with was offline: chart renders,
values-override checks, revision pinning. None of it executes an install. The
owner asked the obvious question — *"nada de testes até agora desse repo
gitops. testes reais."* — and it was correct. Day-2 had never been run.

## Environment

Local Docker-backed Talos via `local-cluster.sh create --name=talos-lab
--cni=cilium`. 1 control-plane + 1 worker, the wrapper's default; the Talos
Docker backend supports exactly 1 control-plane. **No host counts or topology
values were changed for this test.**

Day-1 reproduced cleanly and is not in question:

```
talos-lab-controlplane-1   Ready   control-plane   12m   v1.36.2
talos-lab-worker-1         Ready   <none>          12m   v1.36.2
11/11 pods Running, cilium 1.19.1 deployed
```

## What worked

| Component | Result |
|---|---|
| Argo CD install | `argo-cd-9.4.15` deployed |
| cert-manager | Application `Synced` / `Healthy` — full reconciliation |
| `addons-root` | `Synced` / `Healthy` |
| Cilium adoption | sync `Succeeded`; **pods Running 60m, 0 restarts** |

The adoption contract's critical safety property — Argo CD taking ownership
without disrupting the CNI — held under live conditions for the first time.

## Defect 1 — day-2 never worked at all (`talos-toolchain`, fixed)

`install-platform-helm` failed on the first addon, Argo CD itself:

```
error validating ".../argocd/rendered.yaml": [apiVersion not set, kind not set]
```

`helm template` writes OCI pull progress to **stdout**, ahead of the manifest
(`Pulled:` / `Digest:`). Confirmed stdout, not stderr, by reproducing with
`2>/dev/null`. Redirected into the render file those lines form a leading YAML
document with no `apiVersion`/`kind`, and the mandatory server-side dry-run
rejects everything.

`phase-network-bringup.sh` already carried this exact filter, with a comment
describing this exact error. **Day-1 was fixed and day-2 was not** — the mirror
image of iteration 16's note in `talos-toolchain` that both paths had been
fixed together. Every `oci://` addon was blocked: `argocd`, `cilium`,
`prometheus-stack`. `cert-manager` escaped only by using a classic repo alias.

Fixed in `talos-toolchain` PR #26.

## Defect 2 — Cilium Application never reconciled (fixed)

```
HEAD "https://quay.io/v2/cilium/charts/manifests/1.19.1" -> 401 Unauthorized
```

Not an auth problem. With the `oci://` prefix Argo CD treats `repoURL` as the
complete artifact reference and never appends `chart`, and **quay.io answers
401 rather than 404 for a nonexistent path**, disguising a wrong URL as missing
credentials.

| Path | Result |
|---|---|
| `/v2/cilium/charts/manifests/1.19.1` | 401 |
| `/v2/cilium/charts/cilium/manifests/1.19.1` | 200 |

Patching the live Application proved the cause and then **did not survive** —
the root app's `selfHeal` restored `oci://` from Git and the 401 returned. That
is GitOps behaving correctly, and it is why the fix belongs in the repository.

Fixed in PR #15. Verified persisting from `lab` after merge.

**Misleading signal:** the Application reported `Healthy` throughout, because
the day-1 Cilium resources exist. Health described objects Argo CD was not
managing. Do not read `Healthy` as "adopted".

## Defect 3 — Cilium Secrets drift permanently (open)

After a successful sync, two resources stay `OutOfSync` forever:

```
Secret/cilium-ca           OutOfSync
Secret/hubble-server-certs OutOfSync
```

Helm generates them per render (`genCA` / `genSignedCert`), so every comparison
differs by construction. The Application can never reach `Synced`. Needs
`ignoreDifferences` on those Secrets or a pinned CA in values. Not fixed here.

## Defect 4 — CRDs missing from renders (open)

`kube-prometheus-stack` fails under Argo CD with:

```
no matches for kind "Alertmanager" in version "monitoring.coreos.com/v1"
ensure CRDs are installed first
```

Measured directly: `helm template` renders **0** CRDs; with `--include-crds`,
**10**. Neither `talos-gitops.sh` nor `phase-network-bringup.sh` passes that
flag, so the render used for server-side dry-run omits CRDs that
`helm upgrade --install` does install — the validation set differs from the
installed set.

**This is not a local-environment limitation.** It would fail identically on
vSphere. An earlier prediction in this session that prometheus-stack would fail
for lack of storage was wrong; the cause is CRD ordering.

## Environment limits, correctly attributed

- `argocd-redis-ha`: desired 3, ready 1, for both the StatefulSet and the
  haproxy Deployment. Anti-affinity `topologyKey: kubernetes.io/hostname`
  requires 3 distinct nodes; this cluster has 2, one of them tainted.
  **The requirement is written in the repository**, not inherited from the
  chart: `environments/lab/helm/argocd/values.yaml` sets `redis-ha.enabled:
  true`. The chart's own default is a single non-HA Redis.
- `addon-longhorn`: stuck on `waiting for completion of hook
  batch/Job/longhorn-pre-upgrade`. Plausibly the absence of real block devices;
  **not confirmed**, and recorded as unconfirmed.

## What this says about the offline validators

Four defects, none of which any offline validator could detect. They render
values; they do not install. That is not an argument against them — Defect 4
was found *because* a render was compared against an install — but a green
validator run must not be read as day-2 coverage. The `AGENTS.md` gate wording
should not be understood to promise more than it checks.

## Consequence — one `lab` cannot serve two targets

`environments/lab` is a single environment used for both the container-backed
local cluster and the intended vSphere one, with an HA topology written into it
that the local target cannot schedule. The owner decided on 2026-08-07 to split
into per-target environments and, because that is exactly the trigger recorded
in iteration 12, to **revisit the parked ApplicationSet decision** rather than
copy five Argo CD manifests per environment.

Open design tension, to settle when that work starts: `branch-revision-promotion.md`
binds environment name to branch name and `validate-argocd-revisions.sh`
enforces it, so two environments imply two diverging branches for one platform.
And each addon turned out to carry its own exception — Cilium's unprefixed
`repoURL` and Secret drift, prometheus-stack's CRDs, Longhorn's hook — which in
an ApplicationSet become template conditionals.
