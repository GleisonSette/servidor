# Estado atual da plataforma local

metadata:
  canon_id: canon-estado-atual
  source_path: memory/canon/estado-atual.md
  generated_from: auditoria SSH, runtime K3s, Prometheus e repositórios locais
  updated_at: 2026-09-02
  status: canonical

## Escopo e data da evidência

Este canon reúne o estado atual do host: versões, portas, capacidade, backups,
workloads e serviços. A última auditoria de capacidade ocorreu em 2026-08-26 e
a última operação DRE foi observada em 2026-09-02. O Blindou permanece ativo;
o slot APIWPP/SaferWPP está sem ocupante na geração 2. O DRE possui fundação,
Secrets, release no cache e PostgreSQL/PVC dedicados preservados pelo rollback;
API e worker continuam ausentes.

## Controlador do slot secundário verificado em 2026-08-31

- `secondary-slotctl` permanece instalado como arquivo root-owned, com sudoers
  restrito, admissão fail-closed, timer de métricas e regras Prometheus.
- O atestado root-only está válido na geração 2, com ocupante `none`, zero
  workload APIWPP e zero workload SaferWPP.
- A verificação posterior à validação DRE retornou
  `secondary_slot_verify=passed`; o DRE continua fora desse slot.
- Fundação PostgreSQL, controladores e workloads SaferWPP continuam ausentes.

## DRE schema 2 e primeiro deploy persistente observado em 2026-09-02

- D029 mantém o DRE independente do slot APIWPP/SaferWPP. D030 permite que
  somente `Dre.SudoBootstrap.psm1` entregue `KEY_SERVIDOR` por `stdin` ao
  bootstrap fechado; não existe `sudo` genérico.
- A chave privada Ed25519 permanece fora do servidor e dos repositórios. O host
  possui somente a chave pública SHA-256
  `4902604dad96d9b07f4010308d30e3815cb4e76446855d925079be0e3b922ce9`.
- Fundação, identidade, RBAC, admissão, sudoers, timers, alertas e métricas estão
  instalados. Os cinco Secrets pré-deploy sem FCM existem e
  `dre-production` está em `secrets-only`.
- A release `dre-20260831T202100Z-f6b06765ff61`, ligada ao commit DRE
  `f6b06765ff6196eb8dbd4a9a9fd8c3a422c42ce2`, foi aceita no cache com archive
  SHA-256 `05c14e22ffa092e16f4a7530c8ecddf5216ad6faa54be401ab48d1c5e90b954d`.
  O pacote e a assinatura foram reproduzidos e verificados independentemente.
- Os digests finais são `dre-app@sha256:4f91068dd559fe4852bdc19ee76ad2b4e700695364378265ce0674332891d3d6`,
  `dre-postgres@sha256:029bb2112afae1fca539381bf338fb9c64443b668230c17cd51447c0efb7f2e1`
  e `dre-validation-runner@sha256:7a62c80e8d0094f366d2dbfbfa6fa3c15b439aa20134e7450d63f981ce9615c5`.
  Os três scans registraram zero vulnerabilidade alta ou crítica e possuem SBOM
  SPDX no bundle.
- O controlador instalado veio do bundle SHA-256
  `56612eebcbd60726751dea0b30c04eebaad99f1ee2d5b151b615f652943603b7`;
  a fonte foi publicada no commit de plataforma `e26c528` e o bundle foi
  fixado em `d17bdff`. O bootstrap gerou backup transacional em
  `/var/backups/servidor-local/dre-controller-bootstrap/20260901T151732Z`.
- A correção adicionou a quebra de linha obrigatória da leitura de capacidade e
  o único comando `provision-accounts`. O primeiro `plan` pós-instalação
  retornou `status=passed`; o provisionamento envia duas senhas somente por
  `stdin` e chama a transação atômica da release, sem senha em argumento ou
  recibo.
- A operação `20260831T202626Z-f6b06765ff61` aprovou nove migrations, papéis de
  acesso, bootstrap sintético, E2E financeiro, SSE/queries e substituição de
  API, worker e PostgreSQL. Ao passar, removeu `dre-validation`, PVC e PV.
- O executor rootless também aprovou `make release-check` e `make e2e` em uma
  stack sintética nova. Containers, redes, volumes, imagens, processos e raízes
  temporárias da execução foram removidos; somente as ferramentas de sistema
  sem daemon previstas por D036 permanecem instaladas.
- A validação descartável oficial `20260902T064929Z-97891da83f92` aprovou a
  release `dre-20260902T061906Z-69716bb0a23e`, inclusive nove migrations,
  acessos, E2E e reinícios de API, worker e PostgreSQL; namespace, PVC e PV
  temporários foram removidos no sucesso.
