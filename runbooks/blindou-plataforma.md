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
e backup lógico próprios. A candidata D052 acrescenta o grupo mínimo
`blindou_redirector`; ela não cria um quinto login. O backup físico pgBackRest
continua cobrindo o cluster PostgreSQL inteiro; ele não substitui a cópia lógica
isolada do Blindou.

## Destino PostgreSQL exclusivo preparado por D028/D063

O parágrafo anterior descreve o estado vivo. D028 neste repositório, alinhada à
D063 do Blindou, prepara sem aplicar um
destino PostgreSQL 18 exclusivo no namespace `blindou-data`. A quarentena está
versionada em `platform/blindou-data/`; o StatefulSet, Service, PVCs e
NetworkPolicies pertencem ao repositório Blindou. Esta fase não criou o
namespace no host: nenhum manifest foi aplicado, e o `blindou-deployctl` atual
não o administra.

Não aplicar esse diretório com `kubectl`, não anexá-lo ao controlador atual e
não criar Secret manualmente. I1 entregou, mas não instalou, um
`blindou-datactl` separado, um verificador de bundle fechado e operações de
bootstrap, backup e restore-base. Fundação e StatefulSet ficam em arquivos
distintos: o controlador deve provar o pull da imagem privada por digest antes
de criar o workload. A admissão exclui `blindou-data` da regra geral da
aplicação e usa uma regra própria: `pull-only` admite apenas o Job de prova;
`candidate-foundation` admite somente o singleton e Jobs de dados fechados. A
imagem privada por digest e o bundle assinado já foram publicados e validados;
o controlador e a quarentena ainda não foram instalados neste ponto.

Por D031 neste repositório, alinhada à D064 do Blindou, a publicação da imagem
PostgreSQL pode usar temporariamente o servidor apenas como executor efêmero de
build e scan enquanto o usuário não solicitar o retorno ao GitHub Actions. O
procedimento baixa a base oficial imutável, deriva OCI sem daemon, remove os
artefatos proibidos, executa Trivy fixado e devolve o diretório de publicação à
estação. Ele roda como `apiadmin`, sem `sudo`, K3s, banco, serviço ou segredo,
sob 1 CPU, 4 GiB e prioridade baixa, e recusa iniciar enquanto Cargo/Rust estiver
ativo. A estação é a única autoridade que envia blobs ao GHCR. Essa exceção não
autoriza `foundation`, Secret, PVC, Job, Pod, migration, restore ou cutover.

O controlador aceita apenas `status`, `verify-quarantine`, `validate-release`,
`pull-proof`, `foundation`, `secrets`, `bootstrap`, `backup` e `restore-base`;
não existe comando de
cutover e o arquivo `20-application-egress.yaml` nunca é aplicado em I1.
Segredos entram por envelope tar em `stdin`. A fundação exige ao menos 140 GiB
livres, 4 GiB de memória disponível e dois CPUs lógicos antes dos PVCs. O
backup lógico, o base backup e o WAL chegam cifrados ao PVC de staging; o
restore usa um terceiro PVC e nunca o volume da autoridade.
Jobs de bootstrap, backup e restore usam a identidade de rede exata
`blindou.io/data-access=postgresql`. Eles resolvem o DNS estável do singleton
para a conexão, mas conservam o nome do Service em `PGHOST` para a validação
TLS `verify-full`; a aplicação futura continua usando o endpoint normal.
`archive_timeout=0` evita geração recorrente em repouso; intervalo, retenção,
RPO e offsite precisam ser aprovados juntos antes de I2.
Se `foundation` for interrompido, a repetição aceita apenas subconjuntos
fechados dos objetos esperados e reconcilia a mesma release. Recibos impedem
que `secrets` ou `bootstrap` recriem credenciais transitórias já removidas.

`pull-proof` é anterior e independente de `foundation`. Ele lê o PAT GHCR
`read:packages` já custodiado em `/etc/blindou/ghcr/pull-token`, entrega-o por
`stdin` a um verificador root-only, baixa e confere índice, manifesto, config e
todas as camadas do digest assinado e apaga os bytes temporários. Só o recibo
sem credencial permanece. Antes e depois, o comando exige gate `blocked` e zero
Deployment, StatefulSet, DaemonSet, Job, CronJob, Pod, Service, Secret e PVC em
`blindou-data`; não chama operações mutáveis do Kubernetes.

