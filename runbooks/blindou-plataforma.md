# Plataforma isolada do Blindou

## Estado e limite

Este runbook governa a fundação do Blindou no servidor `apiwpp`. A fundação
cria namespaces vazios e bloqueados, identidade de deploy, database vazio,
logins, TLS cliente, backup lógico criptografado e métricas da plataforma. A
fundação base não cria Secrets Kubernetes, não executa migrations e não publica
imagens. Uma etapa separada e explicitamente autorizada pode liberar somente o
conector `cloudflared`, mantendo a aplicação em quarentena.

O PostgreSQL 18 continua sendo um processo compartilhado com o `apiwpp`, mas o
Blindou possui database, quatro logins, grupos `NOLOGIN`, CA cliente, certificado
e backup lógico próprios. O backup físico pgBackRest continua cobrindo o cluster
PostgreSQL inteiro; ele não substitui a cópia lógica isolada do Blindou.

## Autoridades e arquivos

- `/usr/local/sbin/blindou-hostctl`: contenção temporária do host;
- `/usr/local/sbin/blindou-deployctl`: única interface sem senha da plataforma
  Blindou;
- `/usr/local/lib/blindou-platform/`: manifests e verificador root-owned;
- `/etc/blindou/`: chaves, certificados, URLs e identidades root-only;
- `/var/lib/blindou-platform/`: estado e cache de releases assinadas;
- `/var/backups/blindou/`: backups locais root-only;
- `/home/apiadmin/blindou-deploy-inbox/<sha40>/`: entrada fechada de releases;
- `/home/apiadmin/blindou-backup-outbox/`: somente envelopes criptografados
  exportados para leitura.

A chave privada de assinatura e a chave privada de recuperação nunca entram no
servidor ou neste repositório. Somente a chave pública de assinatura e o
certificado público de recuperação são instalados.

## Instalação do controlador

Antes da instalação, validar no repositório:

```bash
operations/remote/verify-blindou-platform-artifacts.sh
operations/remote/verify-blindou-release-contract.sh /c/github/blindou
```

Transferir o commit limpo para um inbox exclusivo, conferir os hashes no host e
executar como `root`:

```bash
cd /home/apiadmin/<inbox-validado>/operations/remote
sudo ./bootstrap-blindou-deployctl.sh
```

O bootstrap instala arquivos com ownership fixo, valida Python/YAML, certificado,
assinante e sudoers, habilita apenas a coleta de métricas e termina consultando
o status. Ele não aplica namespaces nem dados.

## Fundação Kubernetes bloqueada

```bash
sudo -n /usr/local/sbin/blindou-deployctl \
  apply-foundation blindou-platform-foundation
sudo -n /usr/local/sbin/blindou-deployctl verify-foundation
```

O aceite exige:

- `blindou-production` e `blindou-edge` com gate `blocked`;
- zero Deployment, StatefulSet, DaemonSet, Job, CronJob, Pod, Service, Secret e
  PVC nos dois namespaces;
- quota zero para Pods, Services, Secrets e PVCs;
- ServiceAccount padrão sem token, Pod Security `restricted` e default deny;
- admissão recusando Pod enquanto bloqueado e recusando NodePort;
- nenhum processo ou workload `cloudflared`;
- `blindou-hostctl verify` e `apiwpp-deployctl verify` aprovados.

Rollback humano, somente enquanto os namespaces estiverem vazios:

```bash
sudo /usr/local/sbin/blindou-deployctl \
  rollback-foundation blindou-platform-foundation
```

O rollback restaura as políticas de admissão capturadas antes da aplicação e o
label anterior do nó. Ele recusa remover namespace que possua objeto operacional.

## Autenticação dos bootstraps Blindou

Os orquestradores versionados usam exclusivamente
`operations/Blindou.SudoBootstrap.psm1` para instalar ou atualizar os
controladores. O helper carrega `KEY_SERVIDOR` do `.env` ignorado na raiz deste
repositório, sem exibir seu conteúdo, e envia o valor apenas por `stdin` para
`sudo -S`. Ele fixa o host aprovado, o staging Blindou e os instaladores
`bootstrap-blindou-hostctl.sh` e `bootstrap-blindou-deployctl.sh`.

