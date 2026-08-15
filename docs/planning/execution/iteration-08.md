# Iteration 08 — Argo CD revision consistency

- Status: `PLAN APPROVED — awaiting Claude implementation authorization`
- Repository: `talos-vsphere-gitops`
- Issue: [#5](https://github.com/ednillibanio/talos-vsphere-gitops/issues/5)
- Branch: `fix/issue-008-gitops-revisions`

## Contract

The checked-in environment selects its own Git revision: `lab → lab` and
`main → main`. The root Application and every child Application source using
this Git repository must agree; no branch may be inferred from the current
checkout.

## Scope and acceptance

- Correct manifests only in this GitOps repository.
- Add an offline fixture validator that detects mixed environment revisions.
- Pair EN/PT-BR promotion documentation.
- Do not contact a live Argo/Kubernetes cluster or alter charts/values.