Instalar `blindou-datactl`, publicar imagem/bundle ou executar qualquer desses
comandos exige autorização operacional própria. I2 fará a pausa de escritores,
restauração final, troca de DSNs/rede e smoke em outra autorização. Até esse
recibo, o database nativo é a única autoridade; depois da primeira escrita no
destino, retornar ao nativo e criar duas autoridades é proibido.

Gate offline do pacote de quarentena:

```bash
python3 operations/remote/verify-blindou-data-artifacts.py .
```

Esse comando não acessa K3s, PostgreSQL, host ou segredo.

Os contratos adicionais de I1 são verificados por:

```bash
python3 operations/remote/test-blindou-data-release-verify.py
operations/remote/verify-blindou-platform-artifacts.sh
```

Esses gates também são offline; testam arquivo extra, path traversal, link,
evidência, imagem e namespace de assinatura divergentes.

O único bootstrap aceito é
`operations/Invoke-BlindouDataControllerBootstrap.ps1`, que transporta um
archive seletivo do commit exato e chama
`operations/remote/bootstrap-blindou-datactl.sh` pelo helper autorizado. Ele
restringe a admissão geral aos papéis
`application`/`edge`, instala a política específica de dados e cria, quando
ausente, somente a quarentena `blocked`. Reinstalação nunca rebaixa um gate de
dados já avançado. O helper aceita apenas `DataController`, host, staging,
commit e bootstrap fixos; não oferece `sudo` genérico.

Depois da publicação e da criação do bundle assinado, a prova sem objetos
Kubernetes usa:

```powershell
.\operations\Invoke-BlindouDataPullProof.ps1 `
  -ReleaseId <sha-blindou-40> `
  -BundleDirectory <diretório-dos-três-artefatos> `
  -Confirmation 'PROVAR PULL POSTGRESQL'