- A verificação posterior confirmou Blindou íntegro na release
  `ee4a335236b0e99e5fac4ee3e30a986f0ddc8bb2`, 12 migrations, slot `none` na
  geração 2 e zero unit systemd falha.
- O rollout persistente, migrations, backup/restore, rota HTTPS, contas e chave
  Android estão autorizados e em andamento. A candidata está ligada ao commit
  DRE `69716bb0a23e02cc839f1adac0a41fbc521f7f04`; os gates integrais passaram,
  as três imagens por digest foram publicadas e o pacote assinado
  `dre-20260902T061906Z-69716bb0a23e` foi reproduzido.
- A primeira importação foi recusada antes do cache porque o controlador tratou
  o `ConfigMap` sistêmico `kube-root-ca.crt` como objeto proibido. O bundle
  corrigido `5b0b568d1597f6791f6e423224a6b6dc6a89312f76aee537decc553ade2d89f3`
  foi instalado e permitiu importar a release assinada.
- A segunda correção do inventário edge foi instalada pelo bundle
  `f4b0255daa03b989af83e23c28d40fb624307e3bdd8f7fa8f90b44a6d4e1a056`,
  com backup transacional `20260902T064811Z`; a repetição idempotente da
  importação não exibiu `Forbidden`.
- O plano aprovado SHA-256
  `7136dd2106778f011b7b85b5195e24c229377edf4f940d9d8bc53cea38bad1e6`
  iniciou o deploy `20260902T065643Z-f6defcfcb55d`. O `pgBackRest check`
  terminou com código 82 antes das migrations. O rollback passou: produção
  está `release=none`, gate `secrets-only`, PVC `Bound`, PostgreSQL Ready e
  API/worker em zero; `_sqlx_migrations` permanece ausente.
- D038 autoriza somente o diagnóstico fechado desse estado para corrigir a
  causa e retomar o deploy. O bundle de diagnóstico
  `af943097715fb73f32d1aecba8aa6bc28f2b19bf414841357f0a6369c1f30c47`
  foi instalado com backup `20260902T080118Z`. A coleta confirmou R2/stanza
  acessíveis e isolou o código 82: o BusyBox recusava as opções GNU `-e --` de
  `realpath`; confirmou também que o rótulo canônico do namespace ficou vazio.
  O commit DRE `8c5280709b2f648268eb38aae5972f1449facc98` corrige ambos. Os gates
  integrais e uma segunda pilha E2E limpa passaram; as imagens renovadas foram
  publicadas como `dre-app@sha256:9d2e0af0e3857ecd634f185d1c46e8dda99051b2b4b19d0b976d194e48fdd88e`,
  `dre-postgres@sha256:30ef6d4e0e695878f684e6fc50c97c84b903f79e582b9cfc5ad6155d02561cd5`
  e `dre-validation-runner@sha256:1e7ece3835bb075d8a70f023931dccbc74c543496c7ea82d51ee1f91f002ac5b`.
  A release renovada `dre-20260902T094748Z-8c5280709b2f` foi empacotada duas
  vezes com archive SHA-256
  `07980835cfc28c19b8ae2312c68cf08878aaa7f73bc877f0346160cf9161663e`
  e assinatura Ed25519 aprovada. O controlador D039 foi instalado, a candidata
  entrou no cache e a validação descartável passou. A primeira recuperação
  limitada chegou ao `pgBackRest`, recebeu código 50 e compensou corretamente:
  imagem/rótulo anteriores restaurados, gate `secrets-only`, PVC `Bound`, banco
  Ready e migrations ausentes. A repetição diagnosticada confirmou disputa
  transitória do lock pelo `archive-async`; não houve erro de R2 nem corrupção.
  O controlador está sendo renovado com retry classificado e limitado para esse
  caso exato, diretórios efêmeros `0700` e falha imediata para erros diferentes.
  A recuperação e o deploy persistente passaram: release corrente
  `dre-20260902T094748Z-8c5280709b2f`, gate `passed`, nove migrations, PVC
  `Bound` e API/worker/PostgreSQL Ready. A primeira criação de contas falhou
  atomicamente porque o Pod da API não pode assumir `dre_migrator`; D040 está
  preparada para usar um Pod administrativo efêmero sem ampliar esse privilégio.
  Backup/restore, HTTPS e contas ainda não foram concluídos. A chave Android
  definitiva já existe protegida fora do Git, mas o APK definitivo ainda não foi
  gerado. FCM, dispositivo autorizado, saldo inicial e dados financeiros reais
  continuam ausentes.

## PostgreSQL dedicado Blindou I1 autorizado em 2026-08-29

- O processo PostgreSQL nativo continua sendo a única autoridade do Blindou;
  nenhum DSN, migration, dado, writer ou HBA foi alterado.
