# Manual de operacao do day-2

Como executar o day-2, o que muda por destino e como acessar cada addon.

Tudo aqui foi medido contra um cluster vivo em 2026-08-07, nao deduzido dos
manifests. Onde algo nao foi confirmado, esta dito.

## 1. O pre-requisito que quebra todo o resto

O `local-cluster.sh` mantem um kubeconfig por cluster e **nunca altera o seu
`~/.kube/config`**. Esse isolamento e proposital, e tem uma consequencia: o
`kubectl` puro nao enxerga o cluster local, e qualquer contexto antigo de um
cluster anterior continua resolvendo — para uma porta morta.

Todo comando deste manual assume:

```bash
export KUBECONFIG=~/.local/state/talos-toolchain/local-clusters/<cluster>/kubeconfig
```

Se um comando falhar com `connection refused` ou travar, confira isto primeiro:

```bash
kubectl config current-context          # e o cluster que voce acha que e?
docker port <cluster>-controlplane-1 6443   # a porta que o cluster publica de fato
```

A porta publicada da API e atribuida na criacao e muda a cada create. Um
contexto que sobrou de um cluster anterior aponta para uma porta que nao existe
mais.

## 2. Executando o day-2

O day-2 vive no `talos-toolchain` e consome os manifests deste repositorio.

```bash
export KUBECONFIG=~/.local/state/talos-toolchain/local-clusters/talos-lab/kubeconfig
GITOPS=~/projects/alerr/talos-projects/talos-vsphere-gitops

# 1. Addons Helm de plataforma (Argo CD incluso; Cilium e excluido por design)
./scripts/talos/talos-gitops.sh install-platform-helm \
  --kube-context=admin@talos-lab \
  --kubeconfig=$KUBECONFIG \
  --manifest-root-dir=$GITOPS/environments/lab

# 2. Entrega para o Argo CD
./scripts/talos/talos-gitops.sh deploy-argocd-root-app \
  --kube-context=admin@talos-lab \
  --kubeconfig=$KUBECONFIG \
  --manifest-root-dir=$GITOPS/environments/lab
```

O `configure-talos-cluster-tools` executa os dois em um passo. Use `--dry-run`
em qualquer um deles para ver os comandos exatos sem executar.

### Propriedade: o que voce pode e nao pode instalar na mao

O Cilium e **excluido pelo sistema**: ele e instalado no day-1 e adotado pelo
Argo CD, nunca reinstalado de forma imperativa.

Todos os outros addons ficam protegidos assim que o Argo CD assume. Depois que
o root app e aplicado, uma instalacao imperativa e recusada:

```
Argo CD Application 'addon-prometheus-stack' already manages this addon.
```

Isso nao e burocracia. O Helm nao consegue adotar objetos criados pelo Argo CD —
ele falha com `invalid ownership metadata ... missing key
app.kubernetes.io/managed-by` no meio do caminho e deixa um release parcial
para tras. **Mude o estado desejado neste repositorio.** O
`--allow-argocd-managed` ignora a protecao se voce tiver um motivo especifico.

## 3. Perfis por destino

Os mesmos manifests deveriam servir um cluster local em container e um no
vSphere. As diferencas nao sao cosmeticas:

| | Container (Docker/Colima) | vSphere |
| --- | --- | --- |
| Nos | 1 control-plane + 1 worker (o backend suporta exatamente 1 CP) | conforme provisionado |
| `redis-ha` | nao consegue agendar — veja abaixo | funciona |
| Storage de bloco | nenhum | alvo do Longhorn |
| LoadBalancer | nunca recebe endereco | Cilium L2/BGP, ou o VIP do HAProxy |
| Acessar um addon | so `port-forward` | Ingress / LoadBalancer; `port-forward` para depurar |
| Portas publicadas | fixadas na criacao, nao podem ser adicionadas depois | rede normal |

### Limites medidos no perfil container

- **O `redis-ha` nao consegue agendar.** O `argocd-redis-ha-server` e o
  Deployment do haproxy pedem 3 replicas com `podAntiAffinity` em
  `topologyKey: kubernetes.io/hostname`. Com 2 nos (um deles com taint) o
  resultado e `replicas=3 ready=1` nos dois, `Pending` permanente.

  A exigencia vem **deste repositorio**, nao do chart:
  `environments/lab/helm/argocd/values.yaml` define `redis-ha.enabled: true`. O
  default do proprio chart e um Redis simples, sem HA. Definir `false` foi
  verificado e resolve o caso container por completo — 14 pods com 3 Pending
  viraram 10 pods com 0 Pending.

- **O Longhorn nao converge.** O `addon-longhorn` fica `OutOfSync/Missing`,
  esperando o `batch/Job/longhorn-pre-upgrade`. A ausencia de dispositivos de
  bloco reais e a causa plausivel. **Isso nao foi confirmado** — nao repita
  como fato.

