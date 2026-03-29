# Indice de Documentacao (PT-BR)

Este e o ponto de entrada em Portugues (Brasil) para a documentacao GitOps.

## Objetivo do Repositorio

- Manter os manifests de plataforma do day-2 como fonte de verdade.
- Ser consumido pelo root app do Argo CD a partir da automacao do cluster.

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

## Repositorios Relacionados

- Bootstrap/integracao day-1:
  - `talos-vsphere-lab`
- Futuro toolchain reutilizavel do Talos:
  - repositorio dedicado (em preparacao)
