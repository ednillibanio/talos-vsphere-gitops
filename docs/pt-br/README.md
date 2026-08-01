# Indice de Documentacao (PT-BR)

Este e o ponto de entrada em Portugues (Brasil) para a documentacao GitOps.

## Objetivo do Repositorio

Este repositorio e o dono do estado desejado do Argo CD, da politica de
revisao por ambiente, dos servicos de plataforma e das cargas de trabalho
apos o bootstrap do Kubernetes. Ele:

- Mantem os manifests de plataforma do day-2 como fonte de verdade.
- E consumido pelo root app do Argo CD a partir da automacao do cluster.

## Estrutura Atual

- `environments/lab/argocd/root-app.yaml`
- `environments/lab/argocd/apps/*.yaml`
- `environments/lab/helm/<addon>/release.yaml`
- `environments/lab/helm/<addon>/values.yaml`

## Notas Operacionais

- O root app do Argo CD aponta para:
  - `environments/lab/argocd/apps`
- Os apps filhos e o ciclo de vida dos addons sao renderizados a partir deste
  repositorio.

## Marcos (Milestones)

- Milestone A no macOS: um cluster local pode ser inicializado e reconciliado
  atraves do `talos-toolchain` sem qualquer provisionamento VMware. Os
  manifests do Argo CD deste repositorio se aplicam da mesma forma
  independentemente de onde o cluster Kubernetes subjacente é executado.
- O provisionamento vSphere e a validacao de VIP sao um marco posterior,
  adiado, de responsabilidade do `provision-talos-vsphere`, e nao uma
  dependencia do trabalho local no macOS.

## Repositorios Relacionados

- CLI de ciclo de vida day-1/day-2 do Talos (CTL canonico do Talos):
  - `talos-toolchain`
- Integracao de provisionamento vSphere/ESXi:
  - `provision-talos-vsphere`
- Handoff de execucao entre repositorios:
  - `provision-talos-vsphere/docs/pt-br/cross-repo-handoff.md`
