# Decisões da plataforma local

metadata:
  canon_id: canon-decisoes
  source_path: memory/canon/decisoes.md
  generated_from: decisões do usuário e limites observados do laboratório
  updated_at: 2026-08-29
  status: canonical

## Resolvida D001 - Projetos admitidos pela plataforma

O servidor preserva o `apiwpp` existente e reserva toda a capacidade restante
ao Blindou. Os namespaces vazios Pixel/CIA e SaferWPP podem permanecer como
histórico declarativo, mas não recebem workload. Namespace no mesmo nó não
protege um projeto se o host inteiro for comprometido.

A exclusividade de capacidade descrita nesta decisão foi substituída por D022
em 2026-08-26. A preservação do APIWPP e os limites de isolamento permanecem.

## Resolvida D002 - Identidade administrativa

Não haverá chave SSH por projeto. A chave SSH existente identifica o
administrador. Cada projeto terá assinatura de release, controlador de deploy,
ServiceAccounts, Secrets, banco e permissões próprios.

## Resolvida D003 - Ordem de implantação

Memória/base declarativa e estabilização foram concluídas. A preparação do
SaferWPP foi interrompida por decisão posterior do usuário para priorizar o
Blindou. Nenhum projeto pode usar essa prioridade para contornar seu próprio
controlador, isolamento ou gate de segurança.

A interrupção do SaferWPP foi encerrada por D022 em 2026-08-26. A retomada é
progressiva e continua bloqueada até existirem capacidade medida e controles
de suspensão, retomada e exclusão mútua.

## Resolvida D004 - Classificação por projeto

`apiwpp` conserva a classificação atual. Pixel/CIA e SaferWPP ficam sem novos
workloads. O Blindou poderá ser o primeiro uso operacional limitado do host,
sem alegação de alta disponibilidade, somente depois que os gates temporários
de D013 passarem.

A classificação do SaferWPP como permanentemente sem workloads neste host foi
substituída por D022. Pixel/CIA continua sem novos workloads.

## Resolvida D005 - Alertas e continuidade da primeira operação

O usuário escolheu `gleisonsette@gmail.com` como receptor externo, independente
do servidor e do WhatsApp monitorado. O canal aprovado usa Alertmanager restrito
ao loopback e Resend por SMTP autenticado com TLS. A credencial fica fora do Git
e a liberação do gate exige alerta sintético e confirmação humana de entrega.
Não inventar webhook, WhatsApp ou destino alternativo.

Para a primeira operação no servidor físico, o usuário aceitou RPO de 15
minutos, RTO de 4 horas e retenção offsite de 30 dias. Antes de migrations, o
controlador cria o dump lógico criptografado, a estação administrativa baixa e
confere tamanho e SHA-256 e o host registra um recibo sem segredo. Esses valores
são temporários e devem ser revistos quando a operação migrar ou crescer.

## Resolvida parcialmente D006 - Borda pública

Para o Blindou, Cloudflare Pages e Cloudflare Tunnel foram escolhidos. Durante
a exceção D013, o conector fica no namespace `blindou-edge` e alcança apenas
Services ClusterIP. Nenhum projeto abre portas na ONT residencial.

Em 2026-08-20 o usuário autorizou a criação do Zero Trust, do Tunnel
`blindou-physical` e a vinculação do servidor. O conector foi ativado e
verificado sob gate `connector-only`: exatamente um Pod, um Secret, nenhuma
porta pública/Service/PVC e sem liberar `blindou-production`. As rotas técnicas
do Tunnel apontam para Services ClusterIP ainda ausentes e, portanto,
permanecem fechadas até as origens da aplicação existirem.

## Resolvida D007 - Baseline privado dos novos namespaces

Os espaços Pixel e SaferWPP iniciam vazios, com Pod Security `restricted`,
default deny, somente DNS liberado, cotas conservadoras e conta padrão sem
token. Uma política de admissão impede Service público. As cotas serão
recalibradas com medições, sem remover os limites de segurança.