```

O orquestrador transporta exatamente os três artefatos, prepara o cache
assinado e executa somente `pull-proof`, `verify-quarantine`, `status` e os
gates preservados de host/APIWPP. Não executar `foundation` nessa etapa.

## Autoridades e arquivos

- `/usr/local/sbin/blindou-hostctl`: contenção temporária do host;
- `/usr/local/sbin/blindou-deployctl`: única interface sem senha da plataforma
  Blindou;
- `/usr/local/sbin/blindou-datactl`: interface futura e separada para o
  PostgreSQL dedicado; artefato preparado, ainda não instalado;
- `/usr/local/lib/blindou-platform/`: manifests e verificador root-owned;
- `/etc/blindou/`: chaves, certificados, URLs e identidades root-only;
- `/var/lib/blindou-platform/`: estado e cache de releases assinadas;
- `/var/backups/blindou/`: backups locais root-only;
- `/home/apiadmin/blindou-deploy-inbox/<sha40>/`: entrada fechada de releases;
- `/home/apiadmin/blindou-backup-outbox/`: somente envelopes criptografados
  exportados para leitura.

A chave privada de assinatura nunca entra no servidor ou neste repositório. A
chave privada de recuperação do banco dedicado só poderá entrar por `stdin`
durante um `restore-base` autorizado, em staging root-only e Secret efêmero;
ela é removida ao terminar. O bundle contém somente a chave pública de
assinatura e o certificado público de recuperação.

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

Todo orquestrador que reinstala o `blindou-deployctl` transporta o conjunto
completo de fontes exigido pelo bootstrap, inclusive o controlador emergencial,
o verificador GHCR e o provisionador fechado de planos Pagar.me. O gate offline
compara os seis orquestradores contra esse contrato para impedir que uma
integração nova quebre um caminho antigo de bootstrap.

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
controladores. O helper carrega `KEY_SERVIDOR` exclusivamente do arquivo
ignorado canônico `C:\github\servidor\.env`, independentemente do worktree
limpo usado para fotografar o commit, sem exibir seu conteúdo, e envia o valor
apenas por `stdin` para `sudo -S`. Ele fixa o host aprovado, o staging e
exatamente os instaladores
`bootstrap-blindou-hostctl.sh`, `bootstrap-blindou-deployctl.sh` e
`bootstrap-blindou-datactl.sh`; o último só é aceito pelo conjunto
`DataController` e por um caminho contendo o SHA completo do commit da
plataforma.

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
Como exceção estrita, D031/D064 permite somente a derivação e o scan da imagem
PostgreSQL dedicada no workspace efêmero do usuário. O token de publicação
continua na estação, nunca é transportado ao servidor, e a exceção termina
quando o usuário solicitar o retorno ao GitHub Actions.
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

A migration `0012` introduz o grupo `blindou_redirector`, `NOLOGIN` e
`NOBYPASSRLS`, sem tornar o login membro de `blindou_runtime`. O rollout usa
expansão/contração para não criar uma janela incompatível:

1. `apply` prepara o grupo dedicado e o concede a
   `blindou_redirect_login`, preservando temporariamente `blindou_app`;
2. o migrator separado aplica `0012`, que cria grants mínimos e policies RLS;
3. somente depois de `_sqlx_migrations.version = 12`, o controlador revoga
   `blindou_app` e verifica que o login não pertence aos grupos amplos;
4. o rollout da aplicação prossegue apenas depois dessa reconciliação.

Antes de `0012`, `verify-data` exige o papel legado para manter o runtime atual.
Depois de `0012`, exige exclusivamente o grupo dedicado. Falha do migrator
mantém o estado compatível com a release anterior; não conceder
`blindou_runtime` nem executar `GRANT` manual para contornar uma falha.

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

O worker `report-thumbnail` é uma dependência técnica desse núcleo e exige o
armazenamento de mídia R2. Ele não é UAZAPI, Resend ou Pagar.me e não pode ser
desabilitado silenciosamente para fazer o rollout passar. O bucket aprovado é
`blindou-media-prod`, o único domínio público é `https://media.blindou.com` e a
credencial S3 deve possuir somente leitura e gravação de objetos nesse bucket,
sem administração de R2 e sem acesso aos buckets de outros produtos.

Antes de republicar o runtime de revisão, executar na estação administrativa:

```powershell
.\operations\Invoke-BlindouR2RuntimeCredential.ps1
```

O operador copia da página de criação da Cloudflare o ID e a chave secreta para
dois campos protegidos. O script não lê a sessão do navegador, não salva os
valores na estação e os transmite em base64 somente por `stdin` ao comando
fechado `provision-r2-runtime-credential`. Os artefatos públicos do controlador
são empacotados e enviados em uma única conexão SCP para respeitar o limite de
handshakes do SSH; a credencial não participa desse pacote. O controlador
valida formato, escreve um objeto sentinela, lê o mesmo conteúdo pelo domínio
público, compara SHA-256, exclui o objeto e só então instala os dois arquivos
`root:root 0600` em `/etc/blindou/r2-media`. Falha antes da validação não
persiste a credencial.

Depois da prova viva, o próprio orquestrador repete
`provision-ui-review-runtime`: `production.env` passa a expor somente os dados
não sensíveis do bucket e o Secret `blindou-core-secrets` recebe as duas chaves.
O gate recusa a release se R2 estiver desabilitado, se a credencial local ou as
duas chaves do Secret estiverem ausentes, ou se o novo ciclo vivo falhar antes
da ativação. CORS permite somente `GET` e `HEAD` de
`https://app.blindou.com`; o URL público `r2.dev` permanece desabilitado.

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

Superadmins adicionais usam uma operação distinta e fechada. O comando
`bootstrap-additional-superadmin` aceita somente identidades previamente
versionadas no controlador e liberadas com argumentos exatos no sudoers. Para
Larissa, executar:

```powershell
.\operations\Invoke-BlindouAdditionalSuperadmin.ps1 `
  -ReleaseId <release-sha40> -ConfirmCreation