- O workflow hospedado foi recusado antes dos steps por bloqueio de cobrança.
  Pela D031/D064 temporária, o host concluiu o build/scan efêmero do SHA Blindou
  `753ec66aab3040cd81a766ffeafe1e9cb0850e18`; a estação publicou e releu o
  digest `sha256:2f1c8787a0f689fdc34bf94c59b7f30add5da8c5514930575dc383603a8f3f6d`.
- O bundle assinado foi validado nos namespaces `blindou-data` e
  `blindou-data-image`, com SHA-256
  `729d1caafd1691c3d9bd3ea15cacec791cd97e081f5cc1573ea33b2737ad85d7`.
  O `pull-proof` validou uma imagem, 15 blobs e 157.256.746 bytes.
- O commit de plataforma `8b892b962f4096678c8ae6e0fb89bfe27b25b6de`
  instalou a versão final do `blindou-datactl`; a quarentena `blindou-data`
  permanece `blocked`, sem Secret, PVC, Job, Pod, Service ou workload de banco.
- O estado final é `ready=0 pvc=0 image=none pull_proofs=1 cutover=false`.
  Host, APIWPP e Blindou passaram nas verificações independentes.
- `pull-proof` baixa integralmente o digest pelo PAT GHCR root-only já existente
  e preserva somente recibo. Ele não modifica o cluster e recusa executar se a
  quarentena contiver objeto operacional.
- A execução I1 está pronta para confirmação humana. `foundation`, Secrets
  Kubernetes, PVCs, backup/restore operacional,
  migration, DSN, StatefulSet, I2 e cutover permanecem bloqueados.

## Operação Blindou concluída em 2026-08-27

- A release Blindou `11e21b3319c197ef18440e7f494290b298f2db1e` está ativa.
  Ela limita a carga do Relatório de proteção a uma raiz GraphQL que executa
  sequencialmente as sete leituras existentes, sem aumentar o pool ou alterar
  PostgreSQL.
- O SHA passou nos cinco gates D046, publicou quatro imagens examinadas com
  SBOM/proveniência e zero achado Trivy High/Critical ou segredo. O bundle
  assinado e a prova de pull passaram para quatro imagens, 25 blobs e
  119.734.965 bytes.
- O backup criptografado `blindou-20260827T143510Z`, com 3.052.306 bytes e
  SHA-256 `0ffcbf1eef8b4df0aa9f4be0dfaf3784451198bc4ce14354d235be4f39019614`,
  foi conferido localmente e confirmado offsite antes do rollout.
- A implantação não aplicou migration nova. O estado permanece com 12
  migrations, aplicação e EDGE em `passed`, todos os workloads Ready e
  `redirector=dedicated`.
- Fundação, dados, backup, Cloudflare SaaS, prova GHCR, R2, Pagar.me,
  contenção do host e APIWPP passaram. `api.blindou.com/health`,
  `api.blindou.com/ready` e `app.blindou.com` responderam HTTP 200.
- O link protegido Amazon em `go.guiadoconsumo.com` abriu o destino correto e
  preservou `tag=guia030-20`. O código desconhecido `ZZZ404ZZZ` continuou em
  HTTP 404. A carga fria do relatório respondeu sem erro e somente com
  `redirectAnalyticsOverview`; o novo clique elevou o período a sete acessos:
  quatro humanos, três bots/previews e zero bloqueados.
- `pagarme_runtime_state=active` foi preservado. O estado externo de alertas é
  `deferred_uazapi_resend`; nenhuma chave, plano, webhook ou cobrança foi
  alterada nessa operação.
- Por D025, o `.env` ignorado da estação será retido até a entrada do primeiro
  cliente. Somente o helper fechado pode ler `KEY_SERVIDOR` em memória para os
  bootstraps Blindou explicitamente fixados, incluindo `DataController`; o
  valor não foi aberto, exibido ou indexado.
- D026 está preparada somente no repositório: o controlador ganhou ativação
  Shopee posterior ao deploy, com chave interna root-only, compatibilidade da
  release, journal, rollback, probes, recibo, status e métrica. Nada dessa etapa
  foi instalado ou ativado no host neste estado registrado.

## Auditoria viva de capacidade em 2026-08-26

A auditoria foi executada entre 14:38 e 14:46 UTC por SSH com host key estrita,
somente leitura e operações `status` dos controladores existentes. Não foi
usado `kubectl`, `psql`, kubeconfig, segredo, backup novo, migration, suspensão
ou deploy. Esta seção é a evidência mais recente e substitui, ao descrever o
presente, bullets históricos posteriores que mencionem uma release Blindou
anterior.

Estado final observado:

- host com quatro CPUs lógicas, 15,52 GiB de memória e 9,73 GiB disponíveis;
  o mínimo disponível nas últimas 24 horas foi 9,62 GiB, com swap praticamente
  sem uso;