O helper não aceita comando `sudo` livre, outro host, rollback destrutivo ou
operação de outro projeto. O arquivo `.env` é temporário e deve ser apagado pelo
operador quando a atividade que depende da senha terminar. Token Cloudflare,
PAT GHCR e demais segredos continuam usando seus canais próprios e nunca podem
ser colocados nesse arquivo por conveniência.

## Conector Cloudflare isolado

No computador administrativo, executar:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\operations\Invoke-BlindouCloudflareConnector.ps1
```

O script atualiza o controlador pelo helper fechado, pede o token em campo
oculto e o envia somente pelo `stdin` do SSH. A senha e o token nunca entram em argumento,
arquivo local, Git ou log. O controlador grava diretamente o Secret
`blindou-edge/blindou-cloudflare-tunnel`, aplica a imagem imutável do
`cloudflared` e espera a réplica ficar disponível.

O gate `connector-only` admite exclusivamente um Pod chamado
`blindou-cloudflared`. A quota permite um Pod e um Secret, mas continua negando
Services e PVCs. `blindou-production` permanece `blocked`, vazio e com quotas
zero. A NetworkPolicy do conector libera somente DNS do cluster e TCP/7844 para
endereços públicos, sem destinos privados.

Verificação:

```bash
sudo -n /usr/local/sbin/blindou-deployctl verify-edge-connector
sudo -n /usr/local/sbin/blindou-deployctl verify-foundation
sudo -n /usr/local/sbin/apiwpp-deployctl verify
sudo -n /usr/local/sbin/blindou-hostctl verify
```

Se a primeira ativação falhar, o controlador remove automaticamente o Pod e o
Secret e restaura a quarentena `blocked`. O rollback humano é destrutivo para o
Secret e exige senha:

```bash
sudo /usr/local/sbin/blindou-deployctl \
  rollback-edge-connector blindou-edge-connector
```

Esse rollback não apaga o Tunnel no painel Cloudflare; apenas desconecta o
servidor. O token pode ser rotacionado ou revogado no Zero Trust.

## Credencial Cloudflare for SaaS

O API token que administra hostnames personalizados é diferente do token do
Tunnel. Ele deve conter somente `SSL and Certificates: Edit` na zona exata
`blindou.com`; não recebe DNS, Tunnel, Pages, conta ou billing. Para atualizar o
controlador e transferir o token sem argumento, arquivo local ou log:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\operations\Invoke-BlindouCloudflareSaasToken.ps1
```

O controlador valida que o token está ativo e consegue listar no máximo um
custom hostname da zona. Somente então grava `/etc/blindou/cloudflare-saas/api-token`
como `root:root 0600`, dentro de diretório `0700`. A credencial não entra no
Kubernetes, no banco, no RAG ou no Git nesta etapa. A presença do arquivo não
libera `blindou-production`, migration, release ou criação de hostname.

Verificação sem revelar valor ou hostnames:

```bash
sudo -n /usr/local/sbin/blindou-deployctl verify-cloudflare-saas-token
sudo -n /usr/local/sbin/blindou-deployctl status
```

O rollback só é permitido enquanto a aplicação estiver bloqueada e não existir
release corrente; ele exige a senha administrativa:

```bash
sudo /usr/local/sbin/blindou-deployctl \
  rollback-cloudflare-saas-token blindou-cloudflare-saas-token
```

Revogar o token no painel Cloudflare é uma etapa externa separada. Depois que o
runtime existir, rotação e revogação exigirão um fluxo próprio que preserve a
credencial anterior até a nova ser validada.

## Credencial privada do GHCR

As quatro imagens privadas do Blindou — backend, redirector, NATS endurecido e
`cloudflared` endurecido — ficam em `ghcr.io/GleisonSette`. Redis permanece na
imagem oficial aprovada por digest. O host
recebe um PAT classic exclusivo com exatamente `read:packages`. O controlador
recusa token de outro usuário ou que possua qualquer escopo adicional, inclusive
`repo`, `write:packages`, `delete:packages` ou `workflow`.

