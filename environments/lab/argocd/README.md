# ArgoCD Apps

## Purpose

This directory contains Argo CD manifests that move addon lifecycle ownership
from manual Helm execution to GitOps reconciliation.

## Structure

- `root-app.yaml`: app-of-apps entrypoint.
- `apps/*.yaml`: child `Application` resources for each addon.

## Apply

Create repository credentials first if using a private repository:

```bash
cp environments/lab/argocd/repo-secret.example.yaml /tmp/repo-secret.yaml
# Edit /tmp/repo-secret.yaml and replace sshPrivateKey.
# This step must be done by the operator. Do not commit real keys.
KUBECONFIG=/home/vagrant/.kube/config \
kubectl apply -f /tmp/repo-secret.yaml
```

Then apply app-of-apps:

```bash
KUBECONFIG=/home/vagrant/.kube/config \
kubectl apply -f environments/lab/argocd/root-app.yaml
```

## Notes

- Applications use Argo CD multi-source mode:
  - Source A: external Helm chart repository.
  - Source B: this Git repository (`ref: values`) for values files.
- Update `repoURL` or `targetRevision` if your repository address or branch
  differs from current defaults.
