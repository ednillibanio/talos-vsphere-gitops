# Ambientes: Estagio e Alvo (PT-BR)

Esta e a explicacao canonica do que um diretorio `environments/<nome>`
significa, por que ele tem esse nome, e como adicionar um novo. Todo o resto
que toca o nome de ambiente (`branch-revision-promotion.md`,
`values-ownership.md`, `day2-operations.md`) aponta de volta para aqui quanto
ao modelo, e cobre sua propria fatia mais estreita (fixacao de branch,
ownership de valores, comandos de day-2) em profundidade.

## Os dois eixos

Todo ambiente responde a duas perguntas independentes, e este repositorio
historicamente misturou as duas em um unico diretorio:

- **Estagio** — onde isso esta no caminho de promocao? `lab` e promovido para
  `main`; um `staging` no meio ficaria antes do `main` tambem. Promocao
  significa um pull request de um branch para o proximo, carregando mudancas
  revisadas adiante.
- **Alvo** — em qual infraestrutura esse estagio de fato roda? Um cluster
  container (Docker/Colima, para iteracao local rapida) e um cluster vSphere
  (para testes reais, mais profundos) podem estar rodando o **mesmo
  estagio** — o mesmo estado desejado, as mesmas versoes de addon — ao mesmo
  tempo, em hardware diferente. Um alvo nunca e promovido; ele so nomeia onde
  um estagio esta implantado.

Confundir os dois costumava forcar um branch por escolha de infraestrutura, o
que tornava cada correcao de addon uma tarefa em dois branches. A correcao foi
parar de codificar o alvo no branch e passar a codifica-lo somente no nome do
diretorio.

## O contrato

Um diretorio de ambiente se chama `<estagio>[-<alvo>]`. Tudo **ate o primeiro
traco** e o estagio e fixa o `targetRevision` do Argo CD (o branch Git); tudo
depois dele e o alvo e nao afeta o branch de forma alguma.

```
environments/lab              estagio=lab   alvo=(nenhum)     -> targetRevision: lab
environments/lab-container     estagio=lab   alvo=container    -> targetRevision: lab
environments/lab-vsphere       estagio=lab   alvo=vsphere      -> targetRevision: lab
environments/main              estagio=main  alvo=(nenhum)     -> targetRevision: main
environments/staging-vsphere   estagio=staging alvo=vsphere    -> targetRevision: staging
```

Um nome sem traco e o proprio estagio, com um "sem divisao de alvo ainda"
implicito — e por isso que `environments/lab` e `environments/main` continuam
funcionando exatamente como antes de alvos existirem.

### Exemplo concreto: o roadmap real deste workspace

Isto nao e um grid hipotetico. E o formato ja em uso ou planejado:

| Diretorio | Estagio | Alvo | Branch | Status |
| --- | --- | --- | --- | --- |
| `environments/lab` | `lab` | (nenhum, historicamente com cara de vsphere) | `lab` | ativo hoje |
| `environments/lab-container` | `lab` | container (Docker/Colima) | `lab` | ativo hoje |
| `environments/lab-vsphere` | `lab` | vsphere | `lab` | ainda nao criado — ver "Questao em aberto" abaixo |
| `environments/staging` (futuro) | `staging` | vsphere | `staging` | pre-producao; promovido de `lab`, vira `main` se se sustentar |
| `environments/main` (futuro) | `main` | vsphere | `main` | producao |
| um futuro alvo `-eks` | qualquer estagio | eks | branch daquele estagio | nao planejado, mas o contrato ja suporta — e so mais um sufixo |

`lab-container` e `lab-vsphere` compartilham o branch `lab` de proposito: sao
o mesmo estado desejado em hardware diferente, entao uma correcao de addon
entra uma vez e os dois alvos a pegam no proximo sync. `staging` e `main` serao
cada um seu proprio branch, porque promover `staging` para `main` e exatamente
o tipo de mudanca que precisa passar por revisao — e isso que "estagio"
significa.

## O mecanismo: como o Argo CD de fato resolve isso