## Resolvida D008 - Backup do K3s antes de mudanças

O K3s usa SQLite em nó único. A cópia consistente inicial foi feita com parada
breve e checksum. Ela fica root-only no mesmo HDD e serve para rollback lógico;
uma cópia externa do cluster continua sendo melhoria futura, distinta do R2 do
PostgreSQL.

## Resolvida D009 - Restart de serviços dependentes

PostgreSQL Exporter e gateway privado usam `PartOf` para acompanhar restart do
PostgreSQL e K3s. A manutenção também os inicia explicitamente e valida os
listeners. Isso evita que `Requires` derrube o dependente sem trazê-lo de volta.

## Resolvida D010 - Publicação e licença

O repositório de infraestrutura compartilhada é público em
`https://github.com/GleisonSette/servidor` e usa licença MIT, copyright 2026
Gleison Sette. Os repositórios `apiwpp`, Pixel/CIA, SaferWPP e Blindou
permanecem fora desse commit e conservam seus próprios históricos e licenças.

## Resolvida D011 - Operação segregada por repositório

Cada Codex de aplicação deve ler o guia do servidor do próprio repositório antes
de acessar o host. O apiwpp opera somente pelos controladores restritos já
instalados. Pixel, SaferWPP e Blindou permanecem sem permissão de alteração até
receberem controladores root-owned próprios, com releases assinadas e escopo
fechado nos respectivos namespaces e dados. A senha administrativa, `sudo`
genérico, kubeconfig root e o controlador de outro projeto não são atalhos
válidos.

## Resolvida D012 - Contenção externa obrigatória do Blindou

O gateway observado é uma ONT Huawei HG8145V5 com perfil Oi `OI2`. Ela não é a
fronteira de segurança do Blindou e sua função residencial “DMZ host” é
proibida. Um firewall dedicado, fisicamente externo ao servidor, deve separar
HOME, EDGE e BLINDOU-DMZ, negar DMZ para HOME/gerência da ONT/Internet por
padrão e registrar as exceções.

O `cloudflared` fica na EDGE externa. O servidor não pode atuar como seu próprio
firewall nem manter um conector que permita criar saída arbitrária por túnel.
Publicação permanece bloqueada até testes negativos, allowlist de providers,
alerta externo e kill switch independente do host passarem. Esse desenho reduz
movimento lateral e saída, mas não promete impedir toda exploração ou
exfiltração após comprometimento total: o produto possui integrações externas
necessárias e todos os projetos/dados do mesmo host compartilham o risco de root.

Esta decisão foi substituída temporariamente por D013 em 2026-08-19. Ela
permanece como referência da proteção que seria obtida com equipamento externo.

## Resolvida D013 - Contenção local temporária e host reservado ao Blindou

O usuário decidiu não comprar firewall neste momento e autorizou UFW, sysctl,
Pod Security, NetworkPolicy e Cloudflare Tunnel no próprio servidor até a
migração para a Vultr. O conector roda somente em `blindou-edge`, com Secret
separado; ONT continua sem DMZ host, UPnP ou port forward.

A interface `enp2s0` nega destinos privados para processos do host e tráfego
encaminhado dos Pods, nega entrada da LAN exceto administração 22/6443 de
`192.168.100.57`, preserva DNS/DHCP e tem IPv6 desabilitado para fechar o `/64`
compartilhado. Saída pública permanece disponível. Esses controles reduzem
comprometimento de aplicação/container, mas **não contêm root no host**. Vultr
encerra a exceção.

O serviço `apiwpp` existente é preservado; toda a capacidade restante fica
reservada ao Blindou. Pixel/CIA e SaferWPP não recebem workloads. O Blindou
continua usando UAZAPI e não reativa seu código `api-wpp`.

Em 2026-08-26, D022 substituiu somente a reserva exclusiva de toda capacidade
residual e a proibição permanente de workloads SaferWPP. A contenção local, a
preservação do Blindou e a proibição de reativar o `api-wpp` no Blindou
continuam vigentes.

## Resolvida D014 - Fundação isolada do Blindou no host compartilhado

