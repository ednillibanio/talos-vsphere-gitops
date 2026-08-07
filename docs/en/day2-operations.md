# Day-2 operations manual

How to run day-2, what differs per target, and how to reach each addon.

Everything here was measured against a live cluster on 2026-08-07, not inferred
from the manifests. Where something is unverified, it says so.

## 1. The prerequisite that breaks everything else

`local-cluster.sh` keeps a per-cluster kubeconfig and **never modifies your
`~/.kube/config`**. That isolation is deliberate, and it has a consequence:
plain `kubectl` does not see the local cluster, and any stale context from an
older cluster still resolves — to a dead port.

Every command in this manual assumes:

```bash
export KUBECONFIG=~/.local/state/talos-toolchain/local-clusters/<cluster>/kubeconfig
```

If a command fails with `connection refused` or hangs, check this first:

```bash
kubectl config current-context          # is this the cluster you think it is?
docker port <cluster>-controlplane-1 6443   # the port the cluster actually publishes
```

The published API port is assigned at create time and changes on every create.
A context left over from a previous cluster will point at a port that no longer
exists.

## 2. Running day-2

Day-2 lives in `talos-toolchain` and consumes this repository's manifests.

```bash
export KUBECONFIG=~/.local/state/talos-toolchain/local-clusters/talos-lab/kubeconfig
GITOPS=~/projects/alerr/talos-projects/talos-vsphere-gitops

# 1. Platform Helm addons (Argo CD included; Cilium is excluded by design)
./scripts/talos/talos-gitops.sh install-platform-helm \
  --kube-context=admin@talos-lab \
  --kubeconfig=$KUBECONFIG \
  --manifest-root-dir=$GITOPS/environments/lab

# 2. Hand over to Argo CD
./scripts/talos/talos-gitops.sh deploy-argocd-root-app \
  --kube-context=admin@talos-lab \
  --kubeconfig=$KUBECONFIG \
  --manifest-root-dir=$GITOPS/environments/lab
```

`configure-talos-cluster-tools` runs both in one step. Add `--dry-run` to any of
them to see the exact commands without executing.

### Ownership: what you may and may not install by hand

Cilium is **system-excluded**: it is bootstrapped in day-1 and adopted by Argo
CD, never reinstalled imperatively.

Every other addon is protected once Argo CD owns it. After the root app is
deployed, an imperative install is refused:

```
Argo CD Application 'addon-prometheus-stack' already manages this addon.
```

This is not bureaucracy. Helm cannot adopt objects Argo CD created — it fails
with `invalid ownership metadata ... missing key app.kubernetes.io/managed-by`
partway through and leaves a partial release behind. **Change desired state in
this repository instead.** `--allow-argocd-managed` overrides it if you have a
specific reason.

## 3. Target profiles

The same manifests are meant to serve a container-backed local cluster and a
vSphere one. They differ in ways that are not cosmetic:

| | Container (Docker/Colima) | vSphere |
| --- | --- | --- |
| Nodes | 1 control-plane + 1 worker (backend supports exactly 1 CP) | as provisioned |
| `redis-ha` | cannot schedule — see below | works |
| Block storage | none | Longhorn's target |
| LoadBalancer | never gets an address | Cilium L2/BGP, or the HAProxy VIP |
| Reaching an addon | `port-forward` only | Ingress / LoadBalancer, `port-forward` for debugging |
| Published ports | fixed at cluster create, cannot be added later | normal networking |

### Measured limits on the container profile

- **`redis-ha` cannot schedule.** `argocd-redis-ha-server` and its haproxy
  Deployment both want 3 replicas with `podAntiAffinity` on
  `topologyKey: kubernetes.io/hostname`. With 2 nodes (one tainted) the result
  is `replicas=3 ready=1` for both, permanently `Pending`.

  The requirement comes from **this repository**, not from the chart:
  `environments/lab/helm/argocd/values.yaml` sets `redis-ha.enabled: true`. The
  chart's own default is a single non-HA Redis. Setting it to `false` was
  verified to resolve the container case completely — 14 pods with 3 Pending
  became 10 pods with 0 Pending.

- **Longhorn does not converge.** `addon-longhorn` stays `OutOfSync/Missing`,
  waiting on `batch/Job/longhorn-pre-upgrade`. The absence of real block devices
  is the plausible cause. **This is not confirmed** — do not repeat it as fact.

