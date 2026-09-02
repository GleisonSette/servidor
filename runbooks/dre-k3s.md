# DRE familiar no K3s local

## Estado e limite

O controlador schema 2 e a fundação Kubernetes do DRE estão instalados no
servidor. A release `dre-20260902T173345Z-a191f86039c1` está corrente, com nove
migrations, API, worker e PostgreSQL Ready e PVC `Retain` dedicado. O backup
completo `20260902T174349Z-64e638e42c47` passou no R2. O restore seguinte
preservou o PVC descartável após timeout causado pelo UID `999` divergente da
imagem Alpine, cujo usuário `postgres` é `70`; D043 corrige o renderer e exige
reconciliação fechada desse PVC antes de repetir o ensaio. HTTPS e contas ainda
não foram concluídos.

O DRE é um projeto sempre ativo e independente. Ele não integra nem altera o
slot APIWPP/SaferWPP e não compartilha namespace, ServiceAccount, Secret, PVC,
banco, release ou chave de assinatura com Blindou. A primeira implantação é
recusada quando houver menos de 5 GiB de memória disponível, menos de 45 GiB no
filesystem do K3s, menos de quatro CPUs lógicas, nó não Ready ou qualquer
divergência dos controladores Blindou, APIWPP e slot secundário.
Se o futuro namespace `blindou-data` existir, seu controlador, lock e recursos
também entram obrigatoriamente na proteção.

## Fronteiras administrativas

- `/usr/local/sbin/dre-deployctl` é o único caminho automatizado de mutação.
- A identidade Kubernetes tem CN `dre-deployctl`, grupo `dre-deployers`, não
  pertence a `system:masters` e usa kubeconfig root-only próprio.
- A admissão `dre-controller-only` falha fechada para os recursos do DRE. O
  acesso `system:admin` continua sendo break-glass do administrador root e não
  é interface de automação cotidiana. O `system:kube-scheduler` recebe somente
  a exceção de `UPDATE` em PVC necessária ao `WaitForFirstConsumer`; isso não o
  autoriza a criar, apagar ou alterar outros recursos DRE.
- O sudoers permite somente ações enumeradas do controlador; não concede shell,
  `kubectl`, caminho de manifesto, kubeconfig ou variável de ambiente livre.
- A chave privada de assinatura nunca entra neste repositório nem no servidor.
  O host recebe apenas a chave pública Ed25519.
- Por D030, `Dre.SudoBootstrap.psm1` pode ler exatamente uma ocorrência de
  `KEY_SERVIDOR` do arquivo ignorado canônico `C:\github\servidor\.env` e
  entregá-la somente por `stdin` ao bootstrap DRE fechado. O helper fixa host,
  padrão do staging, hashes,
  inventário, cache root-owned e instalador; não aceita comando livre. O valor
  não pode ser impresso, persistido, colocado em argumento ou variável de
  ambiente. O script root é transportado em Base64 dentro de um comando remoto
  sem aspas ambíguas para o `ssh.exe`; sucesso só é aceito quando o marcador
  final contém os hashes esperados. Os helpers do Blindou/slot continuam
  capacidades separadas.
- Por D035, `Dre.ImageBuild.psm1` usa a mesma origem de senha somente para o
  build efêmero fechado. Ele não aceita comando root livre, não instala daemon
  e não acessa o socket containerd do K3s.

## Build, scan e publicação das imagens

Windows não executa Linux, WSL, Docker, container ou teste de imagem. Ele gera
o archive pelo Git, transporta arquivos com SSH/SCP nativos e chama os dois
orquestradores. O build acontece somente no servidor:

```text
pwsh operations/Invoke-DreImageBuild.ps1
```

O orquestrador fixa o commit, SHA-256 do archive, BuildKit 0.32.2 e script do
build. O helper root copia as entradas para staging privado, usa worker OCI
`native` com rede `bridge`, dois passos paralelos e prioridade reduzida, e
encerra o daemon no `trap`. K3s/containerd nunca é backend do builder. A saída
são `rust.oci.tar`, `postgres.oci.tar` e `validation.oci.tar`, metadados e
recibo ligados ao SHA Git.