O Blindou usa o PostgreSQL 18 já operado no host, sem criar um segundo processo,
mas recebe database vazio, quatro logins, grupos, regras HBA e CA cliente
exclusivos. As conexões dos Pods exigem certificado e SCRAM; nenhum login possui
superuser, criação de database/role ou replicação.

O backup físico pgBackRest continua protegendo o cluster inteiro. O Blindou
também produz dump lógico separado, valida o catálogo antes de criptografar e
exporta somente o envelope CMS AES-256-GCM. A chave privada de recuperação e a
chave de assinatura de release permanecem fora do servidor. O primeiro deploy
exige uma cópia na estação administrativa com retenção de 30 dias e recibo
coerente com o backup mais recente. O objetivo operacional temporário é RPO de
15 minutos e RTO de 4 horas, conforme D005.

## Resolvida D015 - Build efêmero e servidor somente leitura no GHCR

Em 2026-08-20 o usuário autorizou que compilação, testes e publicação das
imagens Blindou usem runner efêmero hospedado pelo GitHub. O workflow é manual,
restrito a `main`, SHA completo e confirmação fechada; testes usam PostgreSQL
descartável e precedem qualquer publicação.

O job publicador usa `GITHUB_TOKEN` temporário com `packages: write`. O servidor
físico nunca recebe essa autoridade: conserva somente PAT classic com exatamente
`read:packages`, root-only, e materializa o pull secret apenas durante release
autorizada. Build, publicação de candidato e deploy são efeitos separados.
`push`, disparo do workflow e promoção dos digests continuam exigindo
autorizações próprias.

## Resolvida D016 - Cloudflare Pages permanece automático no primeiro push

Em 2026-08-21 o usuário decidiu manter ativa a integração automática da branch
`main` com o Cloudflare Pages. O primeiro `push` autorizado pode publicar o
painel antes que a API compatível esteja Ready; a indisponibilidade temporária
dos fluxos integrados foi aceita.

O build e o deployment do painel devem ser acompanhados, mas sucesso do Pages
não libera o gate do servidor, migrations ou deploy. A release só é
considerada operacional depois que API e frontend compatíveis passam na
validação integrada.

## Resolvida D017 - Exceção pontual para o bootstrap de 2026-08-21

Depois de o protocolo de conflito expor a regra que proíbe o Codex de ler senha
administrativa ou usar `sudo` genérico, o usuário autorizou explicitamente uma
exceção única: ler `KEY_SERVIDOR` do arquivo temporário local somente para
executar os dois scripts versionados de bootstrap do `blindou-hostctl` e do
`blindou-deployctl`.

A senha foi enviada apenas por `stdin`, não entrou em argumento, log, resposta,
commit ou memória. A exceção foi consumida com a instalação bem-sucedida e não
altera D011 nem o runbook normal: operações futuras voltam a usar somente os
controladores root-owned ou bootstrap humano. O arquivo temporário deve ser
apagado pelo operador após esta entrega.

Esta decisão permanece como histórico da exceção consumida e foi substituída
para operações futuras por D018 em 2026-08-22.

## Resolvida D018 - Senha local somente para bootstraps fechados do Blindou

Em 2026-08-22, depois da apresentação explícita do conflito com D011/D017, o
usuário autorizou permanentemente os orquestradores versionados da plataforma a
carregar `KEY_SERVIDOR` do `.env` local ignorado. A finalidade é exclusivamente
autenticar os bootstraps previamente fechados do `blindou-hostctl` e do
`blindou-deployctl` no servidor físico aprovado.

Somente `operations/Blindou.SudoBootstrap.psm1` pode ler a chave. O arquivo deve
ser regular, pequeno e conter exatamente uma ocorrência; o valor permanece em
memória somente durante o processo, segue por `stdin` para `sudo -S` e nunca
entra em argumento, variável de ambiente, arquivo derivado, log, resposta,
Git, memória RAG ou índice. O helper fixa host, staging e os dois nomes de
bootstrap aceitos. Ele não recebe comando arbitrário e não automatiza rollback
destrutivo.