Criar o PAT pela sessão autenticada do GitHub sem copiar o valor para arquivo,
chat ou linha de comando. Depois, no computador administrativo, executar:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\operations\Invoke-BlindouGhcrPullCredential.ps1
```

O script atualiza o controlador pelo helper fechado, recebe o PAT em campo
oculto e o envia somente pelo `stdin` do SSH. O controlador valida identidade e
escopo na API oficial do GitHub e grava `/etc/blindou/ghcr/pull-token` como
`root:root 0600`, dentro de diretório `0700`. Nenhum Secret Kubernetes é criado
enquanto `blindou-production` permanecer bloqueado.

Verificação sem revelar o valor:

```bash
sudo -n /usr/local/sbin/blindou-deployctl verify-ghcr-pull-credential
sudo -n /usr/local/sbin/blindou-deployctl status
```

Durante uma release autorizada, depois que os gates e a quarentena forem
removidos, o controlador materializa `blindou-production/blindou-ghcr-pull` do
tipo `kubernetes.io/dockerconfigjson`. O Secret não faz parte do bundle assinado
e somente a `ServiceAccount` `blindou-runtime` pode referenciá-lo.

Rollback da credencial exige senha humana e só é aceito antes da primeira
release:

```bash
sudo /usr/local/sbin/blindou-deployctl \
  rollback-ghcr-pull-credential blindou-ghcr-pull-credential
```

Revogar o PAT no GitHub é uma ação externa separada. Por D015, o Rust é
compilado/testado no runner efêmero hospedado pelo GitHub e as imagens são
publicadas por `GITHUB_TOKEN` temporário. Esse pipeline não acessa o host; o
servidor conserva somente download.
Depois da primeira instalação, o controlador atual recusa a substituição por
outro token. A rotação pós-release exige fluxo próprio autorizado que valide a
nova credencial antes de retirar a anterior.

### Prova integral de pull antes da release

A validação de escopo do PAT não prova sozinha que os quatro pacotes privados da
candidata podem ser baixados. Antes de liberar o gate da aplicação, atualizar o
controlador pelo bootstrap versionado fechado e executar:

```bash
sudo -n /usr/local/sbin/blindou-deployctl \
  verify-ghcr-candidate-pull <release-id-sha40>
```

O comando aceita somente uma release já validada no cache root-owned, descobre
backend, redirector, NATS e `cloudflared` dentro do bundle e exige os quatro
repositórios fixos do Blindou.
A credencial é lida do cofre e entregue ao verificador por `stdin`; não entra em
argumento, ambiente, log ou arquivo temporário. O verificador desabilita proxies
herdados, autentica no GHCR, seleciona exclusivamente `linux/amd64`, baixa o
manifesto, config e todas as camadas, confere cada SHA-256 e limita tempo e
bytes. Redirecionamento de blob para outro host HTTPS perde o header de
autorização.

Os bytes ficam em `/var/tmp` somente durante a prova e são removidos mesmo em
falha. O host guarda apenas um recibo root-only sem credencial em
`/var/lib/blindou-platform/ghcr-pull-proofs/`. A operação não importa imagem no
containerd, não cria `blindou-ghcr-pull`, não altera gate e não inicia Pod. O
estado aparece em `status` e na métrica
`blindou_ghcr_candidate_pull_verified`.

No computador administrativo, o procedimento completo é:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\operations\Invoke-BlindouGhcrCandidatePullProof.ps1 `
  -ReleaseId <sha40> `
  -BundleDirectory <diretório-com-os-três-artefatos-assinados>
```

Esse script transfere no mesmo archive os artefatos versionados do controlador
e exatamente `release.manifest`, `release.manifest.sig` e `rendered.tar.gz`.
Ele carrega a senha temporária pelo helper fechado para o bootstrap, valida a
release no cache e usa depois apenas a interface sem senha fechada para
comprovar o pull. Ele não lê novamente o PAT.

## Fundação de dados

```bash
sudo -n /usr/local/sbin/blindou-deployctl \
  provision-data blindou-data-foundation
sudo -n /usr/local/sbin/blindou-deployctl verify-data
```