Nao existe um campo separado de estagio/alvo em lugar nenhum do Argo CD. O
contrato e imposto inteiramente atraves de tres campos simples em todo source
de `Application` que aponta para este repositorio:

- `repoURL` — este repositorio Git.
- `targetRevision` — o branch a fazer checkout. Este e o estagio.
- `path` (root app) ou o caminho do arquivo de valores `$values/...` (apps
  filhas) — o diretorio de onde ler. Este e o estagio **e** o alvo juntos,
  porque e o caminho completo `environments/<estagio>[-<alvo>]/...`.

Concretamente, em `environments/lab-container/argocd/apps/cilium.yaml`:

```yaml
sources:
  - repoURL: oci://quay.io/cilium/charts   # o proprio chart
    chart: cilium
    targetRevision: 1.19.1                 # versao do chart, nao relacionada ao estagio
    helm:
      valueFiles:
        - $values/environments/lab-container/helm/cilium/values.yaml
  - repoURL: https://github.com/ednillibanio/talos-vsphere-gitops.git
    targetRevision: lab                    # o ESTAGIO, nao "lab-container"
    ref: values
```

Dois campos `targetRevision` diferentes aparecem no mesmo arquivo por dois
motivos diferentes: o primeiro fixa a versao do chart externo, o segundo fixa
o branch deste repositorio. So o segundo e governado pelo estagio. Essa e uma
leitura equivocada comum — ver `branch-revision-promotion.md` se este arquivo
estiver sendo editado a mao.

## O que legitimamente varia por alvo, e o que nao varia

Alvo e sobre **capacidade e topologia**, nunca sobre intencao. Se dois alvos
querem um estado desejado genuinamente diferente — nao uma quantidade
diferente do mesmo estado — essa diferenca pertence a um estagio diferente,
nao a um alvo.

Medido ate agora (ver `docs/planning/execution/iteration-014.md` e
`day2-operations.md` para a evidencia completa):

| Preocupacao | Varia por alvo? | Onde mora |
| --- | --- | --- |
| `redis-ha` do Argo CD, contagem de replicas | **Sim** — `redis-ha` quer 3 replicas com anti-affinity entre nos; um cluster container com 1 CP + 1 worker so consegue agendar 1 | `environments/<estagio>-container/helm/argocd/values.yaml` vs. `environments/<estagio>/helm/argocd/values.yaml` |
| Configuracao de cert-manager, Cilium, Longhorn, prometheus-stack | **Nao, ainda nao** — nada medido ate agora precisa divergir | compartilhado: so existe `environments/<estagio>/helm/<addon>/*` e `environments/<estagio>/argocd/**`; alvos que nao precisam de copia propria simplesmente nao a recebem |
| Versoes de chart | Nao — versao e uma decisao do estagio inteiro, atualizada de forma deliberada e independente do alvo | `release.yaml` dentro da arvore do proprio estagio |
| Storage (Longhorn como alvo real) | Nao medido — container nao tem nenhum block device real; `addon-longhorn` fica `OutOfSync/Missing` la. Nao confirmado se e corrigivel so com valores | em aberto, ver `day2-operations.md` secao 3 |

E por isso que `environments/lab-container` hoje contem apenas
`helm/argocd/{release.yaml,values.yaml}` com valores redimensionados, copiados
sem alteracao de `environments/lab` — ele **nao** duplica
`argocd/root-app.yaml` nem `argocd/apps/*.yaml` para os quatro addons
gerenciados pelo Argo CD; o bootstrap de day-2 simplesmente instala o proprio
Argo CD de forma imperativa com os valores dimensionados para container, e
entao o root app e as apps filhas do proprio Argo CD reconciliam a partir da
arvore compartilhada `environments/lab` normalmente, ja que nada nessa arvore
e especifico de alvo ainda.

## Adicionando um alvo a um estagio existente

1. Confirme o que de fato diverge. Nao crie um diretorio de alvo por
   minuciosidade — crie um porque algo foi medido como nao agendavel, nao
   renderizavel, ou nao convergente naquela infraestrutura (ver a tabela
   acima).