D011 continua proibindo `sudo` genérico e shell administrativo automatizado.
O `.env` é uma credencial temporária da estação, não um cofre permanente. O
prazo original de remoção ao fim do trabalho foi substituído somente quanto ao
prazo por D025.

## Resolvida D019 - Revisão da interface antes dos provedores externos

Em 2026-08-22 o usuário determinou que o primeiro acesso ao Blindou deve
acontecer antes da configuração de UAZAPI, Resend e Pagar.me. A primeira
release pode executar migrations, publicar o núcleo da API e criar
`gleisonsette@gmail.com` como `super_admin`, mas deve manter os três provedores
explicitamente desabilitados e sem suas credenciais no host ou no Kubernetes.

Durante essa revisão inicial, `AUTH_REQUIRE_2FA=false`,
`INITIAL_UI_REVIEW_MODE=true`, `UAZAPI_ENABLED=false` e
`EMAIL_PROVIDER=disabled`. Os workers de notificação de autenticação por e-mail
e WhatsApp não são implantados. O controlador aceita adiar o alerta externo por
Resend somente nesse modo fechado; backup lógico, cópia offsite, release
assinada, prova integral do GHCR, contenção e demais gates continuam
obrigatórios.

Depois que o usuário validar a interface, a ativação de cada provedor será uma
mudança separada e autorizada, com credencial por entrada protegida, validação
real e atualização coerente da release. D005 continua definindo o canal futuro
de alertas, mas sua ativação deixou de preceder o primeiro login.

## Resolvida D020 - Ativação externa Pagar.me-first após aprovação da UI

Em 2026-08-24 o usuário aprovou a UI e determinou a nova ordem externa:
Pagar.me, domínio personalizado, marketplaces e, por último, UAZAPI/Resend.
Para os sete planos live, decidiu cobrança mensal `prepaid` e descritor
`BLINDOU`, preservando preços e limites do catálogo versionado no Blindou.

A credencial Pagar.me entra somente por prompt protegido. O controlador valida
a chave na API live e guarda secret key e segredo aleatório do webhook no cofre
dedicado `/etc/blindou/pagarme`, `root:root 0600`, sem alterar ConfigMap, Secret
Kubernetes ou workload. UAZAPI e Resend continuam ausentes nessa etapa.

A ativação do runtime é uma segunda operação. Ela exige uma release assinada
corrente cuja API e 16 workers declarem
`blindou.io/pagarme-first-compatible=true`, aplicação e EDGE em `passed` e a
credencial live novamente validada. A transição publica somente o par Pagar.me,
mantém UAZAPI/Resend desligados, reinicia consumidores e restaura a configuração
anterior se a prontidão falhar. Preparar o fluxo no repositório não autoriza
instalar o controlador no host, aplicar release, migration ou ativar cobrança.

Até a última etapa dessa ordem externa, atualizações da aplicação reconhecem o
adiamento de UAZAPI/Resend somente quando o recibo root-only de ativação
Pagar.me estiver íntegro e a configuração protegida mantiver
`PAGARME_ENABLED=true`. Isso não substitui o canal futuro definido em D005,
não altera o Pagar.me e não aceita ausência genérica de alertas. Receptor já
confirmado continua válido; sem uma das duas provas, o gate falha fechado.

## Resolvida D021 - Prefixos atuais e criação fechada dos planos Pagar.me

Em 2026-08-24, o painel real e a documentação oficial da API V5 mostraram que
produção usa `sk_*` e `pk_*`, enquanto sandbox usa `sk_test_*` e `pk_test_*`.
O usuário autorizou substituir a suposição anterior `*_live_*` nos gates do
Blindou e da plataforma. Produção recusa explicitamente os prefixos de teste e
a secret key ainda precisa passar por leitura autenticada na API fixa antes de
qualquer efeito.

