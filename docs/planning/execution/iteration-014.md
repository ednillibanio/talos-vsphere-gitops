# Iteration 14 — separate promotion stage from deployment target

- Status: `IN_PROGRESS`
- Repository: `talos-vsphere-gitops`
- Branch: `feat/target-stage-split`
- Baseline commit: `561b9a4` (`lab`)
- Implementer: Claude
- Reviewer: pending (must not be the implementer)
- Date opened: 2026-08-07

## Process note

This record was written **after** the first commit, not before it, which the
repository's own `AGENTS.md` requires. The owner caught it. `d904427` was
already pushed to the branch when this was opened; nothing had reached `lab`.
Recorded here rather than backdated, because the point of the rule is that
scope and acceptance criteria are agreed before implementation, and on this
change they were not.

## Why

Iteration 13's live day-2 test established that `environments/lab` cannot serve
both a container-backed cluster and vSphere. Measured, not assumed:

- `redis-ha` wants 3 replicas with `podAntiAffinity` on
  `kubernetes.io/hostname`; on 1 control-plane + 1 worker the result is
  `replicas=3 ready=1`, permanently `Pending`. The requirement comes from this
  repository's `helm/argocd/values.yaml`, not from the chart.
- With the full addon set on 4 vCPUs, the cluster reached 31 pods and 114
  accumulated restarts. `argocd-server` ran 2 replicas that alternated between
  `Running` and `CrashLoopBackOff`, each exiting 0 after SIGTERM — liveness
  probes timing out under CPU starvation. Scaling `server`, `repo-server` and
  `applicationset` to 1 replica stopped the churn (31 -> 28 pods).

The owner framed the conclusion precisely: raising Colima's CPU and sizing the
configuration to the topology are different things. The topology is the fact;
the configuration has to fit it.

## The contract problem this had to solve first

Environment directory name was bound one-to-one to branch name, enforced by
`validate-argocd-revisions.sh`. Under that rule, splitting targets meant two
branches for one platform — so every addon fix would be applied twice by hand,
and drift would be the default outcome.

Container and vSphere are not promotion stages. They are the same desired state
on different infrastructure. Stage is what gets promoted (`lab` -> `main`);
target is not promoted at all.

**Decision (owner, 2026-08-07):** directories are `<stage>[-<target>]`. The
stage before the first dash pins the branch; the optional target names the
infrastructure. Both targets of a stage share that stage's branch.

## Scope

In scope:

1. Teach `validate-argocd-revisions.sh` the stage/target rule. **Done**
   (`d904427`).
2. Update `branch-revision-promotion.md`, EN and PT-BR. **Done** (`d904427`).
3. Create `environments/lab-container` with values sized for 1 CP + 1 worker.
   **Not started.**
4. Decide the fate of `environments/lab` — rename to `lab-vsphere`, or keep as
   the vSphere-intended environment. **Not decided.** The live cluster's root
   app currently points at `environments/lab`, so a rename is not free.
5. Show the owner a finished ApplicationSet file before committing to it. The
   owner accepted the direction while stating plainly they do not yet know how
   it will look, so it is to be judged as written, and dropped without argument
   if it reads worse than the five manifests. **Not started.**

Out of scope: the addon set per target beyond replica sizing; storage strategy
for the container target; any change to `talos-toolchain`.

## Acceptance criteria

- `validate-argocd-revisions.sh` accepts `environments/lab-container` pinning
  `lab`, still rejects a genuine mixed revision, and its test suite proves the
  previous validator rejected the new case. **Met.**
- `environments/lab` and `environments/main` behave exactly as before, since a
  name without a dash is its own stage. **Met** — the real repository check
  passes unchanged.
- The container environment's Argo CD reaches a steady state on the local
  cluster: no `Pending` pods from anti-affinity, no restart churn on
  `argocd-server`. **Not yet verified.**
- Every addon change needs to be made once, not once per target. **Not yet
  demonstrated** — this is what the ApplicationSet question decides.

## Live-cluster state to unwind

Two changes were made directly to the running cluster while diagnosing, and
neither is in this repository:

- `helm upgrade --set redis-ha.enabled=false` on the `argocd` release.
- `kubectl scale` to 1 replica for `argocd-server`, `argocd-repo-server`,
  `argocd-applicationset-controller`.

Both are diagnosis, not solution. A `helm upgrade` from repository values undoes
both. They belong in the container environment's values, which is item 3.
