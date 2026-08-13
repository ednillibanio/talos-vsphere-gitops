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
   **Done** (this session, 2026-08-13). Design note: only
   `helm/argocd/{release.yaml,values.yaml}` is target-specific — `argocd/`
   (root app + 4 child Applications) and every other addon's `helm/<addon>/`
   are **not** duplicated, since nothing measured so far diverges by target
   for them. `docs/en/environments-and-targets.md` (+ PT-BR) documents the
   full model and this decision.

   Fixed along the way: `validate-cilium-adoption-readiness.sh` was not
   updated in `d904427` alongside `validate-argocd-revisions.sh` — it still
   compared `targetRevision` against the full directory name instead of the
   stage, so it would have rejected `lab-container`'s Cilium Application.
   Fixed to use the same `${env_name%%-*}` stage rule, with a
   `target-suffix` fixture proving the old comparison would have failed.
4. Decide the fate of `environments/lab` — rename to `lab-vsphere`, or keep as
   the vSphere-intended environment. **Decided (owner, 2026-08-13): keep
   `environments/lab` as the implicit default target** — it is the
   VM/baremetal/vSphere-shaped environment (`redis-ha` enabled assumes a real
   multi-node cluster), `lab-container` is the only environment that diverges
   from it, and the live root app already points at `environments/lab`, so a
   rename would not be free for no real gain. No rename.
5. Show the owner a finished ApplicationSet file before committing to it. The
   owner accepted the direction while stating plainly they do not yet know how
   it will look, so it is to be judged as written, and dropped without argument
   if it reads worse than the five manifests. **Not started.**

Out of scope, as declared at open: the addon set per target beyond replica
sizing; storage strategy for the container target; any change to
`talos-toolchain`. **The `talos-toolchain` boundary did not hold** — see
"Deviation from declared scope" below. It was not anticipated at open that
proving item 3 would require a real, from-scratch bootstrap, or that doing
so would surface bugs blocking that bootstrap entirely.

## Acceptance criteria

- `validate-argocd-revisions.sh` accepts `environments/lab-container` pinning
  `lab`, still rejects a genuine mixed revision, and its test suite proves the
  previous validator rejected the new case. **Met.**
- `environments/lab` and `environments/main` behave exactly as before, since a
  name without a dash is its own stage. **Met** — the real repository check
  passes unchanged.
- The container environment's Argo CD reaches a steady state on the local
  cluster: no `Pending` pods from anti-affinity, no restart churn on
  `argocd-server`. **Met — proven by a full from-scratch bootstrap, not just
  an in-place upgrade.** The owner correctly rejected the first verification
  attempt (an `install-addon --allow-argocd-managed` upgrade of an
  already-running cluster) as insufficient: it proved the values render
  correctly, not that the documented day-2 procedure works on a cluster that
  never had `environments/lab`'s original config. Re-verified by destroying
  `talos-lab`, recreating day-1 from `lab` branch (talosctl default 2GiB/node
  — see below), then running day-2 exactly as `day2-operations.md` §2
  documents for the container target. Result: 7/7 Argo CD pods `Running`,
  0 restarts, stable 5+ minutes.
- Every addon change needs to be made once, not once per target. **Holds for
  the target actually built**: `argocd/root-app.yaml` and the four child
  Applications are not duplicated, only Argo CD's own sizing is. Not
  demonstrated for a hypothetical target needing its own addon config —
  that's what item 5 would need to improve on.

## Deviation from declared scope: two `talos-toolchain` fixes were required

The from-scratch bootstrap above failed twice before it passed, on causes
unrelated to `lab-container`'s own values, both now fixed in
`talos-toolchain` (commit history there has the details):

1. **`validate-cilium-handoff.sh` blocked day-1 entirely.** It compared
   day-1's `chart: oci://quay.io/cilium/charts/cilium` against the GitOps
   Application's `repoURL: quay.io/cilium/charts` + `chart: cilium` as raw
   strings. `talos-vsphere-gitops` commit `4116376` (already on `lab`,
   predates this iteration) deliberately dropped the `oci://` scheme from the
   Application's `repoURL` for an unrelated reason (quay.io 401s on a
   malformed OCI reference otherwise) but never updated this validator to
   match, so every real day-1 bootstrap on `lab` as it stands today failed
   `chart mismatch` before installing anything. Fixed to strip the scheme
   from both sides before comparing; regression fixture added
   (`consistent-no-oci-scheme`).
2. **`local-cluster.sh` had no way to raise a node above talosctl's 2GiB
   default**, and the full lab addon set (cert-manager, Cilium, Longhorn,
   kube-prometheus-stack, Argo CD) installed together on a fresh cluster
   needs more: at 2GiB the worker sustained ~99% memory, ~200% CPU, `kubelet`
   flapped `Ready`, `argocd-server` restarted repeatedly — a resource
   symptom, not a `lab-container` values problem, but one the isolated
   `install-addon` verification (see above) never would have surfaced.
   Added `--memory-controlplanes`/`--memory-workers`/`--cpus-controlplanes`/
   `--cpus-workers` passthrough flags (all optional, talosctl's own defaults
   unchanged when omitted). `--memory-workers=6GB --memory-controlplanes=4GB
   --cpus-workers=4.0 --cpus-controlplanes=2.0` resolved it; worker memory
   settled around 45%.

Both are documented in `talos-toolchain/docs/en/local-cluster.md` (+ PT-BR)
and cross-linked from this repo's `day2-operations.md` §1 and §3.

## Live-cluster state to unwind

Two changes were made directly to the running cluster while diagnosing, and
neither is in this repository:

- `helm upgrade --set redis-ha.enabled=false` on the `argocd` release.
- `kubectl scale` to 1 replica for `argocd-server`, `argocd-repo-server`,
  `argocd-applicationset-controller`.

Both are diagnosis, not solution. A `helm upgrade` from repository values undoes
both. They belong in the container environment's values, which is item 3.

**Update (this session):** both are now committed in
`environments/lab-container/helm/argocd/values.yaml`. The live cluster itself
still carries the raw out-of-band `helm upgrade --set` and `kubectl scale`,
not a `helm upgrade` from this file — that reconciliation step (e.g.
`talos-gitops.sh install-addon --addon=argocd
--helm-manifest-dir=.../environments/lab-container/helm`) has not been run
yet.