O provisionamento é idempotente e cria o database vazio `blindou`, quatro
logins sem privilégio administrativo e os grupos esperados pelas migrations. As
regras HBA exigem simultaneamente TLS, certificado emitido pela CA cliente do
Blindou e senha SCRAM. Nenhuma tabela da aplicação é criada nesta etapa.

Rollback de dados exige senha administrativa e só é aceito quando não existe
tabela de aplicação:

```bash
sudo /usr/local/sbin/blindou-deployctl \
  rollback-data blindou-empty-data-foundation
```

## Backup lógico criptografado

```bash
sudo -n /usr/local/sbin/blindou-deployctl \
  backup-database blindou-database-backup
sudo -n /usr/local/sbin/blindou-deployctl verify-backup
sudo -n /usr/local/sbin/blindou-deployctl export-latest-backup
```

O controlador cria um `pg_dump` custom com Zstandard, valida seu catálogo,
criptografa-o em envelope CMS AES-256-GCM para o certificado de recuperação e
remove o texto claro. O dump nasce em diretório aleatório `0700` sob `/var/tmp`
para que o usuário `postgres` não receba acesso de travessia ao diretório dos
backups criptografados. O trap do controlador remove esse staging também em
falha. A outbox expõe somente o envelope, o manifesto e o certificado público.
A prova de recuperação deve ocorrer fora do servidor com a chave privada
custodiada separadamente.

O orquestrador baixa o diretório fechado do backup em uma única conexão SCP e
depois exige exatamente o envelope, o manifesto e o certificado público, todos
regulares e sem link simbólico. Não abrir três conexões consecutivas: o SSH do
host pode limitar handshakes rápidos e deixar uma cópia local parcial.

Periodicidade, retenção, destino offsite, RPO, RTO e ensaio recorrente dependem
de D005/P005. Não apagar ou rotacionar backups por valor inferido.

## Release assinada

O controlador aceita somente um diretório cujo nome seja o SHA Git completo e
que contenha `release.manifest`, `release.manifest.sig` e `rendered.tar.gz`.
Assinatura, SHA-256, estado limpo, paths do archive, namespaces, kinds, nomes,
imagens por digest, exposição e baseline dos Pods são validados antes do cache
root-owned.

`validate-release` pode preparar o cache, mas `apply` continua bloqueado até os
dois gates estarem `passed`, a quarentena ter sido removida e todos os Secrets
obrigatórios existirem. Nesta fase não passar gates nem aplicar release.

### Primeira revisão da interface sem provedores

Por D019, o primeiro login não espera UAZAPI, Resend ou Pagar.me. A candidata
destinada a essa revisão deve declarar `INITIAL_UI_REVIEW_MODE=true`,
`UAZAPI_ENABLED=false`, `EMAIL_PROVIDER=disabled` e
`AUTH_REQUIRE_2FA=false`, omitir todas as credenciais desses provedores e conter
exatamente os 16 workers contínuos que não dependem de notificação externa.

Depois da prova integral da candidata e antes dos gates de release, preparar
somente as chaves internas e os Secrets técnicos:

```bash
sudo -n /usr/local/sbin/blindou-deployctl \
  provision-ui-review-runtime blindou-ui-review-runtime
```

Esse comando recusa executar se encontrar credencial UAZAPI ou Resend no cofre,
mantém Pagar.me ausente, cria a configuração fail-closed e registra um recibo
root-only do adiamento. O recibo substitui apenas a confirmação de alerta
externo durante essa revisão; prova GHCR, backup, cópia offsite, assinatura,
contenção e todos os demais gates continuam obrigatórios.

Em um host sem runtime anterior, o próprio controlador cria primeiro
`/etc/blindou/runtime` como `root:root` e modo `0700`; somente depois grava
`production.env` por arquivo temporário e instala as chaves internas. Não criar
esse diretório manualmente nem relaxar suas permissões para contornar falhas de
bootstrap.