Depois do provisionamento inicial, a secret key não volta à estação. Os sete
planos são criados pelo controlador root-only usando a chave já guardada,
catálogo imutável equivalente à migration `0005`, confirmação explícita,
metadata por código, identidade idempotente e reconciliação de resposta ambígua
sem retry cego. Um plano canônico divergente pode ser corrigido por `PUT` e
fetch-back antes de qualquer nova criação. O recibo local contém somente IDs
`plan_*`; criar planos não publica segredo no Kubernetes, não aplica migration
e não ativa o runtime.

## Resolvida D022 - Slot alternável APIWPP/SaferWPP com Blindou preservado

Em 2026-08-26, o usuário decidiu manter o Blindou sempre ativo e usar a
capacidade residual do servidor em exclusão mútua entre APIWPP e SaferWPP. O
estado permitido será exatamente um destes:

```text
Blindou ativo + APIWPP ativo + SaferWPP suspenso
Blindou ativo + APIWPP suspenso + SaferWPP ativo
```

O Blindou não participa da alternância. Seus repositórios, controladores,
namespaces, workloads, release, banco, mensageria, dados, Secrets, quotas,
Cloudflare, Pagar.me, R2 e demais integrações não podem ser modificados pela
ativação ou suspensão do slot secundário. As verificações anteriores e
posteriores à transição devem provar que o estado Blindou permaneceu igual e
saudável.

Suspender o APIWPP significa reduzir somente os workloads da aplicação a zero
réplicas por uma operação própria, assinada, auditada e reversível. Devem ser
preservados namespace, Deployment e demais objetos declarativos, Service, PVC,
banco `clone_wpp`, papéis, migrations, ConfigMaps, Secrets, imagens, releases e
backups. O gateway privado do APIWPP permanece ativo porque integra os gates
operacionais do Blindou. PostgreSQL, K3s, pgBackRest e monitoramento
compartilhados também permanecem ativos. Suspender não libera o PVC nem o espaço
do banco; libera apenas consumo de execução da aplicação.

A exclusão mútua deve ser aplicada pelos dois controladores. O futuro
`saferwpp-deployctl` recusa qualquer ativação enquanto o APIWPP não estiver no
estado suspenso verificado. O `apiwpp-deployctl` deve ganhar operações fechadas
de suspensão, verificação suspensa e retomada, recusar release durante a
suspensão e recusar retomada enquanto houver workload SaferWPP ativo. Transição
ambígua falha fechada, mantém recibo auditável e exige reconciliação antes de
nova tentativa.

Em 2026-08-26, a aplicação declarativa desta decisão foi fechada no repositório
da plataforma. `secondary-slotctl` é o único escritor do atestado root-only,
compartilha o lock global com os controladores de aplicação e controla labels
de admissão nos namespaces membros. A admissão nega workloads em estado
inativo, ausente ou desconhecido. A reconciliação explícita só escolhe um
ocupante quando o runtime observado é inequívoco; split-brain ou rollout
parcial continua bloqueado e alerta. O outbox JSONL preserva falha e resolução
para integração futura com a ferramenta administrativa. Esses artefatos ainda
não foram instalados, e a decisão continua sem autorizar uma transição viva.

Antes de criar banco, dependência ou workload SaferWPP, é obrigatório medir o
consumo vivo do Blindou, APIWPP e serviços compartilhados, definir margem para
host, K3s, PostgreSQL, backup e picos, e recalibrar a quota `saferwpp-lab`. A
decisão não autoriza suspender o APIWPP, instalar controlador, alterar o
servidor, aplicar migration ou implantar o SaferWPP; essas operações continuam
dependendo de implementação verificada e autorização específica.

## Resolvida D023 - PostgreSQL exclusivo para o slot SaferWPP

A auditoria viva de 2026-08-26 verificou `max_connections=50`, três conexões
reservadas, 41 backends no retrato, pico de 47 em 24 horas e 48 em sete dias.
O Blindou usava 35 e chegou a 43; APIWPP usava quatro e chegou a cinco. O
PgBouncer do host estava inativo. O contrato SaferWPP então presumia teto físico
60, reserva 18 e até dez backends runtime mais dois de migration.