A verificação do slot secundário anterior e posterior ao build repete somente
o erro transitório exato de lock do coletor, por no máximo cinco tentativas e
espera limitada. Qualquer outro erro falha imediatamente. Isso evita classificar
como falha de integridade a corrida curta com o timer, sem ocultar divergência
real de APIWPP/SaferWPP.

Depois, sem sudo:

```text
pwsh operations/Invoke-DreImagePublish.ps1
```

Syft gera os três SBOMs SPDX; Trivy bloqueia o fluxo se encontrar qualquer
vulnerabilidade alta/crítica; somente então regctl publica no GHCR. As três
ferramentas e os dois scripts são fixados por SHA-256. O token do `gh` chega
por `stdin`, é usado em HOME temporário `0700` e não entra em argumento,
ambiente persistente, log ou recibo. O recibo final contém somente referências
por digest e hashes das evidências. Falha parcial de registry é repetida com a
mesma tag `git-<12 SHA>`; nunca trocar o conteúdo por baixo da tag. O transporte
local é compatível com Windows PowerShell 5.1: a linha de comando do `ssh.exe`
é escapada pelas regras nativas do Windows e o token continua separado,
exclusivamente no `stdin` redirecionado.

## Contrato da release schema 2

No repositório `C:\github\dre`, a release é renderizada por digest e empacotada
por `ops/k8s/package-release.py`. O archive assinado contém exatamente:

- os quatro estágios permanentes `00-platform`, `10-migrations`,
  `20-database-access` e `30-runtime`;
- os seis estágios descartáveis `40-validation-platform` até
  `45-validation-e2e`;
- `release.json` schema 2 com nove migrations, `dre-validation` e checksums dos
  dez estágios;
- `supply-chain.json` ligado ao SHA Git e ao release ID;
- SBOM SPDX e recibo de scan sem vulnerabilidade alta/crítica para as imagens
  Rust, PostgreSQL e validation runner `linux/amd64`;
- regras de alerta K3s do DRE.

O release ID usa `dre-YYYYMMDDTHHMMSSZ-<12 primeiros caracteres do SHA Git>`.
O empacotador gera `release.tar.gz`, `release.tar.gz.sig` e
`release-envelope.json`. O controlador confere SHA-256, assinatura Ed25519,
conteúdo do archive, escopo Kubernetes, imagens, SBOM, scan e alertas antes de
copiar a release para cache root-only. Schema 1 continua importável e
reverificável somente para rollback; `plan` e `deploy` aceitam exclusivamente
schema 2 com recibo descartável aprovado.

## Instalação do controlador

Estado vivo: controlador schema 2 com chave pública
`4902604dad96d9b07f4010308d30e3815cb4e76446855d925079be0e3b922ce9`
e backup transacional da atualização em
`/var/backups/servidor-local/dre-controller-bootstrap`. Reexecução usa bundle
novo, hashes novos e o mesmo contrato fechado; nunca altera o cache já
atestado. Atualização com Secrets existentes preserva explicitamente o gate
`secrets-only`; aplicar novamente a fundação não pode regredi-lo para
`blocked`.

Somente em janela autorizada:

1. gerar e guardar a chave privada Ed25519 fora do servidor e do Git;
2. transportar este repositório, a chave pública e seus hashes para staging
   autenticado;
3. executar como root o comando fixo:

   ```text
   bootstrap-dre-deployctl.sh PUBLIC_KEY PUBLIC_KEY_SHA256
   ```

O bootstrap valida todos os artefatos, sintaxe sudoers/systemd, K3s
`v1.36.2+k3s1`, `x86_64` e integridade de APIWPP, Blindou e slot. Ele cria os
três namespaces de base — produção, restauração e borda —, StorageClasses
`Retain`/`Delete`, RBAC, admissão, identidade renovável, métricas e alertas.
Um dry-run com identidade não
autorizada precisa ser recusado. Falha restaura arquivos e Prometheus; se a
fundação era nova e ainda vazia, ela também é removida.