- **Published ports are fixed at create.** The control-plane container publishes
  `6443` and `50000`; the worker publishes nothing. `talosctl cluster create`
  sets this, and Docker cannot add published ports to a running container. A
  NodePort would also sit inside the Colima VM, one hop from the host.

## 4. Reaching an addon

`port-forward` is **not container-specific** — it works on any target, because
it tunnels through the API server. On the container profile it is the only
option; on vSphere it is the debugging path while Ingress or LoadBalancer is
the normal one.

Set this first, in every shell:

```bash
export KUBECONFIG=~/.local/state/talos-toolchain/local-clusters/talos-lab/kubeconfig
```

### How port-forward behaves

A forward is a process, not cluster configuration. It exists only while the
command runs, and the port disappears the moment you stop it. `curl` in the
same terminal after the command returned will always fail with
`Failed to connect ... Couldn't connect to server`.

Either keep it in its own tab and use the service from another, or background
it and stop it explicitly:

```bash
kubectl -n argocd port-forward svc/argocd-server 18080:443 >/dev/null 2>&1 &
sleep 5
curl -k -o /dev/null -w "argocd: HTTP %{http_code}\n" https://127.0.0.1:18080/

pkill -f "port-forward svc/argocd-server"    # when you are done
```

A browser needs the forward running for the whole session. Self-signed
certificate warnings are expected — proceed past them.

### Argo CD

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 18080:443
# https://127.0.0.1:18080   user: admin
```

Delete `argocd-initial-admin-secret` once you have set a real password.

### Prometheus

```bash
kubectl -n kube-prometheus-stack port-forward \
  svc/kube-prometheus-stack-prometheus 19090:9090
# http://127.0.0.1:19090
```

### Grafana

```bash
kubectl -n kube-prometheus-stack get secret kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo
kubectl -n kube-prometheus-stack port-forward \
  svc/kube-prometheus-stack-grafana 13000:80
# http://127.0.0.1:13000   user: admin
```

### Alertmanager

```bash
kubectl -n kube-prometheus-stack port-forward \
  svc/kube-prometheus-stack-alertmanager 19093:9093
# http://127.0.0.1:19093
```

### Reference

| Addon | Namespace | Service | Port |
| --- | --- | --- | --- |
| Argo CD | `argocd` | `argocd-server` | 443 |
| Prometheus | `kube-prometheus-stack` | `kube-prometheus-stack-prometheus` | 9090 |
| Grafana | `kube-prometheus-stack` | `kube-prometheus-stack-grafana` | 80 |
| Alertmanager | `kube-prometheus-stack` | `kube-prometheus-stack-alertmanager` | 9093 |

Argo CD, Prometheus and Grafana were verified reachable this way (`HTTP 200`).
Alertmanager follows the same pattern and was not separately curled.

## 5. Failures worth recognising

These all happened for real. Each wasted time because the message points
somewhere other than the cause.

**`[apiVersion not set, kind not set]` on a render.** `helm template` writes OCI
pull progress (`Pulled:` / `Digest:`) to stdout ahead of the manifest. Fixed in
`talos-toolchain`; if you see it again, something reintroduced an unfiltered
`helm template`.

**`401 Unauthorized` from a chart registry.** Almost certainly not credentials.
quay.io answers 401 rather than 404 for a path that does not exist, so a
malformed chart URL looks like an auth failure. An Argo CD Helm source must not
carry the `oci://` scheme in `repoURL`, or Argo never appends `chart` and
requests a path that does not exist.

**An Application says `Healthy` but nothing is managed.** Health describes the
objects that exist, which may have been created by day-1. Check
`.status.sync.status`; `Unknown` means Argo CD could not even load the target
state.

**A permanently `OutOfSync` resource after a successful sync.** Something in the
chart is generated per render. Cilium's `cilium-ca` and `hubble-server-certs`
are handled with `ignoreDifferences`; a new one needs the same treatment, or
`selfHeal` will rewrite it forever.

**`invalid ownership metadata` during a Helm install.** Argo CD already owns
those objects. See ownership, above.

## Related

- Values contract: `values-ownership.md`
- Cilium adoption: `cilium-adoption.md`
- Branch and revision pinning: `branch-revision-promotion.md`
- Evidence for everything measured here:
  `../planning/execution/iteration-013.md`