```

Se a senha desse acesso for perdida enquanto a recuperação por e-mail estiver
desligada, não excluir nem recriar usuário ou tenant. Depois de implantar uma
release que contenha `blindou-reset-user-password`, use o mesmo orquestrador em
modo de redefinição:

```powershell
.\operations\Invoke-BlindouAdditionalSuperadmin.ps1 `
  -ReleaseId '<SHA_COMPLETO_IMPLANTADO>' `
  -ResetPassword `
  -ConfirmReset `
  -PauseOnExit
```

A janela recebe a senha duas vezes em campos ocultos, o controlador fixa os
IDs e o e-mail da Larissa e o backend troca o hash, incrementa as versões de
sessão/MFA, revoga sessões e tokens anteriores e grava auditoria na mesma
transação. O comando falha fechado se release, gate, identidade, ownership,
papéis ou binário divergirem.

Os gates anteriores e posteriores à operação compartilham uma conexão SSH em
cada etapa. Isso preserva todas as verificações e evita que a limitação de
conexões administrativas do host bloqueie a conexão separada que transporta a
senha por `stdin`.

O orquestrador solicita e confirma a senha em campos protegidos, transmite-a
somente por `stdin`, cria uma conta central administrativa própria para fornecer
o contexto autenticado inicial e grava a role global `super_admin`. Depois,
valida o login e `isSuperAdmin` pela API pública sem imprimir senha ou tokens.
Repetição com o mesmo e-mail falha antes de criar outro tenant. Adicionar outra
identidade exige nova autorização e nova versão do controlador; e-mail livre em
argumento, SQL manual e kubeconfig administrativo permanecem proibidos.

### Pagar.me-first depois da aprovação da interface

Por D020, a UI já foi aprovada e a próxima integração é Pagar.me. UAZAPI e
Resend permanecem desabilitados. O fluxo é deliberadamente dividido para que a
custódia da chave não ative cobrança em uma release antiga.

Primeiro, para custodiar a credencial fora do Kubernetes, executar:

```powershell
.\operations\Invoke-BlindouPagarmeCredential.ps1
```

O script solicita a secret key de produção `sk_*` em campo protegido, recusa
explicitamente `sk_test_*`, gera 32 bytes
aleatórios para o caminho do webhook e envia ambos somente por `stdin` ao
controlador fechado. A chave é validada por chamada autenticada a
`https://api.pagar.me/core/v5`; os valores ficam em `/etc/blindou/pagarme` com
owner `root`, modo `0600` e fora do Kubernetes. A URL completa do webhook é
colocada temporariamente na área de transferência para cadastro direto no
painel Pagar.me e é apagada depois da confirmação ou de uma falha. Não copiar a
URL para chat, ticket, log ou documento.

No painel, cadastrar somente as categorias **Assinatura**, **Cobrança**,
**Fatura** e **Pedido**, com máximo de três tentativas. A autenticação adicional
do painel permanece desligada porque o backend já autentica, em tempo constante,
o segredo forte no caminho e depois confirma cada efeito por fetch-back.

Depois do webhook ser cadastrado no painel, os planos usam somente a secret key
já guardada no host:

```powershell
.\operations\Invoke-BlindouPagarmePlans.ps1 -ConfirmCreation
```

O executor não solicita nem copia a chave. O controlador root-only lista todo o
catálogo antes de qualquer escrita e reutiliza somente um plano vivo com a
metadata canônica. Se esse plano divergir, o `PUT /plans/{id}` autorizado pela
API V5 corrige o contrato e uma nova leitura confirma o efeito; colisão ou
duplicata interrompe a operação. Cada criação usa identidade estável, resposta
ambígua é reconciliada por nova leitura e nunca recebe retry cego. O recibo em
`%LOCALAPPDATA%\blindou\pagarme\plans-receipt.json` contém apenas IDs `plan_*`,
sem credencial, e não autoriza migration.

Em 2026-08-24, a secret key foi validada e guardada em
`/etc/blindou/pagarme`, o webhook foi cadastrado com segredo rotacionado e os
sete planos live passaram na verificação autenticada. Em 2026-08-25, a release
compatível `ab15a31` foi implantada após backup, a migration `0009` vinculou o
catálogo e a ativação fechada materializou somente o par Pagar.me no runtime.
UAZAPI e Resend continuam ausentes.