O bootstrap distingue três estados fechados. `predeploy` aceita somente produção
sem PVC/workload. `failed-first-deploy` exige recibo `failed`, release anterior
`none`, rollback `passed`, apenas o StatefulSet/Pod/Service/PVC exatos do
PostgreSQL preservados e ausência comprovada de `_sqlx_migrations`. Nesse estado
ele não reaplica a fundação e compara antes/depois o fingerprint de namespace,
workloads, configurações, Secrets e PVC.

`active-release` permite atualizar somente os arquivos do controlador depois do
deploy. Ele exige ponteiro corrente root-only `0600`, release schema 2 no cache,
nove migrations, gate `passed`, PVC `Bound`, API/worker/PostgreSQL 1/1 Ready,
validação descartável ausente e nenhum Pod `dre-account-provisioner`. O
controlador anterior e o novo executam `verify` sobre a mesma release. A fundação
não é reaplicada e os fingerprints completos de produção e edge precisam ser
idênticos antes e depois. Assim, instalar uma nova operação administrativa não
faz rollout, migration ou alteração de Secret por efeito colateral.

`dre-validation` deve estar ausente ou ser uma validação
descartável autêntica com gate `blocked`, release e operação válidas. O segundo
caso existe para instalar uma correção de diagnóstico sem apagar a evidência da
falha; o bootstrap compara um fingerprint das configurações, workloads, PVCs e
Secrets antes e depois e recusa qualquer alteração. Os cinco Secrets
permanentes — e o sexto FCM opcional — podem existir; nomes diferentes ou gate
de produção além de `secrets-only` são recusados. A ampliação aditiva da
fundação permanece compatível com o controlador anterior caso a troca dos
arquivos precise ser revertida.

Antes do primeiro deploy, `dre-edge` precisa estar ausente ou `blocked`, sem
Deployment nem Secret. No modo `active-release`, ele pode continuar `blocked` e
vazio ou estar `connector-only`, com exatamente um Deployment/Pod
`dre-cloudflared`, o único Secret `dre-cloudflare-tunnel` e nenhum recurso
proibido. O bootstrap compara o fingerprint do edge e não lê, copia nem
substitui o valor do token.

As provas de inventário vazio usam a interface administrativa somente leitura
do controlador. A identidade mutável DRE não possui `list` amplo no edge e não
pode ser usada como substituta: resposta `Forbidden` nunca equivale a conjunto
vazio.

O backup transacional da instalação fica em
`/var/backups/servidor-local/dre-controller-bootstrap/<timestamp>`. Rollback
humano restaura somente os alvos registrados em `targets.txt`, repete
`visudo`, `systemd-analyze verify`, `promtool check config`, os três
controladores protegidos e a prova negativa da admissão.

O audit log técnico `/var/lib/dre-deployctl/audit.jsonl` usa rotação diária,
30 arquivos e teto de 16 MiB por arquivo. Planos de deploy já inúteis são
removidos depois de sete dias; recibos de release, backup e restore permanecem
root-only para rastreabilidade.

## Importação e plano

O operador copia apenas archive e assinatura para:

```text
/home/apiadmin/dre-deploy-inbox/RELEASE_ID/release.tar.gz
/home/apiadmin/dre-deploy-inbox/RELEASE_ID/release.tar.gz.sig
```

O diretório deve ser `apiadmin:apiadmin` `0700`; arquivos, `0400` ou `0600`.
Hashes vêm do envelope local conferido. A importação aceita somente:

```text
sudo -n /usr/local/sbin/dre-deployctl import-release RELEASE_ID ARCHIVE_SHA256 SIGNATURE_SHA256
```

Antes da primeira release, `initialize-secrets RELEASE_ID` recebe por `stdin`
um único JSON protegido com os campos exatos `schema`,
`registry_dockerconfigjson`, `web_bridge_token`, `r2` e
`fcm_service_account`. O dockerconfig fica restrito aos registries das duas
imagens permanentes e da imagem efêmera de validação; FCM deve ser `null`
quando a release não o habilita. O token da ponte
usa somente alfabeto portátil, possui ao menos 64 caracteres e é o mesmo valor
protegido no Secret `DRE_BRIDGE_TOKEN` do Cloudflare Pages.

