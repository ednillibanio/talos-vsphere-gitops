# Talos vSphere GitOps

This repository is the GitOps source of truth for Talos cluster platform
applications.

Main scope:

- Argo CD app-of-apps manifests
- Helm release manifests and values by environment

## Layout

```text
environments/<env>/
├── argocd/
│   ├── root-app.yaml       # app-of-apps entrypoint
│   └── apps/               # one Application per addon
└── helm/<addon>/
    ├── release.yaml        # chart, pinned version, release identity, namespace
    └── values.yaml         # owned overrides only
```

## The values contract

`values.yaml` holds **only** the keys where the environment diverges from the
chart's own defaults — never a vendored copy of the chart's default values, and
never a `values.base.yaml` beside it. `release.yaml` references it relative to
its own directory (`valuesFile: values.yaml`), so it carries no environment
name in its content.

Read `docs/en/values-ownership.md` (or `docs/pt-br/`) before editing any values
file. It explains why, and how to prove a change with a before/after Helm
render instead of eyeballing it.

## Checks

All offline: no cluster, no credentials. They pull pinned charts from their
registries and render them.

```bash
./scripts/validate-values-overrides.sh          # every addon: no vendored copies, renders
./scripts/validate-values-overrides.test.sh
./scripts/validate-cilium-values-overrides.sh   # Cilium's documented override keys
./scripts/validate-cilium-values-overrides.test.sh
./scripts/validate-argocd-revisions.sh          # per-environment branch pinning
```

There is no CI workflow in this repository yet, so run these yourself before
opening a pull request.

## Adding an environment

The Helm half is a copy with no edits:

```bash
cp -r environments/lab environments/prod
./scripts/validate-values-overrides.sh environments/prod/helm
```

The Argo CD half still needs manual edits — four Applications plus the root
app — because Argo CD resolves `valueFiles` from the values repository root and
`targetRevision` is environment-coupled by design. See "Copying an environment"
in `docs/en/values-ownership.md` for why, and
`docs/planning/execution/iteration-012.md` for the parked ApplicationSet
alternative.

Documentation:

- English: `docs/en/README.md`
- Portuguese (Brazil): `docs/pt-br/README.md`