Mesmo suspendendo o APIWPP, o primário compartilhado não comporta esse orçamento
com reserva operacional e margem durante pico Blindou. Aumentar somente
`max_connections` é incompatível com a política de capacidade e não está
autorizado.

A regra vigente de preservar integralmente o Blindou impede reduzir seus pools,
alterar seus papéis, inserir PgBouncer no caminho ou aplicar um connection limit.
Em 2026-08-26, o usuário escolheu PostgreSQL/PgBouncer exclusivos do SaferWPP no
mesmo servidor físico para o laboratório.

A plataforma deverá criar um segundo cluster/processo PostgreSQL 18
`saferwpp-lab`, separado do cluster compartilhado atual, na porta 55432, com
banco `saferwpp_lab`, papéis, certificado, diretórios, limites, backup e exporter
próprios. O PgBouncer dedicado fica no namespace `saferwpp-lab` e aponta somente
para esse endpoint. Blindou e APIWPP não são alterados e não acessam esse
cluster.

O ID lógico e a stanza permanecem `saferwpp-lab`; o nome operacional do cluster
em `postgresql-common`/systemd é `saferwpp_lab`, sem hífen.

O teto será 24 conexões físicas: três reservadas a superuser, duas a papéis
reservados e 19 ordinárias. As ordinárias são divididas entre PgBouncer runtime
10, migrations 2, monitoramento 1, backup 1 e margem 5. O processo usa unidade e
slice exclusivas, CPU máxima de um core, `MemoryHigh=1536Mi`,
`MemoryMax=2048Mi`, no mínimo 20 GiB para dados e 20 GiB para o repositório
pgBackRest local. Backup usa stanza `saferwpp-lab`, repositórios local/R2, WAL
contínuo e restore isolado.

Essa separação é lógica e operacional; HDD, CPU, memória e domínio de falha
físico continuam compartilhados. A decisão resolve a topologia, mas não cria o
cluster, não suspende APIWPP e não autoriza deploy. Até a implementação
declarativa, os preflights e os controladores passarem, APIWPP permanece ativo e
SaferWPP sem workloads.

## Resolvida D024 - Papel PostgreSQL dedicado para o redirector Blindou

Em 2026-08-26, o primeiro teste de um link protegido Amazon no hostname próprio
chegou ao redirector depois da correção da rota catch-all do Tunnel, mas
respondeu `not found`. A inspeção confirmou que `blindou_redirect_login`
pertencia a `blindou_app`, enquanto o processo tentava ligar um bypass aceito
pelas policies somente para `blindou_runtime`. Como as tabelas usam `FORCE ROW
LEVEL SECURITY`, o link válido permanecia invisível.

O usuário autorizou a correção coordenada nos repositórios Blindou e servidor.
Foi rejeitado adicionar o login a `blindou_runtime`, pois isso entregaria acesso
amplo desnecessário. A plataforma passa a declarar o grupo
`blindou_redirector`, `NOLOGIN`, `NOBYPASSRLS` e sem privilégios administrativos.
O número de logins permanece quatro. Grants por tabela, operação e coluna são
autoridade da migration Blindou `0012`; usuários, sessões, assinaturas, billing,
WhatsApp e equipe não ficam acessíveis.

O controlador usa expansão/contração: prepara o grupo dedicado antes do
migrator, mantém temporariamente `blindou_app` para compatibilidade, aplica
`0012` e somente depois de seu registro revoga o grupo legado. Em falha anterior
à migration, a release atual continua compatível. Depois de `0012`, a imagem
anterior pode usar as policies dedicadas sem receber novamente o papel amplo.

Na primeira tentativa autorizada de rollout, a candidata foi validada e o
backup offsite foi confirmado, mas `activate-release-gates` recusou o estado
vivo porque exigia `blindou-production=secrets-only` também em atualizações. A
regra corrigida distingue os únicos pares seguros: `secrets-only` com
`connector-only` e ausência de release para a primeira instalação; `passed`
com `passed` e ponteiro root-only válido para atualização. Estados mistos
continuam recusados, e o controlador não rebaixa um namespace ativo para
contornar o gate.