O orquestrador local gera o token da ponte somente em memória. Primeiro o envia
por `stdin` à operação autenticada que grava o Secret do Pages e confirma apenas
a presença do nome, nunca o valor. Somente depois monta o JSON em memória e o
envia por `stdin` ao controlador. Se a gravação no Cloudflare falhar, a
inicialização Kubernetes não começa. Se a inicialização falhar, o controlador
remove todos os Secrets DRE criados naquela tentativa e o Pages pode receber um
novo token antes da repetição. Não ler Secret Kubernetes para recuperar token,
não colocar valor em argumento e não persistir o JSON em disco ou histórico.
`DRE_API_ORIGIN` permanece ausente até a rota HTTPS ser autorizada, criada e
verificada.

O controlador gera senhas independentes para admin/API/worker/backup, URLs
codificadas e cifra de backup em `/run`, cria Secrets por arquivo e apaga o
material temporário. Se qualquer Secret DRE já existir, a inicialização inteira
é recusada; rotação futura é outra operação, nunca efeito colateral de deploy.

Não colocar o JSON protegido em argumento, histórico, arquivo do repositório ou
saída capturada. Usar entrada oculta/controlada do orquestrador da janela.

Depois:

```text
sudo -n /usr/local/sbin/dre-deployctl plan RELEASE_ID
```

O plano dura 30 minutos e vincula release, archive, release corrente, inventário
de Secrets, recursos protegidos e capacidade viva. A saída contém apenas o
`plan_sha256` não secreto. Mudança em qualquer prova exige plano novo.

Se o primeiro deploy falhou antes das migrations e o rollback comprovado deixou
o rótulo de projeto ausente, somente `import-release` e `validate-release` podem
usar a exceção de leitura desse estado. Ela recompõe recibo, release anterior,
inventário, imagem, Secrets, PVC e ausência de `_sqlx_migrations`; qualquer
outra divergência mantém a operação bloqueada.

## Validação descartável, deploy e verificação

Antes de qualquer plano permanente:

```text
sudo -n /usr/local/sbin/dre-deployctl validate-release RELEASE_ID OPERATION_ID
```

Essa ação cria `dre-validation`, instala RBAC temporário, copia sem exibir
somente o pull secret já existente e gera credenciais sintéticas em `/run`.
Depois aplica PostgreSQL sem WAL/R2, nove migrations, papéis, API/worker,
bootstrap de duas contas/dispositivos sintéticos e o E2E assinado. API, worker
e PostgreSQL são reiniciados separadamente e precisam recuperar readiness e as
nove migrations. Sucesso registra archive/digests, remove namespace, PVC e PV e
libera a criação do plano. Falha preserva o namespace com gate `blocked`. O
Job de acessos pode conter somente o `initContainer` opcional
`wait-for-postgres`, preso à mesma imagem PostgreSQL por digest, com comando,
script, recursos e segurança exatos. Ele aguarda no máximo 12 vezes o Service
interno, com atraso exponencial limitado a cinco segundos, para absorver a
convergência da `NetworkPolicy` no IP do próprio Pod. A ausência continua aceita
somente para compatibilidade de releases antigas; container extra, script
alterado ou espera em outro workload são recusados. O helper principal não
recebe retry e continua falhando definitivamente em erro de autenticação ou SQL.
O diagnóstico fechado e somente leitura informa fase do recibo, pods,
workloads,
os 25 eventos Kubernetes mais recentes, IP interno do Pod PostgreSQL, contrato
do Service, probes TCP fixas por `pg_isready`, log técnico do banco e até 16
KiB/80 linhas de cada contêiner falho, com URLs e credenciais redigidas. As
probes não autenticam, não escrevem dados e não recebem comando do operador.
Ele não permite shell ou `kubectl` livre:

```text
sudo -n /usr/local/sbin/dre-deployctl diagnose-validation
```

Depois de registrar a causa, a única remoção autorizada é:

```text
sudo -n /usr/local/sbin/dre-deployctl cleanup-validation RELEASE_ID OPERATION_ID
```

Com autorização explícita para migration persistente e deploy:

```text
sudo -n /usr/local/sbin/dre-deployctl deploy RELEASE_ID PLAN_SHA256 OPERATION_ID
sudo -n /usr/local/sbin/dre-deployctl verify RELEASE_ID
```

`OPERATION_ID` usa `YYYYMMDDTHHMMSSZ-<12 hex>`. O controlador:

1. reverifica assinatura e conteúdo no cache;
2. valida capacidade, Secrets, identidade e os três projetos protegidos;
3. adquire locks DRE, Blindou e slot antes da mutação;
4. impede troca implícita da imagem PostgreSQL;
5. aplica plataforma e aguarda o PostgreSQL;
6. cria a stanza pgBackRest e executa `check`;
7. recria somente o Job fixo de migration e exige a quantidade declarada —
   nove para schema 2;
8. recria o Job fixo de papéis e acessos;
9. aplica API/worker e aguarda os rollouts;
10. instala regras Prometheus assinadas, valida configuração e executa smoke
    pela proxy privada do API Server;
11. confirma exatamente `api`, `worker` e `postgres`, Services ClusterIP, PVC
    Bound e fingerprint inalterado de APIWPP/Blindou;
12. só então publica o ponteiro root-only da release.

Depois de comparar o fingerprint sob os locks compartilhados, o controlador
libera explicitamente os locks de PostgreSQL Blindou, slot e Blindou antes de
chamar os verificadores independentes. O gate offline exige essa ordem em
`validate-release`, `cleanup-validation` e `deploy`, evitando auto-contenção do
próprio controlador.

Falha restaura a plataforma e o runtime anteriores; na primeira release remove
somente os dois Deployments, Services e PDBs de aplicação. PVC, PostgreSQL,
migration aditiva e Secrets são preservados para diagnóstico. Falha na própria
compensação fecha o gate como `rollback-failed`. Cada `operation_id` é de uso
único e possui recibo root-only `started`, `passed` ou `failed`, evitando repetir
silenciosamente uma operação interrompida. Migration destrutiva não pertence ao
contrato.

Quando a primeira tentativa falhar antes das migrations e o rollback preservar
somente o PostgreSQL/PVC esperado, a coleta autorizada é:

```text
sudo -n /usr/local/sbin/dre-deployctl diagnose-production
```

Ela não recebe argumentos e retorna JSON com recibo resumido, workloads,
eventos, log técnico redigido do PostgreSQL, `pgBackRest info` e os logs fixos
de `check`/`archive-push`. Antes da coleta, a interface administrativa somente
leitura recompõe a prova do recibo, imagem por digest, inventário exato,
PostgreSQL Ready e ausência de `_sqlx_migrations`; o rótulo de projeto do
namespace é informado como evidência, porque sua ausência pode ser parte da
falha investigada. A ação não repete o `check`, não grava no R2, não expõe
Secrets e não oferece shell ou `kubectl`. Fora do estado fechado de recuperação
a operação é recusada.

Depois que uma nova release schema 2 for importada e aprovada integralmente em
`dre-validation`, a recuperação única é:

```text
sudo -n /usr/local/sbin/dre-deployctl recover-first-deploy RELEASE_ID OPERATION_ID
```

Ela exige o recibo falho com rollback aprovado, a validação da nova release,
capacidade viva, os cinco Secrets exatos, PostgreSQL Ready na imagem anterior,
PVC `Retain` de 20 GiB e ausência de migrations. Sob os locks DRE/Blindou/slot,
restaura somente o rótulo `project=dre`, troca o único contêiner PostgreSQL para
o digest assinado novo e executa `stanza-create`/`check`. Um fingerprint ignora
exclusivamente o rótulo e a imagem permitidos; todo outro recurso, PVC e Secret
precisa permanecer idêntico. Falha volta a imagem anterior, remove o rótulo e
reprova fechado se essa compensação não convergir. Sucesso não aplica migration,
não cria release corrente e apenas libera o fluxo normal `plan`/`deploy`.