- filesystem raiz com 455,91 GiB, 252,21 GiB disponíveis e 3% dos inodes usados;
- nas últimas 24 horas, CPU ocupada média de 23,79% e pico de 50,72% em janela
  de cinco minutos; `iowait` médio de 2,64% e pico de 19,69%; carga de cinco
  minutos chegou a 4,39;
- o HDD teve ocupação média de 10,29% e pico de 61,35%, leitura máxima de
  67,50 MiB/s e gravação máxima de 5,06 MiB/s em janela de cinco minutos;
- a interface Fast Ethernet atingiu aproximadamente 4,59 Mb/s de entrada e
  24,65 Mb/s de saída; memória, espaço e rede comportam o perfil SaferWPP de
  laboratório observado, mas HDD, CPU e nó único continuam sem garantia de
  pico de produção ou alta disponibilidade;
- K3s, PostgreSQL, Prometheus, Node Exporter, PostgreSQL Exporter e gateway
  privado do APIWPP estavam ativos, sem unit systemd falha. Prometheus possuía
  somente os targets `node`, `postgresql` e `prometheus`; não havia métricas
  kube-state/cAdvisor para comprovar requests, limits e consumo por namespace.

O APIWPP permaneceu na release `86bb7f886778`, com uma réplica Ready, 18
migrations, smoke aprovado, Service ClusterIP, PVC de 20 GiB e gateway privado
ativo. Seu container usava 1,93 GiB de memória e 0,805 CPU durante uma amostra
de cinco segundos; request/limit da release são `250m/3 CPU` e `512Mi/8Gi`.
Suspender esse workload liberaria execução, mas não o PVC, banco ou backup.

O primeiro `status` Blindou encontrou o lock de outra operação e foi recusado;
o lock não foi tocado. Depois que a operação terminou, o controlador confirmou
release `dc2aa63a24fbe0fa356a03a98d951dde833eca8c`, 11 migrations, aplicação e
EDGE em `passed`, conector Ready, backup criptografado/offsite presente e
runtime Pagar.me ativo. O commit corrente mantém 16 workers. Seus workloads
estáveis declaram juntos `975m/7,35 CPU` e `2336Mi/9Gi` de requests/limits; o
Job de migration adiciona temporariamente `50m/500m` e `128Mi/512Mi`.

O perfil SaferWPP exige oito Pods estáveis, `650m` e `1824Mi` de requests, com
margem mínima de 30%, além de três PVCs e até 24 GiB. O piso de quota versionado
é 12 Pods, `2/7 CPU`, `4Gi/8Gi`, três PVCs e 24 GiB. A quota viva anterior de
`saferwpp-lab`, `750m/1536Mi` de requests, não comporta sequer os `1824Mi`
estáveis e precisa ser substituída declarativamente antes de qualquer deploy.
Keycloak e Control Plane ainda estão ausentes e, portanto, não tiveram consumo
real mensurado.

O gate PostgreSQL falhou:

- primário PostgreSQL 18.6 com `max_connections=50`, três conexões reservadas
  a superuser e PgBouncer do host inativo;
- 41 backends no retrato final: 35 do Blindou, quatro do `clone_wpp` e dois de
  operação/exporter; 34 das conexões Blindou e as quatro APIWPP estavam idle;
- pico de 47 backends em 24 horas e 48 em sete dias, com pico Blindou de 43 e
  pico APIWPP de cinco; zero deadlock e zero temporary bytes nas últimas 24
  horas;
- suspender APIWPP remove no máximo cinco conexões observadas. Somar os dez
  backends runtime e dois slots de migration planejados para SaferWPP excede a
  capacidade segura e pode alcançar o limite físico durante um pico Blindou;
- no momento da auditoria, o contrato SaferWPP presumia teto físico 60,
  diferente dos 50 reais. Aumentar `max_connections` isoladamente não é aceite
  de capacidade.

Depois dessa evidência, D023 resolveu o alvo: um segundo cluster PostgreSQL 18
exclusivo do SaferWPP na porta 55432, com teto 24 e recursos próprios. Isso é
estado desejado, não estado vivo; o cluster, sua stanza de backup e seu exporter
ainda não existem no servidor.

Conclusão: CPU, memória, disco e rede permitem continuar o desenho do lab com
os riscos registrados. A rota PostgreSQL conjunta foi reprovada e não será
usada; a rota exclusiva foi decidida, mas ainda precisa ser implementada e
validada. Quota viva, backup SaferWPP, Keycloak/Control Plane e controlador
próprio continuam gates bloqueantes. Nenhum estado runtime foi alterado.

## Host verificado

- Hostname: `apiwpp`.
- Sistema: Ubuntu Server 24.04.4 LTS.
- Kernel observado: Linux 6.8.0-137-generic.
- CPU: Intel Core i5-3470, 4 núcleos e 4 threads.
- Memória: aproximadamente 15 GiB; cerca de 10 GiB disponíveis na auditoria.
- Swap: 4 GiB, com aproximadamente 247 MiB utilizados.
- Disco: HDD SATA de 500 GB; filesystem raiz de 456 GB, 140 GB usados e
  297 GB disponíveis.