Em 2026-08-27, as autorizações operacionais foram concedidas separadamente. Os
controladores corrigidos foram instalados, o backup offsite foi confirmado, a
migration `0012` foi registrada e a release
`d5766d87a0cf5ba1d5827fa35e8e6a0cac801185` foi implantada. O estado final
comprovou o login dedicado, 12 migrations, aplicação e EDGE em `passed`, link
Amazon funcional e códigos desconhecidos em HTTP 404. Pagar.me permaneceu ativo
sem alteração de chave, planos, webhook ou cobrança; UAZAPI/Resend continuam
adiados.

## Resolvida D025 - `.env` administrativo retido até o primeiro cliente

Em 2026-08-27, o usuário decidiu manter o arquivo local ignorado `.env` até a
entrada do primeiro cliente. Esta decisão substitui somente o prazo de remoção
de D018; não transforma o arquivo em cofre permanente nem amplia a autoridade
de leitura.

Somente `operations/Blindou.SudoBootstrap.psm1` pode carregar `KEY_SERVIDOR`,
em memória, e entregá-la por `stdin` aos bootstraps fechados do
`blindou-hostctl` e do `blindou-deployctl` no host aprovado. Leitura manual,
log, resposta, argumento, variável de ambiente, Git, RAG, comando livre, outro
host ou outro projeto continuam proibidos. Na entrada do primeiro cliente, ou
antes diante de suspeita de exposição, o arquivo deve ser removido e a
credencial rotacionada.

Em 2026-08-29, o usuário ampliou essa permissão somente para a instalação do
`blindou-datactl`. `operations/Blindou.SudoBootstrap.psm1` aceita o conjunto
`DataController` apenas no host aprovado, sob
`/home/apiadmin/blindou-data-bootstrap/<sha40>`, e executa exclusivamente
`bootstrap-blindou-datactl.sh`. A ampliação não alcança `foundation`, Secret,
PVC, Pod, backup, restore, migration, DSN, cutover, shell ou `sudo` genérico;
depois do bootstrap, o sudoers próprio é a única interface operacional.

## Resolvida D026 - Ativação fechada da Shopee após release compatível

Em 2026-08-27, o usuário autorizou prosseguir com Marketplaces depois do link
Amazon validado. A primeira ativação adicional é a Shopee Open API. O deploy da
aplicação e a ativação do provider são operações separadas: a release entra com
Shopee desligada e deve marcar backend e exatamente 16 workers como
`blindou.io/marketplaces-compatible=true`.

O controlador aceita ativar somente o SHA corrente, com aplicação e EDGE em
`passed` e recibo Pagar.me íntegro. Ele gera uma chave aleatória de 32 bytes em
Base64 no cofre root-only, materializa somente a configuração e o Secret
necessários, reinicia backend/workers, aguarda as probes e grava recibo seguro.
Journal durável permite recuperar interrupção; falha restaura configuração,
Secret e workloads anteriores e remove a chave recém-gerada.

AppID e App Secret não entram na plataforma administrativa. Eles pertencem ao
tenant e são informados pelo usuário diretamente no painel Blindou, junto de um
produto ativo usado para validar a geração oficial antes da persistência
cifrada. Pagar.me permanece ativo; Mercado Livre, UAZAPI, Resend e 2FA não são
ativados por D026. Não há migration.

## Resolvida D027 - Credencial administrativa limitada ao bootstrap do slot

Em 2026-08-27, o usuário autorizou explicitamente usar `KEY_SERVIDOR` do `.env`
local ignorado, sem abrir seu conteúdo, para instalar o pré-requisito
`secondary-slotctl`. Esta decisão amplia D025 somente para essa materialização
e não converte a credencial em uma interface administrativa genérica.

