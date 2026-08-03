# Contrato de Adocao do Cilium (PT-BR)

## Contrato

`environments/<env>/argocd/apps/cilium.yaml` (a Application `addon-cilium`)
adota um Helm release do Cilium ja em execucao, instalado de forma
imperativa, em vez de instalar um novo. O `talos-toolchain` faz o bootstrap
do Cilium no day-1 (antes de o Argo CD existir, porque o Cilium fornece o
CNI que tanto o Kubernetes quanto o Argo CD precisam) usando o mesmo chart,
versao do chart e arquivo de valores que este repositorio declara; veja
`docs/en/cilium-gitops-handoff.md` do `talos-toolchain` para o lado day-1
deste contrato.

A adocao e declarativa e verificada por prontidao, nao imperativa:

- **Mesma identidade de release Helm.** `helm.releaseName` e
  `destination.namespace` da Application precisam corresponder ao release
  criado pelo day-1, para que a primeira sincronizacao do Argo CD reconheca
  e assuma o release existente em vez de criar um segundo, conflitante.
- **Mesmo conteudo renderizado.** A fonte do chart (`repoURL` + `chart` +
  `targetRevision`) e o arquivo de valores referenciado
  (`$values/environments/<env>/helm/cilium/values.yaml`) precisam ser
  exatamente os que o day-1 renderizou, para que a primeira sincronizacao do
  Argo seja um diff vazio, e nao uma mudanca nao planejada em um CNI ativo.
- **Acordo de revisao de ambiente.** A fonte de referencia de valores (a
  fonte que aponta de volta para este repositorio) precisa fixar o
  `targetRevision` no nome do diretorio de ambiente (`lab` -> `lab`,
  `main` -> `main`), conforme `docs/pt-br/branch-revision-promotion.md`.
- **Politica de sincronizacao totalmente automatizada.**
  `syncPolicy.automated.prune` e `selfHeal` precisam ser ambos `true`, para
  que o Argo CD realmente reconcilie o Cilium dali em diante, em vez de
  deixa-lo em um estado de sincronizacao apenas manual.

## Validando a prontidao offline

`scripts/validate-cilium-adoption-readiness.sh` verifica cada
`environments/<env>/argocd/apps/cilium.yaml` presente neste repositorio
quanto as propriedades acima, sem acesso real a Argo CD, Kubernetes ou Helm:

```bash
./scripts/validate-cilium-adoption-readiness.sh
```

Execute `scripts/validate-cilium-adoption-readiness.test.sh` para confirmar
que o proprio validador ainda passa em uma fixture completa e falha em
fixtures sem o arquivo de valores, com politica de sincronizacao nao
automatizada, ou com revisao de ambiente divergente:

```bash
./scripts/validate-cilium-adoption-readiness.test.sh
```

Isso complementa `scripts/validate-argocd-revisions.sh` (que verifica o
acordo de revisao em toda Application de todo ambiente) com checagens de
prontidao de adocao especificas do Cilium, e complementa o
`validate-cilium-handoff.sh` do `talos-toolchain` (que compara adicionalmente
com o release day-1 realmente sincronizado no lado do toolchain).

## Sequencia de adocao

1. O `talos-toolchain` faz o bootstrap do Cilium no day-1 a partir dos
   valores de `environments/<env>/helm/cilium/` deste repositorio
   (`helm upgrade --install` imperativo).
2. O `talos-toolchain` executa `validate-cilium-handoff.sh` para confirmar
   que o release day-1 sincronizado ainda corresponde ao `cilium.yaml` deste
   repositorio antes de prosseguir.
3. O `talos-toolchain` faz o deploy do root app do Argo CD
   (`talos-gitops.sh deploy-argocd-root-app`).
4. A Application `addon-cilium` do Argo CD realiza sua primeira
   sincronizacao. Como a identidade do release, o chart, a versao e os
   valores ja correspondem, essa sincronizacao e um no-op (ou uma adocao de
   metadados benigna), nao uma reinstalacao.
5. A partir desse ponto, o Argo CD reconcilia o Cilium exclusivamente;
   nenhum repositorio ou script deve realizar outra instalacao imperativa do
   Cilium.

## Propriedade do arquivo de valores

`environments/<env>/helm/cilium/values.yaml` contem apenas os overrides
proprios deste lab — as chaves em que o estado desejado diverge
intencionalmente dos valores padrao do proprio chart do Cilium (por exemplo
`k8sServiceHost`/`k8sServicePort`, `ingressController`, `gatewayAPI`,
`encryption`, `ipam.mode`, `kubeProxyReplacement`, `cgroup`). Ele nao e, e nao
deve voltar a ser, uma copia vendorizada do `values.yaml` padrao completo do
chart: toda chave que este arquivo nao define cai de volta para o padrao
embutido no proprio chart no momento da renderizacao, da mesma forma que o
`helm upgrade --install` do day-1 e a renderizacao do Argo CD a resolvem.
`scripts/validate-cilium-values-overrides.sh` verifica esse contrato de forma
offline — que o arquivo ainda declara cada chave de override documentada, nao
carrega o marcador de vendorizacao "DO NOT EDIT" gerado pelo chart, e nao tem
um `values.base.yaml` residual ao lado — e renderiza o arquivo contra a
versao fixada do chart com `helm template` quando o Helm consegue resolver
esse chart a partir do registry (sem cluster ao vivo, sem credenciais).
Execute `scripts/validate-cilium-values-overrides.test.sh` para confirmar que
o proprio validador ainda passa em uma fixture minima e falha em uma que
carrega o marcador de vendorizacao, uma sem uma chave documentada, e uma com
um `values.base.yaml` residual.

## Rollback / recuperacao

Se a reconciliacao do Cilium falhar ou degradar a rede apos a adocao:

1. Nao recorra a uma reinstalacao imperativa. O `talos-gitops.sh` do
   `talos-toolchain` exclui `cilium` de forma fixa tanto de
   `install-platform-helm` quanto de `install-addon` uma vez que o Argo
   possui o release, justamente para evitar que uma segunda escrita Helm
   imperativa concorra com o loop de reconciliacao do Argo CD.
2. Corrija de forma declarativa neste repositorio: ajuste
   `environments/<env>/helm/cilium/values.yaml` ou o `targetRevision` do
   chart em `cilium.yaml`, e deixe o `syncPolicy.automated.selfHeal`
   reconciliar a mudanca.
3. Para reverter, faca `revert` do commit responsavel no branch do ambiente
   (`lab` ou `main`) em vez de editar manualmente o estado ao vivo do
   cluster; o `selfHeal` do Argo CD converge o cluster de volta ao manifest
   revertido, ultimo estado bom conhecido.
4. Execute novamente `validate-cilium-adoption-readiness.sh` (e, a partir do
   `talos-toolchain`, `validate-cilium-handoff.sh`) apos qualquer correcao ou
   rollback para confirmar que o contrato de adocao ainda vale antes de
   considerar o cluster saudavel novamente.