- Temperatura observada por métrica: 45 graus Celsius; SMART saudável.
- Interface ativa: `enp2s0`, Fast Ethernet de 100 Mb/s.
- Segunda interface física `eno1` observada inativa; ela não é uma barreira de
  segurança porque pertence ao mesmo host.
- IPv4 reservado por DHCP: `192.168.100.59/24`.
- IPv6 público chegou a ser observado em `enp2s0`, com prefixo `/64` e rota
  padrão pela ONT. Após o reboot de 2026-08-21 ele foi reativado pelo
  `systemd-networkd`; a correção persistente passou a reaplicar o sysctl depois
  de `network-online` e o estado atual voltou a ser desabilitado.
- PC administrativo: `192.168.100.57`.
- WireGuard `wg-apiwpp`: `10.203.0.2/30`.

## Segurança e exposição

- Gateway/ONT observado em `192.168.100.1`: Huawei HG8145V5, perfil `OI2`.
- O servidor e a estação administrativa ainda compartilham
  `192.168.100.0/24`; a rota padrão do host aponta diretamente para a ONT.
- Não existe firewall externo entre servidor e residência. A camada de host da
  exceção temporária está ativa: UFW bloqueia redes privadas e entrada lateral,
  e o IPv6 da `enp2s0` está desabilitado. A fundação Kubernetes interna do
  Blindou está provisionada. Somente o conector Cloudflare está ativo em
  `blindou-edge`; os workloads e a release continuam bloqueados. O schema
  possui oito migrations já aplicadas, mas nenhum deploy comercial do Blindou
  está publicado no estado atual.

- SSH utiliza chave pública permanente, usuário `apiadmin` e identidade de host
  validada. O acesso é limitado ao PC administrativo.
- UFW está ativo, com entrada e roteamento negados por padrão.
- Do PC administrativo, apenas TCP 22 e TCP 6443 responderam.
- TCP 443, 5432, 8090, 8443, 9090, 9100, 9187 e NodePorts testados não
  responderam pela LAN.
- AppArmor e atualizações automáticas estão habilitados.
- A API Kubernetes não está publicada na internet.
- `apiwpp-deployctl` e `apiwpp-backupctl` estão instalados como controladores
  restritos. `pixel-deployctl` e `saferwpp-deployctl` ainda estão ausentes; por
  isso Pixel e SaferWPP não possuem caminho autorizado de alteração no host.
- A candidata dos controladores SaferWPP
  `swpc-20260827T010424Z-5e8b21d60cd9`, commit
  `5e8b21d60cd9c90546434e2f45ee366b892ff797`, foi construída e assinada fora
  do servidor. A plataforma possui verificador e bootstrap, mas nada foi
  instalado; esse artefato não altera o estado vivo nem autoriza deploy. A
  candidata, a release da aplicação e o commit de plataforma
  `a8127c90757e2f62340ee814881374488060816e` estão no staging user-owned
  `/home/apiadmin/saferwpp-platform-bootstrap-a8127c9-5e8b21d`, após validação
  de hashes e contratos no Linux.
- `blindou-deployctl` está instalado como root com suporte fechado ao conector,
  às credenciais Cloudflare for SaaS/GHCR, à release assinada e à prova de pull
  das quatro imagens privadas. O SHA-256 da
  fonte final é
  `1aa65f272706e59923bca30a9bbb3fe5edfecc04f214554e9d8b31ed0a5e1553`;
  o arquivo instalado no host possui o mesmo hash.
  A interface sudo sem senha continua restrita às operações fechadas do
  controlador; rollbacks destrutivos continuam fora da automação. D018 permite
  usar a senha local somente nos dois bootstraps versionados e fechados.
- `blindou-hostctl` corrigido está instalado como root com SHA-256
  `b51278e6b490a87483156b66968e381593b23a9b5b48a784756549f151e284be`.
  A primeira aplicação de 2026-08-19 foi revertida depois que o gate detectou
  falha de DNS; a segunda aplicação passou. Em 2026-08-21 o reboot revelou que
  o `systemd-networkd` reativava IPv6 depois do sysctl inicial. O unit
  `blindou-temporary-containment.service` agora está habilitado e ativo depois
  de `network-online`, e o gate voltou a passar com IPv6 desabilitado.
- O staging atual em `/home/apiadmin/blindou-platform-bootstrap-ghcr` contém
  somente artefatos públicos versionados, sem credencial. Os dois controladores
  instalados possuem o mesmo SHA-256 das fontes locais validadas.
