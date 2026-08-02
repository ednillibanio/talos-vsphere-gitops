# Branch/Revision Promotion (EN)

## Contract

Every environment directory under `environments/` selects its own Git
revision, and that revision is checked into every Argo CD source that points
back at this repository:

- `environments/lab/**` -> `targetRevision: lab`
- `environments/main/**` -> `targetRevision: main`

This applies to the root `Application` (`environments/<env>/argocd/root-app.yaml`)
and to every child `Application` in `environments/<env>/argocd/apps/*.yaml`
(the source entry with `ref: values`, i.e. this Git repository, not the
external Helm chart source). The revision is never inferred from the branch
Argo CD happens to be checked out on — it is an explicit field, so a stale
`main` reference inside `environments/lab` (or vice versa) is a manifest bug,
not an environment choice.

## Validating offline

`scripts/validate-argocd-revisions.sh` scans `environments/<env>/argocd/**`
for any source whose `repoURL` points at this repository and fails if its
`targetRevision` does not match the environment directory name. It requires
no live Argo CD, Kubernetes, or Helm access.

```bash
./scripts/validate-argocd-revisions.sh
```

Run `scripts/validate-argocd-revisions.test.sh` to confirm the validator
itself still passes a consistent fixture and fails a mixed-revision one:

```bash
./scripts/validate-argocd-revisions.test.sh
```

## Promoting `lab` to `main`

1. Copy `environments/lab/` to `environments/main/`, preserving structure
   (`argocd/root-app.yaml`, `argocd/apps/*.yaml`, `helm/<addon>/*`).
2. In every copied file, change `targetRevision: lab` to `targetRevision: main`
   for sources pointing at this repository. Leave external chart
   `targetRevision` values (chart versions) untouched — only bump those
   deliberately, independent of promotion.
3. Update `path:` fields in root/child Applications from `environments/lab/...`
   to `environments/main/...`.
4. Run `./scripts/validate-argocd-revisions.sh` and confirm it reports `OK`.
5. Open a PR targeting `main` with the new `environments/main/` tree; do not
   hand-edit `environments/lab/` as part of the same change unless the lab
   contract itself changed.