Essa etapa não altera `production.env`, ConfigMap, Secret Kubernetes ou
workload. Depois de atualizar o controlador e antes de publicar a candidata,
reexecutar `provision-ui-review-runtime blindou-ui-review-runtime`: isso mantém
todos os provedores desligados, preserva o cofre Pagar.me separado e acrescenta
`PAGARME_ENABLED=false` ao ConfigMap consumido pela release compatível.

Em seguida, publicar pelo processo normal uma release assinada em que backend
e os 16 workers tenham a annotation
`blindou.io/pagarme-first-compatible: "true"`. O verificador recusa o bundle se
o marcador estiver ausente.

Com a candidata aplicada e somente mediante autorização operacional própria,
executar:

```powershell
.\operations\Invoke-BlindouPagarmeActivation.ps1 `
  -ReleaseId <SHA-GIT-COMPLETO>
```

O operador confirma `ATIVAR PAGARME`. O controlador revalida a chave live,
confere o SHA corrente e os marcadores, muda para
`INITIAL_UI_REVIEW_MODE=false`/`PAGARME_ENABLED=true`, publica somente o par de
segredos Pagar.me e reinicia backend e 16 workers. UAZAPI e Resend continuam
ausentes. Se materialização, rollout ou readiness falhar, a configuração e o
Secret anteriores são restaurados e os consumidores voltam a iniciar no modo
fechado. Um journal root-only permanece até o recibo final; se o processo for
interrompido, a próxima execução primeiro restaura o modo fechado e só então
tenta uma nova ativação.

A prontidão dessa transição usa `rollout status` sobre o backend e os 16
workers. Esse gate só conclui quando as probes HTTP `/ready` da release assinada
passam pelo kubelet. Não executar `curl`, shell ou outra ferramenta de
diagnóstico dentro das imagens mínimas de produção; a ausência dessas
ferramentas é parte do endurecimento e não pode quebrar ativação nem rollback.

Os sete planos externos usam ciclo mensal, `billing_type=prepaid`, uma parcela,
BRL, ausência de trial, produto não físico e descritor `BLINDOU`. Seus IDs não
entram neste repositório; são vinculados no Blindou por migration aditiva
separadamente autorizada.

O coletor de métricas usa o mesmo lock do controlador. Se ele vencer uma corrida
curta entre duas etapas, o orquestrador repete somente o retorno específico de
lock ocupado (`exit 2`), por no máximo 12 tentativas com intervalo de cinco
segundos. Gates e `apply` são comandos separados para que nenhum efeito
concluído entre em um retry ambíguo. Qualquer outro código interrompe a release
imediatamente.

Na primeira instalação, `activate-release-gates` exige o par
`blindou-production=secrets-only` e `blindou-edge=connector-only`, além da
ausência de `current_release`. Em atualização, exige o par `passed`/`passed`
para preservar o runtime e o Tunnel saudáveis, junto de um ponteiro
`current_release` regular, `root:root 0600` e com SHA válido. Pares mistos,
gate diferente ou objeto inesperado falham fechados. Antes da primeira release,
a aplicação permanece em `secrets-only` até a prova GHCR, o backup recente e o
recibo offsite da candidata serem confirmados; uma atualização não rebaixa o
namespace ativo a esse gate intermediário.

Enquanto a ordem Pagar.me-first da D020 mantiver UAZAPI e Resend adiados, uma
atualização aceita essa ausência somente quando o recibo root-only de ativação
Pagar.me estiver íntegro e `PAGARME_ENABLED=true` na configuração protegida. Um
receptor externo já confirmado continua sendo aceito normalmente. Ausência ou
divergência dos dois caminhos falha fechada; o gate não cria credencial, não
altera o Pagar.me e não antecipa UAZAPI/Resend.

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
- presença segura da credencial Pagar.me no cofre dedicado;
- recibo de ativação do runtime Pagar.me em release compatível;
- sucesso da própria coleta.

Falha de coleta produz uma métrica explícita com valor zero. Alertas externos
por Resend permanecem adiados durante D020 e o scrape dos workloads depende da
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
