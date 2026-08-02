# Promocao de Branch/Revisao (PT-BR)

## Contrato

Cada diretorio de ambiente em `environments/` seleciona sua propria revisao
Git, e essa revisao fica registrada em todo source do Argo CD que aponta de
volta para este repositorio:

- `environments/lab/**` -> `targetRevision: lab`
- `environments/main/**` -> `targetRevision: main`

Isso vale para a `Application` raiz (`environments/<env>/argocd/root-app.yaml`)
e para cada `Application` filha em `environments/<env>/argocd/apps/*.yaml`
(a entrada de source com `ref: values`, ou seja, este repositorio Git, e nao
o source externo do chart Helm). A revisao nunca e inferida a partir do
branch em que o Argo CD esta com checkout no momento — e um campo explicito,
entao uma referencia `main` esquecida dentro de `environments/lab` (ou o
inverso) e um bug de manifest, nao uma escolha de ambiente.

## Validando offline

`scripts/validate-argocd-revisions.sh` percorre `environments/<env>/argocd/**`
em busca de qualquer source cujo `repoURL` aponte para este repositorio e
falha se o `targetRevision` nao corresponder ao nome do diretorio de
ambiente. Nao requer acesso a um Argo CD, Kubernetes ou Helm em execucao.

```bash
./scripts/validate-argocd-revisions.sh
```

Execute `scripts/validate-argocd-revisions.test.sh` para confirmar que o
proprio validador continua aprovando uma fixture consistente e reprovando
uma fixture com revisao mista:

```bash
./scripts/validate-argocd-revisions.test.sh
```

## Promovendo `lab` para `main`

1. Copie `environments/lab/` para `environments/main/`, preservando a
   estrutura (`argocd/root-app.yaml`, `argocd/apps/*.yaml`,
   `helm/<addon>/*`).
2. Em cada arquivo copiado, altere `targetRevision: lab` para
   `targetRevision: main` nos sources que apontam para este repositorio.
   Nao altere os valores de `targetRevision` dos charts externos (versoes de
   chart) — atualize-os separadamente, de forma deliberada e independente da
   promocao.
3. Atualize os campos `path:` nas Applications raiz/filhas de
   `environments/lab/...` para `environments/main/...`.
4. Execute `./scripts/validate-argocd-revisions.sh` e confirme que o
   resultado e `OK`.
5. Abra um PR direcionado a `main` com a nova arvore `environments/main/`;
   nao edite `environments/lab/` manualmente na mesma mudanca, a menos que o
   contrato do lab em si tenha mudado.