- Não existe unit systemd `cloudflared` no host. O único conector roda como Pod
  restrito no namespace `blindou-edge`.

## K3s e workloads

- K3s `v1.36.2+k3s1`, nó único.
- Secrets do Kubernetes criptografados em repouso.
- Traefik e ServiceLB desabilitados.
- Kubeconfig administrativo permanece root-only no servidor.
- `apiwpp`: Deployment com uma réplica Ready, Service ClusterIP e PVC local de
  20 GiB. Smoke test registrado como aprovado.
- Os dois pods antigos em `ContainerStatusUnknown` foram removidos; somente a
  réplica ativa e Ready permanece.
- O verificador do `apiwpp` seleciona exatamente o único pod Running e Ready,
  sem aguardar réplicas órfãs de ReplicaSets anteriores.
- Os namespaces vazios `cia-pixel-lab` e `saferwpp-lab` estão ativos com Pod
  Security `restricted` v1.36, conta padrão sem token, ResourceQuota,
  LimitRange, negação padrão de rede e liberação somente de DNS.
- Uma ValidatingAdmissionPolicy recusa Service `NodePort`, `LoadBalancer` e
  `externalIPs` nos namespaces gerenciados; o teste server-side de NodePort foi
  recusado.
- `blindou-production` permanece sem workloads, com Pod Security `restricted`,
  default deny e gate `secrets-only`; contém somente Secrets, ConfigMaps e
  controles admitidos por esse gate. A candidata `48bc9f0` concluiu as oito
  migrations, mas o worker `report-thumbnail` recusou iniciar sem R2. O
  rollback de primeira release removeu workloads e Services, restaurou a
  contenção e manteve `current_release` ausente.
  `blindou-edge` está em gate `connector-only` e contém somente os três objetos
  permitidos do Tunnel: um Deployment com um Pod Ready, ServiceAccount e Secret
  exclusivos. Não existe Service, PVC, release Blindou corrente nem outro
  workload de aplicação nesses namespaces.
- O audit log do Kubernetes está ativo em nível `Metadata`, sem corpos de
  Secrets e com limites de 14 dias, cinco arquivos e 50 MiB por arquivo.
- Pixel/CIA e SaferWPP não estão implantados no estado observado. Pixel/CIA
  continua sem workloads. Por D022, o SaferWPP só poderá ocupar o slot residual
  depois da auditoria de capacidade, com APIWPP suspenso e verificado; no estado
  atual, o APIWPP permanece ativo.

## Dados, backup e observabilidade

- PostgreSQL 18.6 roda no host, fora do K3s, com TLS, checksums e SCRAM.
- pgBackRest 2.59 possui repositório local e Cloudflare R2; WAL, timers e
  métricas estão saudáveis.
- Em 2026-08-15, 23,5 GB foram restaurados do R2 em cluster isolado; checksums e
  18 migrations foram confirmados. A operação levou aproximadamente 542
  segundos no HDD e limpou o ambiente temporário.
- Backups incrementais local e R2 foram forçados e concluídos antes da
  manutenção.
- O backup consistente do K3s está em
  `/var/backups/shared-lab/20260815T113334Z`, root-only, com SHA-256 validado. É
  uma cópia no mesmo HDD e não protege contra falha física.
- O database `blindou` foi criado com quatro logins sem privilégios
  administrativos e papéis separados para migration, runtime, redirector e
  conector ML. Conexões do CIDR K3s exigem `hostssl`, certificado de cliente
  confiável e SCRAM; as migrations `0001` a `0008` estão registradas.
- O banco operacional avançou posteriormente para 11 migrations. No teste de
  2026-08-26, o hostname próprio alcançou o redirector, mas o link válido
  respondeu `not found`: `blindou_redirect_login` ainda pertence ao grupo amplo
  `blindou_app`, enquanto `FORCE RLS` não aceita o bypass tentado pelo processo.
  D024 e a migration Blindou `0012` preparam `blindou_redirector` com grants
  mínimos e a revogação pós-migration do legado. Controlador, papel e migration
  ainda não foram instalados ou aplicados no host.
- O primeiro backup lógico Blindou é `blindou-20260820T111734Z`, armazenado
  somente como envelope CMS AES-256-GCM. O catálogo foi validado por
  `pg_restore` antes da criptografia; uma prova local abriu o envelope com a
  chave de recuperação DPAPI, confirmou o cabeçalho `PGDMP` e apagou chave e
  dump temporários. SHA-256 do envelope:
  `048b0ac1413a39790f3a38755185179e0d881a46ffd4430ef89f8a6178782d4f`.
- O timer `blindou-platform-metrics.timer` está habilitado e ativo. Prometheus
  coletou fundação `1`, dados `1`, coleta `1`, timestamp do backup e gates `0`
  para os dois namespaces, pois `connector-only` não equivale a liberação de
  release. A presença segura local da credencial Cloudflare for SaaS também é
  publicada como gauge, sem consultar ou revelar o valor durante a coleta.
