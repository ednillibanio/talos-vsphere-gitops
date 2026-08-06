# Helm Values Ownership

## The contract

Every `environments/<env>/helm/<addon>/values.yaml` in this repository is an
**owned override set**: it lists only the keys where that environment
intentionally diverges from the chart's own defaults. Every other key falls
back to the chart's built-in default at render time.

A values file must never be a vendored copy of the chart's default
`values.yaml`, and no `values.base.yaml` should sit next to it.

## Why

A vendored copy hides intent. Before this contract was applied repo-wide:

| Addon | `values.yaml` size | Real overrides |
| --- | --- | --- |
| `cert-manager` | 63,496 bytes | **2 lines** (`installCRDs`, `crds.enabled`) |
| `prometheus-stack` | 191,908 bytes | **none at all** — byte-identical to the chart defaults |

That is roughly 255 KB of YAML expressing two lines of actual decision-making.
Nobody reading those files could tell what the lab had chosen versus what the
chart shipped, and a chart upgrade would silently pin every unreviewed default
at its old value.

`cilium` received this treatment first (iteration 10); `cert-manager` and
`prometheus-stack` followed. `argocd` and `longhorn` were already small,
hand-written override files.

## What lives where

- **`values.yaml`** — only the environment's intentional divergences, each
  with a `# --` comment saying *why*.
- **`release.yaml`** — chart, pinned version, release name, namespace,
  validation selector, and namespace Pod Security labels. Identity and
  targeting, not tuning.

## Verifying

Two offline validators enforce this. Both contact no cluster and use no
credentials; they pull the pinned chart from its registry and render it.

```bash
# Every addon: no vendoring markers, no leftover values.base.yaml, renders
./scripts/validate-values-overrides.sh
./scripts/validate-values-overrides.test.sh

# Cilium additionally: every documented owned-override key is present
./scripts/validate-cilium-values-overrides.sh
./scripts/validate-cilium-values-overrides.test.sh
```

A chart that cannot be pulled is reported as a limitation, not a failure — so
the check stays useful offline. A chart that *is* resolved but fails to render
with the values file is a real failure.

## Changing a values file

Prove the render, do not eyeball it. Render before and after against the
pinned chart and diff:

```bash
helm pull <chart> --version <pinned> --destination /tmp/charts
helm template <release> /tmp/charts/<chart>.tgz \
  --namespace <ns> -f <values.yaml> > /tmp/after.yaml
diff /tmp/before.yaml /tmp/after.yaml
```

Note that `kube-prometheus-stack` generates a random Grafana admin password on
every render, so two renders of the *same* file differ on that line and its
dependent `checksum/secret`. Exclude both before comparing, or you will chase
a difference that is not yours.

## Known follow-up

`cert-manager/values.yaml` sets both `installCRDs` and `crds.enabled`. The
chart marks `installCRDs` deprecated in favour of `crds.enabled`/`crds.keep`.
Both are kept because that is what the previous vendored file set and the two
are not interchangeable at render time. Migrating off the deprecated key is
separate work with its own render proof.