2. Se so os valores Helm divergem (o caso comum ate agora):
   ```bash
   mkdir -p environments/<estagio>-<alvo>/helm/<addon>
   cp environments/<estagio>/helm/<addon>/release.yaml \
      environments/<estagio>-<alvo>/helm/<addon>/release.yaml
   # edite environments/<estagio>-<alvo>/helm/<addon>/values.yaml a mao —
   # nao copie o values.yaml de origem literalmente, dimensione para o alvo
   ```
   Nada em `argocd/` precisa de copia. `targetRevision: <estagio>` nunca foi
   tocado, entao `validate-argocd-revisions.sh` nao precisa de excecao.
3. Se o estado desejado inteiro precisa divergir — todo addon, nao so
   dimensionamento — copie o diretorio de estagio completo (ver "Adicionando
   um ambiente completo" abaixo) com o sufixo de alvo, e espere manter os
   manifests de Application do Argo CD duas vezes. Essa e uma decisao maior,
   deixe isso explicito no registro da iteracao antes de fazer.
4. Rode os validadores offline antes de abrir um PR:
   ```bash
   ./scripts/validate-values-overrides.sh environments/<estagio>-<alvo>/helm
   ./scripts/validate-argocd-revisions.sh
   ./scripts/validate-cilium-adoption-readiness.sh   # se o alvo tiver seu proprio cilium.yaml
   ```
5. Documente o comando de bootstrap de day-2 para o novo alvo se ele divergir
   do atalho existente `--manifest-root-dir=environments/<estagio>` (ver
   `day2-operations.md` secoes 2-3).

## Adicionando um novo estagio (promocao)

Este e o caminho de copia de diretorio completo, e e deliberado, nao um
contorno — ver `values-ownership.md` secao "Copying an environment" e
`docs/planning/execution/iteration-012.md` para o motivo de a resolucao de
`$values` do Argo CD (relativa a raiz do repositorio, nao ao manifest) tornar
isso inevitavel hoje. Procedimento completo:
`branch-revision-promotion.md` secao "Promovendo `lab` para `main`".

## Limitacao conhecida: isso duplica quatro Applications por ambiente

Todo diretorio de ambiente carrega seu proprio `argocd/root-app.yaml` e
quatro `argocd/apps/*.yaml`, identicos byte a byte a outro ambiente exceto
pelo caminho e branch embutidos. A iteracao 12 confirmou que isso nao e
corrigivel por um refactor de caminho: o Argo CD resolve sources `$values` a
partir da raiz do repositorio, sem forma relativa ao manifest. A iteracao 14
deixou estacionada a alternativa — uma ApplicationSet com um generator que
templatiza o ambiente — como uma mudanca de design real que exige uma decisao
do dono, nao uma correcao imediata; ver
`docs/planning/execution/iteration-014.md` item 5. Ate isso acontecer,
adicionar um estagio significa editar cinco arquivos a mao; adicionar um alvo
geralmente nao, porque a maioria dos alvos ate agora so toca o
dimensionamento do proprio Argo CD.

## Questao em aberto: o proprio `environments/lab`

O root app do cluster ao vivo hoje aponta para `environments/lab`, que hoje
nao tem alvo rotulado mas tem cara de vSphere na pratica (seu ajuste de
`redis-ha` assume um cluster real multi-no). Se ele deveria ser renomeado para
`environments/lab-vsphere` por simetria com `lab-container`, ou permanecer
como o alvo "padrao" implicito, **nao esta decidido** — um rename toca o root
app ao vivo e nao e de graca. Ver
`docs/planning/execution/iteration-014.md` item 4.

## Relacionados

- Mecanica de branch/revisao e o procedimento de promocao:
  `branch-revision-promotion.md`
- Ownership de valores e por que o lado Argo CD nao pode ficar agnostico de
  caminho: `values-ownership.md`
- Comandos de day-2, limites medidos por alvo, e como acessar cada addon:
  `day2-operations.md`
- A medicao que deu inicio a isso: `docs/planning/execution/iteration-013.md`
- A historia deste modelo: `docs/planning/execution/iteration-014.md`
- A alternativa ApplicationSet estacionada: `docs/planning/execution/iteration-012.md`