- **As portas publicadas sao fixadas na criacao.** O container do control-plane
  publica `6443` e `50000`; o worker nao publica nada. Quem define isso e o
  `talosctl cluster create`, e o Docker nao adiciona portas publicadas a um
  container em execucao. Um NodePort tambem ficaria dentro da VM do Colima, a um
  salto do host.

## 4. Acessando um addon

O `port-forward` **nao e exclusivo do container** — funciona em qualquer
destino, porque tunela pelo API server. No perfil container ele e a unica
opcao; no vSphere ele e o caminho de depuracao, enquanto Ingress ou
LoadBalancer e o caminho normal.

Defina isto primeiro, em cada shell:

```bash
export KUBECONFIG=~/.local/state/talos-toolchain/local-clusters/talos-lab/kubeconfig
```

### Como o port-forward se comporta

Um forward e um processo, nao configuracao do cluster. Ele existe apenas
enquanto o comando roda, e a porta some no instante em que voce o encerra. Um
`curl` no mesmo terminal depois que o comando retornou vai sempre falhar com
`Failed to connect ... Couldn't connect to server`.

Ou mantenha o forward em uma aba propria e use o servico de outra, ou coloque
em segundo plano e encerre explicitamente:

```bash
kubectl -n argocd port-forward svc/argocd-server 18080:443 >/dev/null 2>&1 &
sleep 5
curl -k -o /dev/null -w "argocd: HTTP %{http_code}\n" https://127.0.0.1:18080/

pkill -f "port-forward svc/argocd-server"    # quando terminar
```

O navegador precisa do forward rodando durante toda a sessao. Avisos de
certificado autoassinado sao esperados — prossiga por cima deles.

### Argo CD

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 18080:443
# https://127.0.0.1:18080   usuario: admin
```

Apague o `argocd-initial-admin-secret` depois de definir uma senha real.

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
# http://127.0.0.1:13000   usuario: admin
```

### Alertmanager

```bash
kubectl -n kube-prometheus-stack port-forward \
  svc/kube-prometheus-stack-alertmanager 19093:9093
# http://127.0.0.1:19093
```

### Referencia

| Addon | Namespace | Service | Porta |
| --- | --- | --- | --- |
| Argo CD | `argocd` | `argocd-server` | 443 |
| Prometheus | `kube-prometheus-stack` | `kube-prometheus-stack-prometheus` | 9090 |
| Grafana | `kube-prometheus-stack` | `kube-prometheus-stack-grafana` | 80 |
| Alertmanager | `kube-prometheus-stack` | `kube-prometheus-stack-alertmanager` | 9093 |

Argo CD, Prometheus e Grafana foram verificados por esse caminho (`HTTP 200`).
O Alertmanager segue o mesmo padrao e nao foi testado separadamente.

## 5. Falhas que vale reconhecer

Todas aconteceram de verdade. Cada uma custou tempo porque a mensagem aponta
para outro lugar que nao a causa.

**`[apiVersion not set, kind not set]` em um render.** O `helm template` escreve
o progresso do pull OCI (`Pulled:` / `Digest:`) no stdout, antes do manifest.
Corrigido no `talos-toolchain`; se reaparecer, algo reintroduziu um
`helm template` sem filtro.

**`401 Unauthorized` de um registry de charts.** Quase certamente nao e
credencial. O quay.io responde 401 em vez de 404 para um caminho que nao existe,
entao uma URL de chart malformada parece falha de autenticacao. Um source Helm
do Argo CD **nao** deve levar o esquema `oci://` no `repoURL`, ou o Argo nunca
anexa o `chart` e pede um caminho inexistente.

**Uma Application diz `Healthy` mas nada esta sendo gerenciado.** O health
descreve os objetos que existem, que podem ter sido criados pelo day-1. Olhe o
`.status.sync.status`; `Unknown` significa que o Argo CD nem conseguiu carregar
o estado desejado.

**Um recurso `OutOfSync` permanente depois de um sync bem-sucedido.** Algo no
chart e gerado a cada render. O `cilium-ca` e o `hubble-server-certs` sao
tratados com `ignoreDifferences`; um caso novo precisa do mesmo tratamento, ou
o `selfHeal` vai reescreve-lo para sempre.

**`invalid ownership metadata` durante um install do Helm.** O Argo CD ja e dono
daqueles objetos. Veja a secao de propriedade, acima.

## Relacionados

- Contrato de values: `values-ownership.md`
- Adocao do Cilium: `cilium-adoption.md`
- Fixacao de branch e revisao: `branch-revision-promotion.md`
- Evidencias de tudo que foi medido aqui:
  `../planning/execution/iteration-013.md`