Se `stanza-create` ou `check` falhar, o controlador limita a saída a 16 KiB,
redige padrões de credencial e a devolve ao operador antes da compensação. O
recibo continua sem payload técnico ou segredo; a imagem e o rótulo anteriores
são restaurados antes de uma nova tentativa.

O código 50 só é transitório quando a saída também comprova lock ocupado por
outro processo pgBackRest. Nesse caso específico, o controlador faz no máximo
oito tentativas, com backoff exponencial, jitter e espera individual limitada a
30 segundos. Qualquer outro código ou mensagem falha imediatamente. Os
diretórios efêmeros de log e lock são criados com modo `0700` antes da ação.

## Provisionamento privado das contas iniciais

Depois que a release corrente estiver saudável, o único caminho autorizado para
criar o núcleo familiar e as contas Gleison/Aline é:

```text
sudo -n /usr/local/sbin/dre-deployctl provision-accounts RELEASE_ID OPERATION_ID HOUSEHOLD_ID GLEISON_USER_ID ALINE_USER_ID
```

Os cinco identificadores não secretos são validados e permanecem estáveis. As
duas senhas chegam exclusivamente por `stdin`, uma por linha, e nunca entram em
argumento, variável de ambiente, audit log ou recibo. O login permanente
`dre_api_runtime` não pode assumir `dre_migrator`; por isso o controlador não
executa essa operação no Pod da API. Ele cria um único Pod administrativo
efêmero, preso ao digest Rust da release corrente, sem token de ServiceAccount,
com filesystem raiz somente leitura e a URL admin montada apenas durante a
transação. O Pod aceita o par de senhas por `exec -i`, é removido antes do
recibo e possui deadline de cinco minutos. Falha de limpeza fecha o gate como
`accounts-cleanup-failed`. Núcleo, usuários e auditorias são gravados em uma
única transação PostgreSQL: falha em qualquer conta reverte tudo. O recibo
root-only registra somente release, operação, identificadores, logins e o
atestado `atomic=true`.

Essa ação é de uso único para a primeira família. Troca de senha, dispositivo e
saldo inicial continuam fluxos administrativos separados e exigem autorização
própria.

## Backup e restauração

Operações autorizadas:

```text
sudo -n /usr/local/sbin/dre-deployctl backup diff OPERATION_ID
sudo -n /usr/local/sbin/dre-deployctl backup full OPERATION_ID
sudo -n /usr/local/sbin/dre-deployctl restore-drill RELEASE_ID OPERATION_ID latest
```

`full` executa pgBackRest e a exportação lógica cifrada; `diff` executa somente
pgBackRest. Ambos exigem runtime saudável e gravam recibo root-only sem valor,
descrição ou credencial.

O restore drill copia em memória somente os Secrets necessários para
`dre-restore-drill`, cria um PVC de 20 GiB na StorageClass exclusiva `Delete`,
restaura da mesma release e desliga `archive_mode` no banco restaurado para não
enviar WAL ao prefixo de produção. A prova exige as migrations da release —
nove no schema 2 e sete em rollback legado — e zero índice inválido. Ao passar,
remove StatefulSet, Service, ConfigMaps, Secrets e PVC e
aguarda o PV ser apagado. Falha preserva o PVC para diagnóstico e exige
reconciliação explícita; nunca apaga ou restaura sobre `dre-postgres-data`.
As três credenciais de backup são montadas no init container e no PostgreSQL
restaurado como arquivos `subPath` individuais, com a mesma validação
antissymlink usada no PostgreSQL permanente. O segundo acesso é necessário para
buscar WAL durante a recuperação antes da abertura do banco.

