# Environments: Stage and Target (EN)

This is the canonical explanation of what an `environments/<name>` directory
means, why it is named the way it is, and how to add one. Everything else that
touches environment naming (`branch-revision-promotion.md`,
`values-ownership.md`, `day2-operations.md`) links back here for the model and
covers its own narrower slice (branch pinning, values ownership, day-2
commands) in depth.

## The two axes

Every environment answers two independent questions, and this repository has
historically conflated them into one directory:

- **Stage** — where is this in the promotion path? `lab` is promoted to
  `main`; a `staging` in between would sit before `main` too. Promotion means
  a pull request from one branch to the next, carrying reviewed changes
  forward.
- **Target** — what infrastructure does this stage actually run on? A
  container cluster (Docker/Colima, for fast local iteration) and a vSphere
  cluster (for real, deeper testing) can both be running the **same stage** —
  the same desired state, the same addon versions — at the same time, on
  different hardware. A target is never promoted; it just names where a stage
  is deployed.

Confusing the two used to force one branch per infrastructure choice, which
made every addon fix a two-branch chore. The fix was to stop encoding target
in the branch and start encoding it only in the directory name.

## The contract

An environment directory is named `<stage>[-<target>]`. Everything **up to
the first dash** is the stage and pins the Argo CD `targetRevision` (the Git
branch); everything after it is the target and does not affect the branch at
all.

```
environments/lab              stage=lab   target=(none)   -> targetRevision: lab
environments/lab-container     stage=lab   target=container -> targetRevision: lab
environments/lab-vsphere       stage=lab   target=vsphere    -> targetRevision: lab
environments/main              stage=main  target=(none)   -> targetRevision: main
environments/staging-vsphere   stage=staging target=vsphere -> targetRevision: staging
```

A name with no dash is its own stage with an implicit "no target split yet" —
this is why `environments/lab` and `environments/main` keep working exactly
as they did before targets existed.

### Worked example: this workspace's actual roadmap

This is not a hypothetical grid. It is the shape already in use or planned:

| Directory | Stage | Target | Branch | Status |
| --- | --- | --- | --- | --- |
| `environments/lab` | `lab` | (none, historically vsphere-shaped) | `lab` | live today |
| `environments/lab-container` | `lab` | container (Docker/Colima) | `lab` | live today |
| `environments/lab-vsphere` | `lab` | vsphere | `lab` | not yet created — see "Open question" below |
| `environments/staging` (future) | `staging` | vsphere | `staging` | pre-production; promoted from `lab`, becomes `main` if it holds |
| `environments/main` (future) | `main` | vsphere | `main` | production |
| a future `-eks` target | any stage | eks | that stage's branch | not planned, but the contract already supports it — it is just another suffix |

`lab-container` and `lab-vsphere` share the `lab` branch on purpose: they are
the same desired state on different hardware, so an addon fix lands once and
both targets pick it up on their next sync. `staging` and `main` will each be
their own branch, because promoting `staging` to `main` is exactly the kind of
change that must go through review — that is what "stage" means.

## The mechanism: how Argo CD actually resolves this

There is no separate stage/target field anywhere in Argo CD. The contract is
enforced entirely through three plain fields on every `Application` source
that points at this repository:

- `repoURL` — this Git repository.
- `targetRevision` — the branch to check out. This is the stage.
- `path` (root app) or the `$values/...` value-file path (child apps) — the
  directory to read from. This is the stage **and** target together, because
  it is the full `environments/<stage>[-<target>]/...` path.

Concretely, in `environments/lab-container/argocd/apps/cilium.yaml`:

```yaml
sources:
  - repoURL: oci://quay.io/cilium/charts   # the chart itself
    chart: cilium
    targetRevision: 1.19.1                 # chart version, unrelated to stage
    helm:
      valueFiles:
        - $values/environments/lab-container/helm/cilium/values.yaml
  - repoURL: https://github.com/ednillibanio/talos-vsphere-gitops.git
    targetRevision: lab                    # the STAGE, not "lab-container"
    ref: values
```

Two different `targetRevision` fields appear in the same file for two
different reasons: the first pins the external chart's version, the second
pins this repository's branch. Only the second is stage-governed. This is a
common misreading — see `branch-revision-promotion.md` if this file is being
edited by hand.

## What legitimately varies by target, and what does not

Target is about **capacity and topology**, never about intent. If two targets
want a genuinely different desired state — not a different amount of the same
state — that difference belongs to a different stage, not a target.

Measured so far (see `docs/planning/execution/iteration-014.md` and
`day2-operations.md` for the full evidence):