- O API token Cloudflare for SaaS está fora do Kubernetes em
  `/etc/blindou/cloudflare-saas/api-token`, sob diretório `0700` e arquivo
  `root:root 0600`. O controlador confirmou token ativo e acesso de leitura à
  coleção de custom hostnames da zona `blindou.com`; isso não libera criação de
  hostname, migration ou release.
- O bucket de mídia `blindou-media-prod` está criado no R2 com domínio público
  `media.blindou.com` ativo, TLS mínimo 1.2, `r2.dev` desabilitado e CORS
  limitado a `GET`/`HEAD` de `https://app.blindou.com`. A credencial de objetos
  restrita ao bucket foi entregue por entrada protegida e está no cofre
  root-only do host. O controlador comprovou o ciclo vivo de escrita, leitura
  pública com comparação SHA-256 e exclusão do sentinela. O estado autenticado
  é `r2_runtime_credential_state=secure_local_store` e
  `r2_runtime_live_probe=passed`; o runtime técnico foi republicado sem liberar
  uma release corrente.
- Prometheus, Node Exporter e PostgreSQL Exporter estão `up`, com três targets
  saudáveis e zero alertas ativos.
- O coletor `stat_bgwriter`, incompatível com PostgreSQL 18 no exporter 0.15,
  foi desabilitado. Exporter e gateway privado agora acompanham o restart de
  PostgreSQL e K3s por `PartOf`.
- O destino externo aprovado para notificações é `gleisonsette@gmail.com`, mas
  ainda não existe provedor autenticado, credencial nem teste real de entrega.
- A credencial GHCR do host foi validada em 2026-08-21 com exatamente
  `read:packages` e está no cofre root-only fora do Kubernetes. O Secret
  `blindou-ghcr-pull` continua ausente porque só pode ser materializado durante
  uma release autorizada.
- A `main` Blindou foi publicada no SHA
  `1265c3be1e808d522887f38ff47e9a110533677a`. O Pages concluiu o deployment
  `c5a6e0db-6b0b-4f04-9830-9a721934824e`; `app.blindou.com` serve o painel e a
  API continua ausente.
- O workflow GitHub `32534879401` passou gates Rust/PostgreSQL, scans e
  publicação das imagens privadas desse SHA. A release assinada foi validada e
  armazenada no cache do controlador com bundle SHA-256
  `d22fb791e2fd9c68d95b98493a97a03c724cb83f66bc536a2417dfa1889035fb`.
  `current_release` continua ausente, os gates permanecem `blocked` e nenhum
  workload, Secret Kubernetes ou migration foi aplicado.
- A candidata Blindou `0ba8384` passou nos gates de publicação e no scan
  fechado `32550929031`. O bundle assinado está validado no cache do host e a
  prova integral comprovou backend, redirector, NATS e `cloudflared`: quatro
  imagens, 24 blobs e 111.683.519 bytes. O recibo root-only registra
  `ghcr_candidate_pull_proof=0ba83846102a480ae79d44fce971de13b91f9d04`.
  `current_release` permanece ausente, `blindou-production` continua `blocked`
  com zero objetos operacionais, e nenhum Secret Kubernetes, migration ou
  workload foi criado.
- A candidata `794d92235ea5ad14a001bac103f23435bb32fcf0` passou no workflow
  `32602526360`, na assinatura e na prova integral das quatro imagens. O backup
  offsite `blindou-20260822T225840Z` foi confirmado antes do `apply`. NATS e
  Redis ficaram prontos, mas o Job `blindou-migrate-794d92235ea5` não concluiu
  em 600 segundos; o rollback automático restaurou `secrets-only` e
  `connector-only`, o conector voltou a Ready e a API pública permaneceu em
  `502`. UAZAPI, Resend e Pagar.me continuam ausentes.
- Com o controlador de diagnóstico instalado, a repetição identificou a causa
  em segundos: `0001` tentou criar `pg_stat_statements`, operação recusada para
  `blindou_migration_login` por menor privilégio. A contenção foi novamente
  restaurada. A correção preparada mantém a extensão administrativa na
  fundação, sob owner `postgres`, e remove sua criação/comentário do baseline da
  aplicação antes da primeira migration concluída. O controlador `5aaae67` foi
  instalado, `provision-data` criou a extensão com owner `postgres`,
  `verify-data` passou e o status confirmou `migration_history_count=0` e
  `pg_stat_statements=present`. O novo SHA Blindou `ccc4edd` está no workflow
  externo `32605412093`; ainda não existe release corrente.