O orquestrador `operations/Invoke-BlindouFirstRelease.ps1` executa a sequência
completa e solicita somente a senha do superadmin em campo protegido. Ele
aplica migrations e a release assinada, cria `gleisonsette@gmail.com` ativo e
verificado como `super_admin` e valida o login pela API pública sem imprimir
token. A configuração posterior de cada provedor exige nova autorização e uma
release compatível; não reutilizar o modo de revisão como estado operacional
definitivo.

O coletor de métricas usa o mesmo lock do controlador. Se ele vencer uma corrida
curta entre duas etapas, o orquestrador repete somente o retorno específico de
lock ocupado (`exit 2`), por no máximo 12 tentativas com intervalo de cinco
segundos. Gates e `apply` são comandos separados para que nenhum efeito
concluído entre em um retry ambíguo. Qualquer outro código interrompe a release
imediatamente.

O `apply` executa o corpo da release em subshell com `errexit` explicitamente
reativado e só então captura o código para decidir rollback. Não envolver
`apply_cached_release` diretamente em `if !`: Bash desabilita `errexit` também
nas funções chamadas nesse contexto e pode continuar após uma recusa do
Kubernetes.

O Job de migration é observado por estado terminal, não somente por
`Complete`. `Failed` encerra a espera imediatamente; ausência de estado
terminal continua limitada a 600 segundos. Antes do rollback, o controlador
emite as últimas linhas do único container `migrate` por um filtro que remove
URLs PostgreSQL e valores associados a senha, token, segredo ou chave privada.
Não substituir esse fluxo por espera exclusiva de `Complete`, pois um Job já
falho consumiria todo o timeout e perderia o diagnóstico ao ser removido.

`pg_stat_statements` é pré-requisito administrativo da fundação PostgreSQL. O
controlador o cria idempotentemente no database `blindou`, schema `public`,
sob o owner `postgres`, e verifica essa autoridade. A migration de aplicação
não pode criar nem comentar essa extensão, pois sua identidade permanece
corretamente sem superuser, `CREATEDB` ou `CREATEROLE`. Extensões confiáveis que
pertencem ao schema da aplicação continuam sob a migration.

Se uma versão anterior já carregada em memória permanecer presa depois de uma
falha de primeira release, não usar `sudo kill` nem editar objetos manualmente.
O controlador independente `blindou-release-emergencyctl` aceita somente
`contain-stuck-first-release <sha> blindou-stuck-first-release`: ele exige um
único holder root do lock cujo `cmdline` seja exatamente o `apply` daquele SHA,
encerra sua árvore, remove workloads e Services parciais, restaura
`secrets-only`/`connector-only` e confirma `current_release` ausente. Qualquer
divergência recusa a contenção.

## Observabilidade

`blindou-platform-metrics.timer` grava no textfile collector do Node Exporter:

- integridade da fundação Kubernetes;
- integridade da fundação de dados;
- timestamp do backup lógico mais recente;
- estado do gate de cada namespace;
- presença segura local da credencial Cloudflare for SaaS, sem testar ou expor
  seu valor no coletor;
- sucesso da própria coleta.

Falha de coleta produz uma métrica explícita com valor zero. Alertas externos
por Resend permanecem adiados durante D019 e o scrape dos workloads depende da
existência do runtime.
Como o controlador usa lock exclusivo, uma auditoria manual concorrente pode
fazer um ciclo do coletor falhar fechado em zero; o ciclo seguinte deve voltar
a um sem intervenção. Persistência em zero exige investigação.

## Verificação final desta etapa

```bash
sudo -n /usr/local/sbin/blindou-deployctl status
sudo -n /usr/local/sbin/blindou-deployctl verify-foundation
sudo -n /usr/local/sbin/blindou-deployctl verify-cloudflare-saas-token
sudo -n /usr/local/sbin/blindou-deployctl verify-data
sudo -n /usr/local/sbin/blindou-deployctl verify-backup
sudo -n /usr/local/sbin/apiwpp-deployctl verify
sudo -n /usr/local/sbin/blindou-hostctl verify
```

Também confirmar zero unit systemd falha e nenhuma porta nova. Antes da etapa
do conector, os namespaces devem estar vazios; depois dela, somente o Pod e o
Secret fechados descritos acima são aceitos. Qualquer outro workload interrompe
a fase.