| Concern | Varies by target? | Where it lives |
| --- | --- | --- |
| Argo CD `redis-ha`, replica counts | **Yes** — `redis-ha` wants 3 replicas with anti-affinity across nodes; a 1 CP + 1 worker container cluster can only ever schedule 1 | `environments/<stage>-container/helm/argocd/values.yaml` vs. `environments/<stage>/helm/argocd/values.yaml` |
| cert-manager, Cilium, Longhorn, prometheus-stack config | **No, not yet** — nothing measured so far needs to differ | shared: only `environments/<stage>/helm/<addon>/*` and `environments/<stage>/argocd/**` exist; targets that don't need their own copy simply don't get one |
| Chart versions | No — versions are a stage-wide decision, bumped deliberately and independent of target | `release.yaml` under the stage's own tree |
| Storage (Longhorn as a real target) | Not measured — container has no block devices at all; `addon-longhorn` stays `OutOfSync/Missing` there. Not confirmed as fixable by values alone | open, see `day2-operations.md` §3 |

This is why `environments/lab-container` today contains only
`helm/argocd/{release.yaml,values.yaml}` with resized values, copied
unmodified from `environments/lab` — it does **not** duplicate
`argocd/root-app.yaml` or `argocd/apps/*.yaml` for the four Argo CD-managed
addons; the day-2 bootstrap simply installs Argo CD itself imperatively with
the container-sized values, then Argo CD's own root app and children reconcile
from the shared `environments/lab` tree as normal, since nothing in that tree
is target-specific yet.

## Adding a target to an existing stage

1. Confirm what actually differs. Do not create a target directory to be
   thorough — create one because something was measured to not schedule, not
   render, or not converge on that infrastructure (see the table above).
2. If only Helm values differ (the common case so far):
   ```bash
   mkdir -p environments/<stage>-<target>/helm/<addon>
   cp environments/<stage>/helm/<addon>/release.yaml \
      environments/<stage>-<target>/helm/<addon>/release.yaml
   # edit environments/<stage>-<target>/helm/<addon>/values.yaml by hand —
   # do not copy the source values.yaml verbatim, size it for the target
   ```
   Nothing under `argocd/` needs a copy. `targetRevision: <stage>` was never
   touched, so `validate-argocd-revisions.sh` needs no exception.
3. If the whole desired state has to differ — every addon, not just sizing —
   copy the full stage directory instead (see "Adding a full environment"
   below) with the target suffix, and expect to maintain the Argo CD
   Application manifests twice. That is a bigger decision; say so explicitly
   in the iteration record before doing it.
4. Run the offline validators before opening a PR:
   ```bash
   ./scripts/validate-values-overrides.sh environments/<stage>-<target>/helm
   ./scripts/validate-argocd-revisions.sh
   ./scripts/validate-cilium-adoption-readiness.sh   # if the target has its own cilium.yaml
   ```
5. Document the day-2 bootstrap command for the new target if it differs from
   the existing `--manifest-root-dir=environments/<stage>` shortcut (see
   `day2-operations.md` §2–3).

## Adding a new stage (promotion)

This is the full-directory-copy path, and it is deliberate, not a workaround —
see `values-ownership.md` §"Copying an environment" and
`docs/planning/execution/iteration-012.md` for why Argo CD's `$values`
resolution (repository-root-relative, not manifest-relative) makes this
unavoidable today. Full procedure: `branch-revision-promotion.md`
§"Promoting `lab` to `main`".

## Known limitation: this duplicates four Applications per environment

Every environment directory carries its own `argocd/root-app.yaml` and four
`argocd/apps/*.yaml`, byte-identical to another environment's except for the
embedded path and branch. Iteration 12 confirmed this is not fixable by a
path refactor: Argo CD resolves `$values` sources from the repository root
with no manifest-relative form. Iteration 14 parked the alternative — an
ApplicationSet with a generator that templates the environment — as a real
design change requiring an owner decision, not a drop-in fix; see
`docs/planning/execution/iteration-014.md` item 5. Until that lands, adding a
stage means editing five files by hand; adding a target usually does not,
because most targets so far only touch Argo CD's own sizing.

## Open question: `environments/lab` itself

The live cluster's root app currently points at `environments/lab`, which
today is target-unlabeled but vSphere-shaped in practice (its `redis-ha`
setting assumes a real multi-node cluster). Whether it should be renamed to
`environments/lab-vsphere` for symmetry with `lab-container`, or stay as the
implicit "default" target, is **not decided** — a rename touches the live root
app and is not free. See `docs/planning/execution/iteration-014.md` item 4.

## Related

- Branch/revision mechanics and the promotion procedure:
  `branch-revision-promotion.md`
- Values ownership and why the Argo CD side cannot be made path-agnostic:
  `values-ownership.md`
- Day-2 commands, per-target measured limits, and how to reach each addon:
  `day2-operations.md`
- The measurement that started this: `docs/planning/execution/iteration-013.md`
- This model's own history: `docs/planning/execution/iteration-014.md`
- The parked ApplicationSet alternative: `docs/planning/execution/iteration-012.md`