- O workflow `32605412093` aprovou `ccc4edd`, e a prova no host confirmou quatro
  imagens, 25 blobs e 113.292.669 bytes. O backup criptografado
  `blindou-20260823T002003Z` foi copiado e confirmado offsite antes do `apply`.
  `0001` foi aplicada e registrada; `0002` falhou ao tentar revogar permissão
  de `pg_stat_statements_reset`, cujo owner é `postgres`. O rollback restaurou
  `secrets-only`/`connector-only`, o conector ficou Ready e
  `current_release` permaneceu ausente. O status autenticado confirmou
  `migration_history_count=1`, `pg_stat_statements=present` e nenhum provedor
  externo configurado. Esse estado foi posteriormente substituído pela
  candidata `48bc9f0`.
- O workflow `32645928340` aprovou `8e17210e34767935158ba5c8b863b48724297a93`,
  inclusive bootstrap real com login runtime `NOBYPASSRLS`. A prova integral
  confirmou quatro imagens, 25 blobs e 113.212.411 bytes. O backup
  `blindou-20260823T152218Z` foi conferido e confirmado offsite. O rollout
  concluiu com oito migrations já aplicadas, `current_release=8e17210`,
  aplicação e EDGE em `passed`, Tunnel Ready, R2 comprovado e todos os
  workloads Ready. UAZAPI, Resend e Pagar.me permanecem ausentes. A janela
  protegida criou `gleisonsette@gmail.com` como `super_admin`; o comando
  concluiu e validou o login real pela API pública sem exibir tokens.
- Em 2026-08-25, esse estado foi sucedido pela release
  `ab15a31b8b0538b772763cb0b5a52d6ef3c7c463`. A prova das quatro imagens, o
  backup criptografado `blindou-20260825T092915Z` com cópia offsite, a migration
  `0009` e o rollout passaram. O runtime possui nove migrations, aplicação e
  EDGE em `passed`, todos os workloads Ready e
  `pagarme_runtime_state=active`. UAZAPI e Resend permanecem ausentes; nenhum
  efeito financeiro real foi criado na validação.

## Manutenção

- Os 15 pacotes identificados foram atualizados, incluindo PostgreSQL 18.6,
  libpq, pgBackRest 2.59, linux-firmware, Kerberos e Apport.
- Não há pacote atualizável restante nem reboot requerido após a manutenção.
- K3s, PostgreSQL, WireGuard, gateway privado, observabilidade e `apiwpp`
  passaram na verificação final; não há unit systemd falha.
- Depois da fundação Blindou, `blindou-hostctl verify`,
  `apiwpp-deployctl verify`, os verificadores de fundação, dados, backup,
  conector EDGE e credencial SaaS do `blindou-deployctl`, a recuperação do
  backup e a coleta Prometheus passaram; zero unit systemd falhou e nenhum
  arquivo plaintext de backup permaneceu em `/var/tmp`.
- A contenção temporária passou em DNS, HTTPS pública, bloqueio da ONT, K3s,
  `apiwpp` e reaplicação idempotente. IPv6 da `enp2s0` está desabilitado.
- Depois do reboot de 2026-08-21, a persistência pós-rede, o cofre GHCR, o
  bundle assinado, o conector EDGE, Cloudflare for SaaS, fundação, dados,
  backup e `apiwpp` foram revalidados; zero unit systemd falhou.
- Do PC administrativo, somente TCP 22 e 6443 responderam. TCP 443, 5432,
  8090, 8443, 9090, 9100, 9187 e 30000 permaneceram inacessíveis pela LAN.
- Não existe nobreak com desligamento controlado.
- O HDD e a interface de 100 Mb/s servem para validação funcional, não para
  afirmar capacidade de produção ou alta disponibilidade.

## Estado dos repositórios relacionados

- `C:\github\servidor` usa a branch `main` e o remoto público
  `https://github.com/GleisonSette/servidor`.
- O conteúdo é publicado sob licença MIT, titular Gleison Sette, ano 2026.
- `C:\github\saferdock\saferwpp` mantém a base de código `e8a0427`; o commit
  documental `d8fce28` adicionou somente `AGENTS.md`, `README.md` e
  `README-SERVIDOR-LOCAL.md`.
- `C:\github\cia` possuía alterações e artefatos Pixel ainda não commitados.
- `C:\github\cintia\apiwpp` possuía várias alterações locais não commitadas.
- Os guias foram commitados isoladamente como `31e9637` no apiwpp e `608a3de4`
  no CIA/Pixel, sem incluir, reverter ou assumir autoria das demais mudanças já
  existentes nesses repositórios.
- A estabilização alterou de forma localizada no `apiwpp` o verificador de
  deploy, a configuração/instalador do PostgreSQL Exporter e o unit do gateway
  privado. Essas alterações permanecem no working tree existente para não
  misturar ou assumir autoria das demais mudanças do usuário.
- Alterações futuras nesses repositórios devem preservar o trabalho existente
  e usar commits separados por repositório.