O único caminho adicional permitido é
`operations/SecondarySlot.SudoBootstrap.psm1`, chamado por
`operations/Invoke-SecondarySlotBootstrap.ps1`. O orquestrador fixa o servidor,
a identidade SSH, os arquivos do commit, o staging e as verificações de APIWPP
e Blindou; calcula e compara o SHA-256 local e remoto. A etapa privilegiada
copia primeiro o arquivo autenticado para um cache root-owned, repete o hash,
executa o verificador offline e somente então chama
`bootstrap-secondary-slotctl.sh`.

A chave permanece apenas em memória e entra por `stdin` do `sudo` fechado. Ela
não pode aparecer em argumento, variável de ambiente, arquivo gerado, log,
índice ou resposta. A autorização não alcança a inicialização do estado por
senha, shell livre, fundação PostgreSQL, controladores SaferWPP, suspensão do
APIWPP, deploy, rollback destrutivo ou qualquer recurso Blindou. Depois da
instalação, inicialização e operação usam somente o sudoers restrito do próprio
`secondary-slotctl`.

## Resolvida D028 - PostgreSQL Blindou será exclusivo em namespace de dados

Em 2026-08-29, o usuário substituiu o destino da D014 que permitia ao Blindou
compartilhar o processo PostgreSQL 18 nativo com o APIWPP. Até um cutover
aprovado, o database `blindou` no processo nativo continua sendo a única
autoridade.

O destino é um único StatefulSet PostgreSQL 18 exclusivo do Blindou no
namespace K3s `blindou-data`, com Service ClusterIP, dois PVCs iniciais de 40
GiB, roles/logins, certificados, Secrets, NetworkPolicies, orçamento e backup
próprios. Não há `hostNetwork`, `hostPort`, `NodePort`, `LoadBalancer` ou rota
pública. Depois do cutover, nenhum login, database, HBA ou rota Blindou
permanece no processo nativo.

O teto inicial é 24 conexões: 16 runtime, uma migration, uma backup, duas para
Debezium futuro, três reservadas a superuser/operação e uma margem ordinária.
O servidor prepara `wal_level=logical`, duas senders e dois slots, mas não cria
publication ou slot antes da fase correspondente do Blindou.

O namespace nasce em pacote separado, `blocked`, com Pod Security `restricted`,
quota zero, ServiceAccount default sem token e default deny. Ele não integra o
`blindou-deployctl`. O `blindou-datactl` é uma autoridade separada, com bundle
assinado, scan/SBOM/proveniência, materialização fechada de Secrets, backup e
restore-base. Isso impede que um deploy comum altere ou reverta a autoridade de
dados.

Container no mesmo host é isolamento lógico e de recursos, não isolamento de
kernel, disco, domínio de falha ou comprometimento `root`. A migração Vultr
continua sendo a fronteira física definitiva. Antes do cutover, backup offsite,
restore em destino novo, pausa dos escritores e comparação de
migrations/RLS/grants/contagens/checksums são obrigatórios. Depois da primeira
escrita no destino, voltar ao banco nativo e criar dual-write é proibido.

I1 usa imagem privada derivada minimamente da mesma base PostgreSQL 18.6
imutável, sem `gosu` ou snakeoil e como UID/GID 999. Fundação e StatefulSet são
separados, backups chegam cifrados ao staging e restore-base usa PVC novo. A
prova inicialmente prevista em `foundation` criaria PVCs, Services, Secret de
pull e Job; ao explicitar esse conflito, o usuário aprovou uma prova anterior e
direta. `pull-proof` usa o PAT GHCR root-only já existente, baixa e valida todos
os blobs do digest assinado, remove o staging e preserva somente recibo. O gate
fica `blocked` e zero objeto operacional Kubernetes é criado.

Em 2026-08-29, o usuário aprovou o recibo I1, o risco residual do mesmo host,
os commits/pushes, a publicação da imagem e bundle, a instalação restrita do
controlador e essa prova direta. Secret Kubernetes, PVC, Job, Pod,
`foundation`, backup/restore operacional, migration, DSN, workload PostgreSQL,
I2 e cutover continuam sem autorização.
