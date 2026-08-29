# Arquitetura da plataforma compartilhada

metadata:
  canon_id: canon-arquitetura-plataforma
  source_path: memory/canon/arquitetura-plataforma.md
  generated_from: decisão do usuário, auditoria e requisitos de apiwpp/Blindou/SaferWPP
  updated_at: 2026-08-29
  status: canonical

## Objetivo e limite

O Blindou permanece sempre ativo e intacto. A capacidade residual do servidor
será usada por um slot alternável entre APIWPP e SaferWPP, com exclusão mútua:
somente um deles poderá manter workloads ativos por vez. No estado vivo atual,
o APIWPP permanece ativo e o SaferWPP permanece vazio. O controlador
compartilhado do slot está instalado e inicializado; os controladores SaferWPP
continuam apenas nos repositórios e no staging. Pixel/CIA não recebe workloads.
Não há acesso de clientes ao
host ou ao Kubernetes. O cluster fornece isolamento lógico, não isolamento
forte contra comprometimento do kernel/root.

## Identidades

- Uma identidade SSH administrativa por pessoa/dispositivo.
- Uma chave de assinatura de release por projeto.
- Um controlador de deploy restrito por projeto; nenhuma automação recebe shell
  administrativo genérico.
- D018 permite que o helper local versionado entregue `KEY_SERVIDOR` por
  `stdin` somente aos bootstraps fechados dos controladores Blindou. O helper
  fixa host, staging e nomes dos instaladores e não aceita comando livre nem
  rollback destrutivo.
- D027 concede uma segunda capacidade, separada e de uso único, ao helper
  `SecondarySlot.SudoBootstrap.psm1`: materializar somente o controlador
  compartilhado do slot a partir de um arquivo produzido pelo commit aprovado,
  com host, staging, SHA-256, cache root-owned e bootstrap fixos. Essa concessão
  não instala fundação ou controlador SaferWPP e não oferece `sudo` genérico.
- Uma ServiceAccount por workload, com token desabilitado quando não necessário.
- Secrets, credenciais de banco e certificados separados por finalidade.

SSH identifica o operador. O isolamento entre projetos é feito por assinatura
de artefato, namespaces, RBAC, ServiceAccounts, NetworkPolicy, dados e limites.

Estado dos controladores em 2026-08-27:

- `apiwpp-deployctl` e `apiwpp-backupctl` estão instalados, root-owned e são os
  únicos caminhos sem senha do apiwpp; as novas operações do slot existem no
  repositório APIWPP, mas a versão instalada ainda não foi reconciliada;
- `secondary-slotctl` está instalado e inicializado na geração 1, com APIWPP
  ativo, SaferWPP vazio, atestado root-only, admissão fail-closed, timer,
  métricas e sudoers restrito;
- `pixel-deployctl` ainda não existe; `saferwpp-deployctl`,
  `saferwpp-backupctl` e `saferwpp-secretsctl` possuem release assinada, SBOM,
  scan, proveniência e verificador independente. A plataforma possui bootstrap
  fechado; os artefatos estão em staging user-owned validado no Linux, mas
  ainda não foram instalados no host;
- `blindou-deployctl` está instalado e governa a fundação, dados, backup,
  conector Cloudflare e releases assinadas do Blindou;
- até a instalação de cada controlador, o respectivo Codex de aplicação pode
  preparar artefatos e confirmar o acesso, mas não alterar o servidor;
- a capacidade administrativa com senha do usuário humano não é uma interface
  de automação e não pode ser usada para contornar um controlador ausente.

As identidades Kubernetes dos controladores SaferWPP são certificados cliente
exclusivos, emitidos pela CA cliente local do K3s sem grupo administrativo e
guardados em kubeconfigs `root:root` `0600`. A plataforma renova os certificados
com 365 dias de validade quando faltarem 45 dias, confirma o CN devolvido pelo API
Server e alerta com 30 dias de antecedência ou quando a reconciliação ficar
mais de 26 horas sem sucesso. Falha de uma renovação restaura o kubeconfig
anterior quando ele existia. Essas identidades não reutilizam kubeconfig,
certificado, Role ou credencial do APIWPP ou do Blindou.

## Slot alternável APIWPP/SaferWPP

O estado-alvo definido por D022 é:

```text
Blindou sempre ativo
  +-- APIWPP ativo / SaferWPP suspenso
  `-- APIWPP suspenso / SaferWPP ativo
```

Não existe estado autorizado com APIWPP e SaferWPP ativos simultaneamente. A
transição também não pode alterar recursos Blindou. Suspender APIWPP reduz seus
workloads a zero réplicas, mas preserva namespace, objetos declarativos,
Service, PVC, banco `clone_wpp`, papéis, migrations, ConfigMaps, Secrets,
imagens, releases e backups. O gateway privado permanece ativo para não quebrar
o contrato de verificação do Blindou.

No repositório APIWPP, o `apiwpp-deployctl` já implementa suspensão,
verificação suspensa, retomada e recusa de retomada quando houver workload
SaferWPP. No repositório SaferWPP, o `saferwpp-deployctl` já implementa a recusa
de ativação enquanto o APIWPP não estiver suspenso e verificado. Cada transição
usa lock, release/ação assinada, auditoria,
verificação negativa do outro lado e rollback. Enquanto esses controles não
estiverem instalados e verificados no host, a alternância falha fechada e
nenhuma operação SaferWPP é autorizada.

A fonte de verdade compartilhada é o arquivo regular `root:root` `0600`
`/var/lib/servidor-local/secondary-slot/state`, escrito atomicamente somente por
`secondary-slotctl`. O contrato possui sete campos em ordem fixa: schema, slot,
generation, ocupante ativo, contagens APIWPP/SaferWPP e timestamp com offset. O
lock global é `/run/lock/servidor-local-secondary-slot.lock`.

O gate Kubernetes usa `ValidatingAdmissionPolicy` com `failurePolicy: Fail` e
exige que o recurso instalado coincida com o manifesto fixo pertencente a root.
Ele nega
Deployment, StatefulSet, DaemonSet, ReplicaSet,
ReplicationController, Job, CronJob ou Pod que tente executar em namespace
membro inativo ou sem estado. A reserva root-only atualiza o atestado antes de
abrir os namespaces do novo ocupante. Estados ausentes, inseguros, divergentes,
parciais ou com os dois lados ativos não liberam nenhum membro.

A reconciliação explícita recompõe a admissão pelo manifesto fixo, observa o
runtime e só publica APIWPP, SaferWPP ou `none` quando o resultado é inequívoco.
Runtime ambíguo permanece bloqueado e gera auditoria,
métrica e evento no outbox operacional. Falhas resolvidas continuam no
histórico JSONL para futura ingestão pela ferramenta administrativa; auditoria
e outbox mantêm o arquivo atual e até cinco rotações locais limitadas a 16 MiB
cada, enquanto o histórico mantém no máximo 256 atestados e um estado compacto
root-only preserva apenas os IDs não resolvidos para a coleta de métricas. Antes
e depois de cada transição, o controlador verifica saúde e fingerprint estável
do Blindou, sem invocar seu controlador sob o lock global e sem alterar qualquer
recurso Blindou.

Cada repositório de aplicação possui `README-SERVIDOR-LOCAL.md` e uma referência
obrigatória em `AGENTS.md`. O guia define ownership, comandos permitidos,
proibições, verificação e escalonamento para a plataforma.

## Topologia temporária de contenção

```text
Internet -> Huawei HG8145V5, sem porta publicada
                    |
              KNUP KP-SW105
                    |
          Ubuntu + UFW + K3s
             |             |
          apiwpp        Blindou
                         +-- blindou-edge/cloudflared
                         +-- blindou-production
