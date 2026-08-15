# Propriedade dos Valores Helm (PT-BR)

## O contrato

Todo `environments/<env>/helm/<addon>/values.yaml` neste repositorio e um
**conjunto de overrides proprios**: ele lista apenas as chaves em que aquele
ambiente diverge intencionalmente dos defaults do proprio chart. Todas as
demais chaves caem no default embutido do chart no momento do render.

Um arquivo de valores nunca deve ser uma copia vendorizada do `values.yaml`
padrao do chart, e nenhum `values.base.yaml` deve ficar ao lado dele.

## Por que

Uma copia vendorizada esconde a intencao. Antes deste contrato ser aplicado a
todo o repositorio:

| Addon | Tamanho do `values.yaml` | Overrides reais |
| --- | --- | --- |
| `cert-manager` | 63.496 bytes | **2 linhas** (`installCRDs`, `crds.enabled`) |
| `prometheus-stack` | 191.908 bytes | **nenhum** — identico byte a byte aos defaults do chart |

Sao cerca de 255 KB de YAML para expressar duas linhas de decisao real.
Ninguem lendo aqueles arquivos conseguia distinguir o que o lab escolheu do
que o chart entregou, e uma atualizacao de chart congelaria silenciosamente
cada default nao revisado no valor antigo.

O `cilium` recebeu esse tratamento primeiro (iteracao 10); `cert-manager` e
`prometheus-stack` vieram depois. `argocd` e `longhorn` ja eram arquivos de
override pequenos, escritos a mao.

## O que fica onde

- **`values.yaml`** — apenas as divergencias intencionais do ambiente, cada
  uma com um comentario `# --` dizendo *por que*.
- **`release.yaml`** — chart, versao fixada, nome do release, namespace,
  seletor de validacao e os rotulos de Pod Security do namespace. Identidade e
  alvo, nao ajuste fino.

O `release.yaml` referencia seu arquivo de valores **relativo ao proprio
diretorio**:

```yaml
valuesFile: values.yaml
```

Nunca `environments/<env>/helm/<addon>/values.yaml`. Um arquivo que repete a
propria localizacao embute o nome do ambiente no conteudo, e e isso que faz
`cp -r environments/lab environments/prod` gerar release files quebrados. Os
dois consumidores de day-1 resolvem a forma relativa nativamente.

## Copiando um ambiente

A metade Helm sai de graca:

```bash
cp -r environments/lab environments/prod
./scripts/validate-values-overrides.sh environments/prod/helm
```

A metade do Argo CD nao, e isso e uma limitacao real, nao um descuido. O Argo
CD resolve `valueFiles` sob uma fonte `$ref` a partir da **raiz do repositorio**
de valores, sem semantica de "relativo a este manifesto", entao
`$values/environments/<env>/helm/<addon>/values.yaml` nao pode ser encurtado.
O `targetRevision` e o `path` do root app sao acoplados ao ambiente pelo
contrato deliberado de branch por ambiente descrito em
`docs/pt-br/branch-revision-promotion.md`.

Ou seja, um ambiente novo ainda exige editar quatro Applications mais o root
app. Tornar isso automatico exige um ApplicationSet com generator — um modelo
de gerenciamento diferente, nao uma mudanca de caminho.

## Verificando

Dois validadores offline garantem isso. Nenhum contata cluster nem usa
credenciais; eles baixam o chart fixado do registry e renderizam.

```bash
# Todo addon: sem marcadores de vendorizacao, sem values.base.yaml, renderiza
./scripts/validate-values-overrides.sh
./scripts/validate-values-overrides.test.sh

# Cilium adicionalmente: toda chave de override documentada esta presente
./scripts/validate-cilium-values-overrides.sh
./scripts/validate-cilium-values-overrides.test.sh
```

Um chart que nao pode ser baixado e reportado como limitacao, nao como falha —
assim a checagem continua util offline. Um chart que *e* resolvido mas falha ao
renderizar com o arquivo de valores e uma falha real.

## Alterando um arquivo de valores

Prove o render, nao confie na leitura. Renderize antes e depois contra o chart
fixado e compare:

```bash
helm pull <chart> --version <fixada> --destination /tmp/charts
helm template <release> /tmp/charts/<chart>.tgz \
  --namespace <ns> -f <values.yaml> > /tmp/after.yaml
diff /tmp/before.yaml /tmp/after.yaml
```

Atencao: o `kube-prometheus-stack` gera uma senha aleatoria de admin do Grafana
a cada render, entao dois renders do *mesmo* arquivo diferem naquela linha e no
`checksum/secret` que depende dela. Exclua as duas antes de comparar, ou voce
vai perseguir uma diferenca que nao e sua.

## Pendencia conhecida

O `cert-manager/values.yaml` define tanto `installCRDs` quanto `crds.enabled`.
O chart marca `installCRDs` como depreciado em favor de
`crds.enabled`/`crds.keep`. Ambos foram mantidos porque era o que o arquivo
vendorizado anterior definia e os dois nao sao intercambiaveis no render.
Migrar para fora da chave depreciada e trabalho separado, com sua propria
prova de render.