Se o Pod não puder ser agendado, o init container falhar ou a imagem não puder
iniciar, a operação encerra sem aguardar todo o timeout. O recibo `failed` e a
saída do controlador preservam fase, estados do Pod e os últimos logs dos
containers, limitados e sanitizados; credenciais e payloads financeiros não são
registrados. Os workloads temporários são removidos e o PVC fica preservado
para reconciliação explícita.

Depois de identificar a causa, a única reconciliação autorizada do volume
descartável preservado informa a mesma release, o ID da operação falha e um ID
novo para a própria limpeza:

```text
sudo -n /usr/local/sbin/dre-deployctl cleanup-restore RELEASE_ID FAILED_OPERATION_ID OPERATION_ID
```

A ação exige um novo `OPERATION_ID`, distinto do `FAILED_OPERATION_ID` cujo
recibo está `failed`, ausência dos workloads temporários, labels e
UIDs correspondentes, PVC de 20 GiB na StorageClass `Delete` e PV vinculado com
reclaim policy `Delete`. Ela não aceita nome ou caminho fornecido pelo operador,
remove somente `dre-restore-data`, aguarda o PV desaparecer e reverifica a
produção e os projetos protegidos.

PITR aceita somente timestamp UTC `YYYY-MM-DDTHH:MM:SSZ`. O recibo do restore
fica em `/var/lib/dre-deployctl/receipts`.

## Borda HTTPS do DRE

A borda usa um Tunnel Cloudflare exclusivo do DRE. O recurso externo, o DNS e
a configuração do hostname são criados no painel autenticado; o servidor
recebe somente o token desse túnel pela ação fechada:

```text
sudo -n /usr/local/sbin/dre-deployctl configure-edge RELEASE_ID OPERATION_ID
```

O token chega exclusivamente por `stdin` não interativo, nunca entra em
argumento, arquivo de staging, recibo ou log e é persistido somente no Secret
Kubernetes cifrado `dre-cloudflare-tunnel`. O controlador aceita a ação apenas
para a release corrente saudável, com `dre-edge` bloqueado e vazio. Ele cria
um único Deployment `dre-cloudflared`, fixado por digest, aguarda readiness,
reverifica a API e os projetos protegidos e só então altera o gate para
`connector-only`. Falha remove Deployment e Secret e retorna o namespace ao
estado bloqueado.

`dre-edge` possui quota para um Pod, um Secret, zero Service/PVC/ConfigMap de
aplicação, ServiceAccount sem token e NetworkPolicies de negação por padrão.
O único `ConfigMap` tolerado pelo gate é `kube-root-ca.crt`, criado
automaticamente pelo controlador do Kubernetes: ele deve ser o único objeto
desse tipo, conter somente `data.ca.crt` com certificado PEM, não possuir
`binaryData` e não ser imutável. A quota continua em zero para impedir a
criação de `ConfigMap` pela aplicação; qualquer outro objeto faz o controlador
falhar fechado. O conector
pode consultar DNS, sair somente por TCP/7844 para a borda pública e alcançar
somente o Service `dre-api` em TCP/8080. Ele não recebe kubeconfig, credencial
de registry, volume persistente ou acesso a outros projetos.

O hostname público aponta para
`http://dre-api.dre-production.svc.cluster.local:8080`. A configuração externa
deve bloquear `/metrics`, confirmar HTTPS, health/readiness, autenticação e SSE
e somente depois definir no Pages
`DRE_API_ORIGIN=https://dre-api.fitdock.com.br`. Rollback desabilita primeiro
o hostname/rota no Cloudflare e exige operação fechada futura para retirar ou
rotacionar o conector; não apagar o Secret manualmente.

## Exposição e dados reais

Este controlador não cria Ingress, NodePort, LoadBalancer, `hostPort`, regra
UFW, recurso Tunnel ou rota no painel Cloudflare. Ele pode materializar apenas
o conector isolado de um Tunnel externo previamente criado e autorizado. A API
continua ClusterIP; PostgreSQL e métricas nunca recebem exposição pública.
Dispositivos Android e saldo inicial permanecem operações separadas.