```

UFW nega LAN, RFC1918, CGNAT e link-local pela interface física tanto para
processos do host quanto para tráfego encaminhado dos Pods. Entrada da LAN é
negada, com exceção de 22/6443 a partir do PC administrativo; DNS/DHCP são
preservados. IPv6 é desabilitado na interface para fechar o `/64`
compartilhado. `blindou-edge` inicia TCP/7844 para Cloudflare e acessa somente
API/redirector por ClusterIP. Saída HTTPS pública da aplicação permanece
temporariamente disponível.

Esses controles não são prova de contenção se o host for comprometido por
`root`. A decisão expira no cutover Vultr.

Namespaces de infraestrutura não contam como novos projetos. Eles só serão
criados quando uma dependência compartilhada realmente for implantada.

## Baseline de cada espaço

- Pod Security `restricted`, fixado à versão Kubernetes validada.
- NetworkPolicy com negação padrão de entrada e saída.
- Liberação inicial somente para DNS; cada dependência recebe regra explícita.
- ResourceQuota e LimitRange conservadores.
- Service ClusterIP; NodePort, LoadBalancer, externalIPs, hostPort e hostNetwork
  são negados por padrão.
- Containers sem root, sem privilege escalation, capabilities removidas,
  seccomp RuntimeDefault e filesystem raiz somente leitura quando possível.
- Requests, limits, probes, shutdown gracioso e logs estruturados obrigatórios.

Baseline aplicado em 2026-08-15:

- `cia-pixel-lab`: até 12 pods, quatro PVCs, 30 GiB de requests de storage,
  500m/768Mi de requests agregados e 1500m/2Gi de limits agregados;
- `saferwpp-lab`: até 24 pods, oito PVCs, 60 GiB de requests de storage,
  750m/1536Mi de requests agregados e 2500m/4Gi de limits agregados;
- ambos começam vazios, negam todo tráfego de entrada/saída exceto DNS e
  recusam Services que exponham NodePort, LoadBalancer ou externalIPs.

As cotas são orçamento inicial, não promessa de capacidade. Serão revistas com
métricas durante a implantação real.

Alvo declarativo fechado em 2026-08-26, ainda não aplicado:

- `saferwpp-lab`: 12 pods, três PVCs, 24 GiB de requests de storage, 2 CPU/4Gi
  de requests e 7 CPU/8Gi de limits agregados;
- `saferdock-identity`: namespace vazio exclusivo do Keycloak, até dois pods,
  500m/1Gi de requests e 1500m/2Gi de limits, sem PVC até existir contrato de
  dados próprio;
- `saferdock-platform`: namespace vazio exclusivo do Control Plane, até dois
  pods, 250m/512Mi de requests e 1 CPU/1Gi de limits, sem PVC até existir
  contrato de dados próprio;
- cada fronteira possui ServiceAccount padrão sem token, Pod Security
  `restricted` v1.36, default deny e somente DNS liberado inicialmente.

Os valores aplicados em 2026-08-15 continuam descrevendo o estado vivo até uma
janela operacional específica reconciliar os novos manifests.

`blindou-production` e `blindou-edge` nascem vazios, com gate `blocked`, quota
zero para objetos operacionais, Pod Security `restricted`, default deny e
admissão adicional. Após autorização explícita, somente `blindou-edge` pode
avançar para `connector-only`: quota de um Pod e um Secret, nenhum Service/PVC e
admissão limitada ao `blindou-cloudflared` imutável. `blindou-production`
permanece bloqueado até a primeira release passar todos os gates. Quotas e
políticas de quarentena pertencem à plataforma; contas, PVCs e políticas dos
workloads continuam pertencendo ao repositório Blindou e só entram depois do
gate completo.

`blindou-data` é uma terceira fronteira Blindou, de papel `data`, governada
separadamente. O bootstrap cria apenas namespace `blocked`, quota zero,
ServiceAccount default sem token, Pod Security `restricted`, default deny e
admissão própria. A política geral da aplicação seleciona somente papéis
`application` e `edge`, portanto não pode decidir Pods de dados.

`blindou-datactl` é o único controlador dessa fronteira. Seu `pull-proof`
valida o bundle assinado e baixa integralmente a imagem privada usando o PAT
GHCR root-only por `stdin`, mas não modifica Kubernetes. Antes e depois exige
gate `blocked` e zero Deployment, StatefulSet, DaemonSet, Job, CronJob, Pod,
Service, Secret e PVC. `foundation` permanece outro comando e outra
autorização, pois materializa a base candidata e a prova via Job.

## Dados no host

O mesmo processo PostgreSQL 18 do host continua atendendo somente `apiwpp` e
Blindou. A suspensão do APIWPP preserva integralmente o banco `clone_wpp` e seu
backup. A D023 proíbe ligar o SaferWPP a esse processo ou à porta 5432.

D028 substitui essa topologia somente como destino do Blindou. Até I2, o banco
nativo permanece autoridade. O destino é um PostgreSQL 18 singleton em
`blindou-data`, com dois PVCs de 40 GiB, TLS, roles, Secrets, backup e rede
exclusivos, `max_connections=24`, WAL lógico, duas senders e dois slots. A
imagem deriva da base oficial 18.6 imutável, remove somente `gosu` e snakeoil e
roda como UID/GID 999. Container não isola kernel, HDD, energia ou `root`; a
migração Vultr continua sendo a fronteira física final.

Dump lógico, base backup e WAL chegam cifrados ao PVC de staging; restore-base
usa um terceiro PVC e nunca o volume da autoridade. `archive_timeout=0` evita
custo recorrente antes de fechar RPO, retenção e offsite. Nenhum desses volumes,
Secrets ou workloads é criado pela instalação do controlador ou por
`pull-proof`.

O laboratório SaferWPP usará, no mesmo servidor físico, um segundo
cluster/processo PostgreSQL 18 exclusivo `saferwpp-lab` na porta 55432, com
banco, papéis, TLS, diretórios, limites, stanza pgBackRest e exporter próprios.
O PgBouncer exclusivo no namespace `saferwpp-lab` poderá abrir no máximo dez
backends nesse cluster. Nenhum produto acessa o banco ou a credencial de outro.

O repositório agora declara `postgresql@18-saferwpp_lab.service` na slice
`saferwpp-postgresql.slice`, configuração/HBA próprios, repo1 local, bucket R2
exclusivo `saferwpp-postgres-backup-lab`, timers, exporter em
`127.0.0.1:9188`, coleta textfile e alertas. O contrato
`saferwpp.backup-preflight/v2` exige restore-base antes do database e restore
pós-migration antes do rollout. A prova `foundation` mantém
`postMigrationRestore` nulo; a prova `rollout` exige `rolesVerified`,
`grantsVerified` e `rlsVerified` verdadeiros. Certificados, senhas,
endpoint/credenciais R2 e
DSN do exporter permanecem fora do Git. Esse estado é somente declarativo: o
cluster, a stanza, o bucket, o exporter e os timers ainda não existem no host.

A fundação Blindou prepara quatro logins sem privilégio administrativo. As
conexões vindas do CIDR dos Pods exigem senha SCRAM e certificado assinado pela
CA cliente exclusiva do Blindou. Por D024, o login do redirector deve pertencer
ao grupo dedicado `blindou_redirector`, `NOLOGIN` e `NOBYPASSRLS`, e não aos
grupos amplos `blindou_app` ou `blindou_runtime`. A migration `0012` define os
grants mínimos e as policies RLS; o controlador prepara o grupo antes da
migration e revoga o legado somente depois de seu registro. Essa mudança está
declarada, mas ainda não instalada nem aplicada no host. O backup físico
pgBackRest continua abrangendo o cluster compartilhado; adicionalmente o
database Blindou recebe dump lógico isolado, validado e criptografado para uma
chave de recuperação mantida fora do servidor.

NATS e Redis do Blindou pertencem somente ao produto e rodam no seu namespace.
O namespace Pixel/CIA permanece vazio. O SaferWPP também permanece vazio no
estado atual e só poderá receber banco, mensageria, identidade ou armazenamento
depois que backup, capacidade, controlador próprio e exclusão mútua estiverem
implementados e verificados.

As miniaturas de relatórios e as mídias de ofertas do Blindou usam o bucket R2
exclusivo `blindou-media-prod`, publicado somente em `media.blindou.com`. Esse
bucket é independente do repositório R2 do pgBackRest. A identidade do runtime
possui somente leitura e gravação de objetos no bucket Blindou; não administra
buckets e não alcança os buckets de outros produtos. A credencial permanece em
cofre `root-only` no host e é materializada apenas em `blindou-core-secrets`.
Antes de cada liberação de gate, o controlador executa um ciclo S3 assinado de
escrita, leitura pública com comparação de SHA-256 e exclusão do sentinela.

## Entrada HTTP

O primeiro acesso usa ClusterIP e port-forward administrativo. Um ingress
interno poderá ser adicionado depois, limitado ao PC administrativo e sem abrir
80/443 para a rede residencial.

O Blindou usa Pages e Tunnel; durante a exceção o conector fica em
`blindou-edge` e alcança API/redirector por ClusterIP. Access/mTLS protege
administração e integrações máquina-a-máquina no edge Cloudflare; o Tunnel
autentica o conector pelo token próprio. A ONT residencial não recebe DMZ host,
UPnP ou redirecionamento de porta para o servidor.

## Deploy e rollback

- Build reproduzível e verificado antes do servidor.
- Imagem OCI imutável por digest, SBOM e scan de vulnerabilidade/segredo.
- Imagens próprias privadas no GHCR; o servidor recebe um PAT classic com
  exatamente `read:packages`, sem `repo`, escrita, exclusão ou workflow.
- Build/test/publicação usam runner efêmero hospedado pelo GitHub, manual e
  restrito ao SHA da `main`. O publicador usa `GITHUB_TOKEN` por job, produz
  SBOM/proveniência e scan; não acessa host, banco ou segredo operacional.
- Manifesto de release assinado por chave exclusiva do projeto.
- Controlador root-owned valida assinatura, digest, escopo e lock.
- O controlador aceita uma interface fechada; não recebe comando shell,
  caminho arbitrário, kubeconfig root ou manifesto fora do contrato.
- A credencial R2 chega por `stdin` em dois campos protegidos, nunca pela sessão
  do navegador, argumento, arquivo `.env`, log ou repositório. O controlador
  fixa conta, bucket e domínio público e recusa release sem uma prova viva.
- Migration é bloqueante e usa papel separado.
- Rollout, smoke test e rollback preservam a versão anterior.
- A credencial GHCR permanece root-only fora do Kubernetes enquanto o runtime
  está bloqueado. O controlador materializa `blindou-ghcr-pull` apenas durante
  release autorizada e somente `blindou-runtime` pode referenciá-lo.
- Antes de liberar uma candidata, a operação fechada
  `verify-ghcr-candidate-pull` baixa integralmente backend, redirector, NATS e
  `cloudflared` da release já validada no cache, confere manifestos e blobs por
  SHA-256 e remove
  os bytes temporários. Ela usa a credencial somente por memória/stdin, guarda
  apenas recibo root-only e não cria Secret, imagem no containerd ou workload.
- Alteração manual no cluster deve ser evitada e posteriormente reconciliada no
  repositório quando uma resposta emergencial for necessária.

O K3s mantém audit log somente de metadados com rotação limitada. Antes de
mudanças de configuração do cluster de nó único, o serviço é parado brevemente
para criar backup consistente e root-only do datastore SQLite e da configuração.

## Capacidade

O nó único permite uma réplica por workload e baixo tráfego. O orçamento do
Blindou é preservado; somente a capacidade residual medida pode ser oferecida
ao slot alternável. Suspender o APIWPP libera CPU e memória de execução, mas não
libera seu PVC nem o espaço do banco. Antes do SaferWPP, uma auditoria viva deve
medir Blindou, APIWPP e serviços compartilhados, reservar margem para host,
K3s, PostgreSQL, backups e picos e recalibrar a quota `saferwpp-lab`. Quotas
iniciais não substituem essa medição. HDD, quatro núcleos, Fast Ethernet e um
único domínio de falha impedem afirmar alta disponibilidade.

A auditoria viva de 2026-08-26 encontrou folga observada de CPU, memória, disco
e rede para continuar o planejamento do laboratório, mas reprovou o plano de
conexões. O PostgreSQL possui teto real 50, chegou a 48 backends em sete dias e
não usa PgBouncer compartilhado. O Blindou chegou a 43 backends; suspender o
APIWPP libera no máximo cinco observados. Os dez backends runtime e dois slots
de migration planejados para SaferWPP não preservam reserva operacional nem
margem nesse primário.

D023 resolveu a topologia ao separar o SaferWPP em um cluster de teto 24 na
porta 55432, sem mudar o primário compartilhado. Seu envelope adicional limita
CPU a um core, usa `MemoryHigh=1536Mi`, `MemoryMax=2048Mi` e exige pisos de 20
GiB para dados e 20 GiB para backup local. Essa conta cabe na folga observada
para continuar o laboratório, mas precisa ser revalidada junto com os workloads
antes da ativação.

Permanecem bloqueantes a ausência viva do cluster/stanza/exporter, a quota viva
antiga, os workloads Keycloak/Control Plane, seus contratos de dados, os
Secrets externos e os controladores do slot. Os artefatos declarativos e seus
orçamentos passam em verificação offline, mas não constituem capacidade nem
backup comprovados. Aumentar `max_connections` do primário compartilhado
isoladamente continua proibido.
