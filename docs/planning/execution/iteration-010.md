# Iteration 10 — minimal Cilium GitOps overrides

- Status: `CLAUDE_COMPLETED — awaiting Codex review`
- Repository: `talos-vsphere-gitops`
- Branch: `refactor/iteration-010-minimal-cilium-values`

## Contract

Reduce `environments/lab/helm/cilium/values.yaml` from a vendored copy of the
Cilium 1.19.1 chart's own default values to a small, owned override file,
without changing the declared Cilium/Argo adoption contract (chart, version,
release identity, namespace, values-file path, Argo Application) or
contacting a live cluster.

## Scope and acceptance

- Replace `environments/lab/helm/cilium/values.yaml`'s content with only the
  keys where lab intentionally diverges from the chart's defaults; delete
  `values.base.yaml` once proven unreferenced.
- Add an offline regression test for the owned-override contract and a
  pinned-chart Helm render when Helm can resolve the chart.
- Update EN/PT-BR `cilium-adoption.md` with the values-file ownership model.
- No change to `talos-toolchain` or `provision-talos-vsphere`; no Kubernetes,
  Argo CD, Docker, Colima, Talos, VMware, or credential access.

## Implementation summary

- Diffed `values.base.yaml` (vendored chart defaults) against the prior
  `values.yaml` to enumerate every intentional lab override: direct
  Kubernetes API endpoint (`k8sServiceHost`/`k8sServicePort`), a reduced
  agent/clean-cilium-state capability set (no `SYS_MODULE`/`SYSLOG`),
  ingress controller enabled as cluster default with shared LB mode, Gateway
  API enabled with ALPN/appProtocol, WireGuard pod-to-pod encryption with
  node encryption and open strict-mode CIDRs, Kubernetes-managed IPAM,
  full kube-proxy replacement, and a disabled cgroup automount with an
  explicit `/sys/fs/cgroup` host root.
- Rewrote `environments/lab/helm/cilium/values.yaml` to declare only those
  keys, each with a one-line rationale comment; removed the now-unreferenced
  `values.base.yaml` after confirming via repo-wide grep that nothing
  (scripts, docs, fixtures) referenced it.
- Added `scripts/validate-cilium-values-overrides.sh` (checks the values file
  exists, carries none of the chart's generated vendoring marker, declares
  every documented override key, has no leftover `values.base.yaml`, and — if
  `helm` can resolve the pinned chart from the OCI registry — renders
  successfully against it) and
  `scripts/validate-cilium-values-overrides.test.sh` (a valid fixture, a
  vendoring-marker fixture, a missing-key fixture, a leftover-`values.base`
  fixture, plus the real lab file) under
  `scripts/testdata/cilium-values/{valid,vendored-marker,missing-key,
  leftover-base}/`.
- Updated `docs/en/cilium-adoption.md` and `docs/pt-br/cilium-adoption.md`
  with a "values-file ownership" section describing the override-only
  contract and the new validator.

### Rendered-output verification

Rendered the prior committed `values.yaml` and the new minimal file through
`helm template` against the pinned `oci://quay.io/cilium/charts/cilium`
chart version `1.19.1` and diffed the two manifests. The only differences
were: (1) randomly generated Hubble/operator TLS material, which `helm
template` regenerates non-deterministically on every run regardless of
values content, and (2) two ConfigMap keys (`debug-verbose`,
`nodeport-addresses`) that the prior vendored file rendered as explicit empty
strings only because it declared those keys with their default `null` value
— the chart's own templates gate them with `hasKey`, so a file that omits
them (matching a values-less render of the chart) simply doesn't emit them.
Both forms are behaviorally identical to Cilium; the minimal file matches
true chart-default rendering more closely than the vendored copy did. No
other rendered key, value, resource, or count differs.

### Commands run

- `bash scripts/validate-cilium-values-overrides.test.sh` — 5/5 assertions
  pass, including a live pinned-chart `helm template` render of the real
  `environments/lab/helm/cilium/values.yaml`.
- `bash -n scripts/validate-cilium-values-overrides.sh
  scripts/validate-cilium-values-overrides.test.sh` — clean.
- `shellcheck scripts/validate-cilium-values-overrides.sh
  scripts/validate-cilium-values-overrides.test.sh` — clean.
- `yq eval . environments/lab/helm/cilium/values.yaml` — valid YAML.
- `git diff --check` — clean.
- `bash scripts/validate-argocd-revisions.test.sh` — 2/2 assertions pass
  (pre-existing, unaffected).
- `bash scripts/validate-cilium-adoption-readiness.test.sh` — 4/4 assertions
  pass (pre-existing, unaffected).
- `bash scripts/validate-argocd-revisions.sh` — `OK`.
- `bash scripts/validate-cilium-adoption-readiness.sh` — `OK` (1 environment
  checked).
- `helm template cilium oci://quay.io/cilium/charts/cilium --version 1.19.1
  -n kube-system -f <old values.yaml | new values.yaml>` — both succeed;
  diffed as described above.

### Deviations / known limitations

- Helm chart resolution for the render check reaches the public
  `quay.io` OCI registry over the network (read-only chart pull, no
  authentication); it does not contact any cluster, Argo CD instance, or use
  any credential. If a future environment cannot reach that registry, the
  validator reports the exact retrieval failure and exits `0` rather than
  failing the values-file contract or substituting a live-cluster check.
- No Kubernetes, Argo CD, Docker, Colima, Talos, or VMware operation was
  performed or authorized.
- `talos-toolchain` and `provision-talos-vsphere` were not modified; their
  consumer relationship to this values file (rendered content used for day-1
  bootstrap and handoff validation) is unchanged since the chart, version,
  release identity, and values-file path are all unchanged.
