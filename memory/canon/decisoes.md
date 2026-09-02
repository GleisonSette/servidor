# Decisões da plataforma local

metadata:
  canon_id: canon-decisoes
  source_path: memory/canon/decisoes.md
  generated_from: decisões do usuário e limites observados do laboratório
  updated_at: 2026-09-02
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

O caminho administrativo canônico é `C:\github\servidor\.env`. O helper não
deriva esse arquivo da raiz do worktree: assim, um commit limpo pode ser
fotografado em worktree separado sem copiar, vincular ou relocalizar a
credencial. Arquivo ausente, simbólico, repetido ou fora dos limites continua
falhando fechado.

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

## Resolvida D029 - DRE familiar independente e sempre ativo no K3s

Em 2026-08-29, depois de preparar a operação K3s no repositório DRE, o usuário
autorizou explicitamente alterar o repositório `servidor` para implementar seu
controlador fechado. Essa decisão acrescenta o DRE ao alvo da plataforma sem
colocá-lo no slot APIWPP/SaferWPP. O estado-alvo passa a preservar Blindou e DRE
sempre ativos, com exatamente um ocupante ativo no slot secundário.

O DRE usa `dre-production`, API e worker Rust separados e um PostgreSQL 18
StatefulSet exclusivo. São exatamente três containers permanentes, com
ServiceAccounts, Secrets, PVC, banco, papéis, rede, release, backup e chave de
assinatura próprios. PostgreSQL, métricas e Services permanecem privados. A
fundação adicional `dre-restore-drill` aceita somente restauração temporária em
StorageClass `Delete`; nunca aponta para o PVC de produção.

`dre-deployctl` aceita somente release Ed25519 com quatro estágios fixos,
digests `linux/amd64`, SHA Git, SBOM SPDX, scans sem vulnerabilidade alta/crítica
e regras de alerta assinadas. A identidade Kubernetes `dre-deployctl` não
pertence a `system:masters`; admissão e sudoers restringem namespace, ações e
recursos. Segredos iniciais entram por `stdin`, valores internos são gerados
separadamente por papel e nenhum valor é impresso. Plano expira em 30 minutos e
vincula release, Secrets, capacidade e fingerprints de APIWPP/Blindou.

O preflight exige um nó Ready `x86_64`, ao menos quatro CPUs lógicas, 5 GiB de
memória disponível e 45 GiB livres no filesystem K3s. Esses pisos são gate
conservador, não prova de capacidade. A operação também adquire os locks
Blindou e slot e compara recursos protegidos antes/depois.

D029 autorizou somente a implementação offline inicial nos repositórios
`servidor` e DRE. Chave privada, publicação de imagens, R2/FCM, instalação,
Secrets, migration persistente, deploy, restore vivo, rota HTTPS, contas e
saldo inicial permaneceram operações separadas.

## Resolvida D030 - Capacidade de senha restrita ao bootstrap DRE

Em 2026-08-29, depois que a primeira execução manual do bootstrap DRE acionou
rollback e exigiria nova digitação de senha, o usuário decidiu permitir que
`KEY_SERVIDOR` fosse carregada do arquivo ignorado canônico
`C:\github\servidor\.env` exclusivamente por
`Dre.SudoBootstrap.psm1` e entregue por `stdin` ao `sudo` de um bootstrap DRE
versionado e fechado.

O helper valida host, identidade SSH, padrão do staging, hashes SHA-256, lista
exata do bundle e instalador. Antes de executar código transportado como root,
ele copia bundle e chave pública para cache root-owned, revalida o inventário e
extrai somente arquivos regulares permitidos. O segredo nunca entra em
argumento, variável de ambiente, arquivo gerado, log ou saída e é descartado da
variável local ao final.

D030 não concede `sudo` ou shell genérico e não autoriza importação de release,
criação de Secrets, migration, deploy, backup, restore, publicação de imagem,
R2/FCM, HTTPS, contas ou dados financeiros. A chave privada Ed25519 continua
fora do servidor e dos repositórios.

## Resolvida D031 - Build temporário do PostgreSQL dedicado no servidor

Em 2026-08-29, após o GitHub recusar o workflow antes de qualquer step por
bloqueio de cobrança, o usuário autorizou temporariamente o servidor físico
como executor da imagem PostgreSQL dedicada, até solicitar o retorno ao GitHub
Actions. A decisão está alinhada à D064 do repositório Blindou e substitui
somente esse trecho operacional da D015.

A derivação OCI sem daemon e o scan bloqueante rodam como `apiadmin` em
workspace descartável, sob cgroup de 1 CPU/4 GiB, `nice`/`ionice` baixos e
recusa de concorrência com Cargo/Rust. São proibidos `sudo`, Docker/BuildKit,
K3s, banco, serviço, Secret e credencial operacional. A credencial GHCR de
escrita permanece somente na estação: ela recebe o artefato, valida o recibo e
publica os blobs por streaming. O host conserva apenas sua autoridade de
leitura já aprovada. A exceção não alcança outra imagem, projeto, migration,
workload ou etapa I2 e termina quando o usuário pedir a volta ao GitHub Actions.

Enquanto D031/D064 vigorar, o verificador do bundle aceita exatamente duas
linhas de scan, sem combinação entre elas: o caminho normal com Trivy 0.67.2
por imagem imutável, sem recibo D064, ou o caminho excepcional com o binário
Trivy 0.70.0 no archive SHA-256
`8b4376d5d6befe5c24d503f10ff136d9e0c49f9127a4279fd110b727929a5aa9` e
recibo D064 completo. Versão, hash, modo, limites, autoridade ou recibo
divergentes falham fechados.

## Resolvida D032 - Token da ponte DRE coordenado antes dos Secrets

Em 2026-08-30, depois da publicação do Pages e da importação da primeira release
assinada, a verificação operacional encontrou uma fronteira impossível no
contrato inicial: `dre-secret-material.py` gerava o token da ponte dentro do
servidor e apagava o material temporário, enquanto o Cloudflare Pages precisava
receber exatamente o mesmo valor. Recuperar o token lendo um Secret Kubernetes
violaria o cofre e não seria uma interface operacional reproduzível.

O usuário autorizou corrigir, publicar e instalar o controlador. O contrato
passa a exigir `web_bridge_token` no JSON protegido recebido por `stdin`, com
alfabeto portátil e ao menos 64 caracteres. O orquestrador local gera o valor
somente em memória, grava primeiro o Secret homônimo no Pages e só então envia o
mesmo valor ao controlador. O valor não entra em argumento, arquivo versionado,
log, índice ou resposta. Senhas PostgreSQL e cifra de backup continuam geradas
separadamente no servidor.

A coordenação não transforma Cloudflare e Kubernetes em uma transação única. A
ordem torna a falha segura: erro no Pages impede `initialize-secrets`; erro no
controlador remove o lote Kubernetes criado na tentativa, e o Secret ainda
inativo do Pages pode ser sobrescrito antes de repetir. D032 não autoriza criar
credencial GHCR/R2, inicializar Secrets, configurar origem HTTPS, executar
migration ou deploy; essas operações continuam separadas.

## Resolvida D033 - Retirada imediata do runtime APIWPP preservando o banco

Em 2026-08-30, diante de consumo concorrente de CPU/RAM e de uma operação
pgBackRest presa, o usuário determinou que o APIWPP não permaneça funcionando
nem retenha artefatos de execução. A ordem explícita substitui, para o APIWPP,
a preservação reversível de runtime prevista em D022. Permanecem vigentes a
proteção do Blindou, a exclusão mútua do slot e a preservação do database
`clone_wpp`.

A operação autorizada reduz o Deployment a zero, reconcilia o slot para
ocupante `none`, desabilita os seis timers pgBackRest associados ao APIWPP e
remove imagem, cache OCI, inbox de release e PVC de spool. Deployment, Service,
ConfigMaps, Secrets, namespace, controlador e gateway podem permanecer como
estrutura declarativa de custo desprezível quando forem necessários à
coerência do slot, do host ou do Blindou; não podem iniciar workload.

O repositório físico pgBackRest existente não é apagado. Embora historicamente
nomeado APIWPP, ele contém proteção do cluster PostgreSQL compartilhado e sua
remoção também reduziria a recuperabilidade do Blindou. Paralisar novas agendas
não autoriza destruir cópias já existentes nem o PostgreSQL compartilhado.

Retomar o APIWPP exige nova decisão explícita, nova imagem/release autenticada,
recriação do PVC quando necessário, reativação consciente da proteção de dados
e reserva válida pelo `secondary-slotctl`. Nenhum trabalho paralelo pode
interpretar a presença do Deployment em zero como autorização de retomada.

## Resolvida D034 - Release DRE validada em namespace descartável antes do plano

Em 2026-08-30, a candidata DRE passou a declarar schema 2, nove migrations,
três imagens e seis estágios adicionais de validação. Aplicar diretamente os
quatro estágios permanentes manteria uma lacuna operacional: migrations,
bootstrap, E2E e recuperação após reinício seriam comprovados somente depois
de tocar o banco de produção.

O usuário autorizou alterar e publicar o repositório `servidor`, instalar o
controlador schema 2, publicar as imagens e executar apenas o ambiente
descartável `dre-validation`. A decisão é manter schema 1 importável e
reverificável somente para rollback, aceitar novas candidatas schema 2 com os
dez estágios e bloquear `plan`/`deploy` até existir recibo aprovado ligado ao
mesmo release ID, SHA-256 do archive e digests.

O controlador cria `dre-validation` por ação fechada, instala RBAC limitado ao
namespace, copia somente a credencial de pull já existente e gera senhas
exclusivamente sintéticas em `/run`. Ele executa PostgreSQL sem WAL/R2, nove
migrations, papéis, API, worker, bootstrap, E2E e substituição controlada dos
pods API, worker e PostgreSQL. Sucesso remove namespace, PVC e PV e grava
recibo root-only sem valores. Falha fecha o gate como `blocked`, preserva o
ambiente para diagnóstico e exige `cleanup-validation` explícito.

A alternativa de usar `kubectl` ou shell genérico foi recusada porque ampliaria
a autoridade do operador. Manter um namespace permanente também foi recusado:
o RBAC é recriado por manifesto root-owned e desaparece com o namespace. A
fundação conserva somente a permissão nominal e a admissão fail-closed. O
rollback instala o bundle anterior; receipts schema 2 e releases cacheadas
permanecem auditáveis. D034 não autoriza `dre-production`, migration
persistente, rota externa, contas reais, dispositivos ou saldo inicial.

## Resolvida D035 - Build e publicação das imagens DRE somente no servidor

Em 2026-08-30, o usuário determinou que nenhum workload Linux, Docker, WSL ou
container seja executado na estação Windows e autorizou construir, verificar e
publicar as três imagens da candidata DRE no servidor físico. A estação fica
restrita a Git, edição, SSH/SCP nativos e entrega protegida da credencial GHCR.

O build usa o archive exato do commit
`25dc4f8996699a5c9870294666391eb8bbab7c3e`, SHA-256
`a5303a241928ea78223bf7cddfb5425fc77d14acbc96c9c249dcca586ad70099`,
e BuildKit 0.32.2 oficial fixado pelo SHA-256
`2975d0f651ad96ba8b80b9992ae1f9a964f4408569af5b6dc36544165c3926af`.
O daemon existe somente durante a operação, roda como root por helper fechado,
usa worker OCI próprio, snapshotter `native`, rede `bridge`, paralelismo dois,
`nice`/`ionice` reduzidos e não acessa Docker nem o socket containerd do K3s.
O preflight exige quatro CPUs, 8 GiB disponíveis e 60 GiB livres, além dos
locks DRE, Blindou e slot secundário.

O resultado são três OCI archives `linux/amd64` entregues novamente a
`apiadmin`. A etapa seguinte permanece sem sudo: Syft 1.51.0 produz SBOM SPDX,
Trivy 0.72.0 bloqueia qualquer vulnerabilidade alta/crítica e regctl 0.11.5
publica `dre-app`, `dre-postgres` e `dre-validation-runner`. Todas as
ferramentas são fixadas por SHA-256. O token `write:packages` continua no
keyring da estação, atravessa SSH apenas por `stdin`, vive somente na memória e
em um HOME temporário `0700` no servidor e nunca aparece em argumento, log,
recibo ou arquivo versionado.

Falha antes do push não publica imagem. Falha parcial durante o push pode deixar
tag imutável sem recibo; repetir a mesma candidata é idempotente porque archive
e tag estão presos ao mesmo SHA Git. D035 não concede acesso ao containerd do
K3s, não instala daemon permanente e não autoriza `dre-production`, migration
persistente, Cloudflare, contas ou dados reais.

## Resolvida D036 - Executor rootless dos gates integrais DRE

Em 2026-08-31, os gates literais `make release-check` e `make e2e` continuavam
pendentes porque exigem uma interface compatível com Docker para builds,
Compose e bancos descartáveis. A estação Windows foi excluída por D035, o K3s
não pode virar executor genérico e BuildKit isolado não cobre os contratos de
Compose do repositório. O usuário autorizou alterar e publicar este repositório,
instalar as ferramentas necessárias no servidor e executar os dois gates em
ambiente integralmente sintético e descartável.

A decisão instala por bootstrap fechado Podman, uidmap, podman-compose,
slirp4netns, fuse-overlayfs e passt nas versões fixadas do Ubuntu 24.04, junto
das dependências/recomendações que o APT resolve para build, rede e `init`. A
transação proíbe remoção ou atualização de pacote preexistente, fotografa o
inventário e desfaz somente pacotes novos se falhar antes do recibo. Nenhuma
unit, timer, socket ou API Podman é habilitada ou iniciada; Docker e daemon
persistente continuam ausentes.

Execuções ocorrem como `apiadmin`, em `--root`, `--runroot`, XDG, caches e
workspace próprios sob `/tmp`. Um shim temporário traduz exclusivamente a
interface usada pelo Makefile para Podman rootless/podman-compose. Source vem de
commit DRE publicado, contas, dispositivos, saldo e credenciais são sintéticos,
e a API fica somente na loopback. Ao terminar, Compose, volumes, redes, imagens,
processos e workspace são removidos por caminho exato.

Os grupos, `subuid`, `subgid` e a inacessibilidade do kubeconfig/socket K3s são
comparados antes e depois. O executor não recebe `kubectl`, kubeconfig,
containerd, sudoers, grupo novo ou autoridade do `dre-deployctl`; consultas de
segurança continuam somente pelos controladores já instalados. O recibo
root-only não contém segredo. Remover as ferramentas depois do sucesso é uma
operação separada e deve usar o inventário registrado, sem `autoremove` cego.

D036 não autoriza migration ou deploy em `dre-production`, rota HTTPS,
Cloudflare, R2 operacional, contas, dispositivos ou dados reais.

## Resolvida D037 - Borda Cloudflare exclusiva e fechada para o DRE

Em 2026-09-01, o usuário autorizou o deploy persistente do DRE e sua rota HTTPS
no Cloudflare. Reutilizar `blindou-physical` ou qualquer conector de outro
projeto violaria o isolamento aprovado; expor NodePort, Ingress, hostPort ou
porta da LAN ampliaria a superfície do servidor sem necessidade.

A decisão é criar um Tunnel Cloudflare e um namespace `dre-edge` exclusivos.
O recurso Tunnel, o hostname e a regra pública continuam administrados no
Cloudflare autenticado. O K3s recebe somente o token pela ação fechada
`configure-edge`, via `stdin`, e o persiste no único Secret permitido,
protegido pela criptografia de Secrets já ativa. O recibo e as métricas
registram apenas estado, release e disponibilidade, nunca o token.

O namespace nasce `blocked` e possui quota para exatamente um Pod, um Secret,
zero Service/PVC/ConfigMap de aplicação, ServiceAccount sem token e negação de
rede por padrão. O `ConfigMap` sistêmico `kube-root-ca.crt`, materializado
automaticamente pelo Kubernetes e não contabilizado como autoridade da
aplicação, é a única exceção ao inventário vazio: o gate exige no máximo esse
único nome, somente `data.ca.crt` em PEM, nenhum `binaryData` e `immutable`
ausente ou falso. A quota de `ConfigMap` permanece zero e qualquer objeto
adicional falha fechado. O único Deployment usa a imagem oficial
`cloudflared` fixada por digest,
sai por TCP/7844, consulta apenas o DNS do cluster e alcança somente a API DRE
em TCP/8080. A ação exige release corrente saudável, locks dos projetos
protegidos e rollback automático que remove Deployment/Secret e restaura o
gate `blocked` em caso de falha.

O inventário vazio do edge é observado pela interface administrativa somente
leitura do controlador. A identidade mutável DRE conserva RBAC sem `list`
amplo; uma recusa `Forbidden` nessa identidade não pode ser interpretada como
lista vazia ou prova de ausência.

O hostname aprovado é `dre-api.fitdock.com.br`; ele encaminha somente para o
Service ClusterIP do DRE. `/metrics` deve ser negado na borda e
`DRE_API_ORIGIN` no Pages só é definido depois que a rota HTTPS passar nos
smokes. Rotação ou retirada do token exige nova operação fechada; editar Secret
ou workload manualmente não é procedimento operacional. Esta decisão não
autoriza FCM, saldo inicial ou dados financeiros reais.

## Resolvida D038 - Diagnóstico fechado após rollback do primeiro deploy DRE

Em 2026-09-02, o primeiro deploy persistente do DRE criou somente a plataforma
e o PostgreSQL dedicado, mas o `pgBackRest check` terminou com código 82 antes
das migrations. A compensação passou, removeu API/worker e preservou
PostgreSQL, PVC `Retain` e Secrets conforme o contrato. Não havia release
corrente nem tabela `_sqlx_migrations`.

O bootstrap normal recusa produção com PVC/workload e o controlador anterior
não expunha diagnóstico desse estado. A decisão é admitir uma exceção única e
fail-closed para instalar somente uma operação de leitura. Ela exige recibo do
primeiro deploy com `failed`, `previous_release=none` e `rollback=passed`,
inventário exato contendo apenas o PostgreSQL esperado, imagem presa ao bundle,
PVC `dre-local-retain` de 20 GiB e ausência comprovada de migrations. A fundação
não é reaplicada e um fingerprint do runtime, inclusive configurações, Secrets
e PVC, precisa permanecer idêntico antes e depois.

`diagnose-production` não aceita argumentos, não repete `pgBackRest check`, não
grava no R2 e não oferece shell ou `kubectl`. A saída redigida limita-se ao
recibo resumido, inventário, eventos, log técnico do PostgreSQL, `pgBackRest
info` e arquivos fixos de log. A operação é recusada assim que o estado deixar
de corresponder ao rollback anterior às migrations. Corrigir a causa e repetir
o deploy continuam sujeitos ao plano autenticado e às verificações vigentes.

## Resolvida D039 - Recuperação mutável e limitada do primeiro deploy DRE

Em 2026-09-02, o usuário autorizou concluir o deploy persistente, migrations,
backup/restore, borda e contas privadas. A release corrigida não podia ser
importada porque o próprio rollback anterior removeu o rótulo de projeto; após
a importação, o deploy normal também recusaria trocar implicitamente a imagem
PostgreSQL preservada. Remover o PVC, editar o cluster manualmente ou enfraquecer
os gates não preservaria a rastreabilidade exigida.

A decisão acrescenta uma recuperação única ao controlador fechado. Importação e
validação descartável podem tolerar o rótulo ausente somente quando recompõem o
estado exato D038. Depois que a nova release schema 2 possui recibo de validação
aprovado, `recover-first-deploy` restaura `project=dre`, substitui apenas o
digest do contêiner PostgreSQL e executa o `pgBackRest check` corrigido. PVC,
Secrets, configurações e projetos vizinhos são protegidos por inventário,
fingerprints e locks; `_sqlx_migrations` deve continuar ausente.

Falha tenta restaurar imagem e rótulo anteriores e registra recibo; compensação
incompleta fecha o gate como `rollback-failed`. Sucesso não cria release
corrente nem aplica migration: ele apenas devolve o ambiente ao pré-estado em
que o fluxo autenticado `plan`/`deploy` pode continuar. A interface continua sem
`kubectl`, shell, caminho ou imagem fornecida livremente pelo operador.

Como a primeira execução da recuperação devolveu apenas o código interno do
`pgBackRest`, a ação passa a capturar exclusivamente a saída de
`stanza-create`/`check`, redigir padrões de credencial e limitar o diagnóstico a
16 KiB antes do rollback. A mensagem não é persistida no recibo e não amplia os
comandos aceitos pelo controlador.

O diagnóstico revelou concorrência legítima com o `archive-async`, não falha de
R2 ou corrupção. Somente o código 50 acompanhado das duas mensagens exatas de
lock ocupado recebe até oito tentativas com backoff exponencial, jitter e espera
máxima de 30 segundos. O mesmo helper protege recuperação e deploy normal;
qualquer erro não classificado continua falhando imediatamente. Diretórios de
log e lock existem apenas no `emptyDir` do Pod, em modo `0700`.

## Resolvida D040 - Provisionamento inicial por Pod administrativo efêmero

Em 2026-09-02, a primeira criação das contas falhou atomicamente porque o CLI
foi executado no Pod da API. Esse Pod possui somente `dre_api_runtime`, que por
desenho não recebe `dre_migrator`; conceder a ele privilégio administrativo
permanente romperia o menor privilégio aprovado.

A decisão é materializar, somente dentro de `provision-accounts`, um Pod
administrativo de nome fixo, imagem presa ao digest assinado da release e
ServiceAccount sem token. Apenas esse Pod monta a URL `dre-postgres-admin`,
recebe as duas senhas por `exec -i` e termina após a transação. O filesystem é
somente leitura, recursos são limitados, a rede já permite somente PostgreSQL e
o deadline é de cinco minutos. O controlador recusa Pod preexistente, confere o
manifesto vivo, remove o Pod antes do recibo e compara Secrets e projetos
protegidos. Se a limpeza falhar, fecha o gate como `accounts-cleanup-failed`.

## Resolvida D041 - Atualização do controlador com release DRE ativa

Em 2026-09-02, a instalação do controlador D040 foi recusada antes de substituir
qualquer arquivo porque o bootstrap interpretava todo PostgreSQL existente como
resto do primeiro deploy falho. A produção já possuía release corrente saudável,
nove migrations e os três componentes Ready; exigir `release=none` era correto
para D038/D039, mas incorreto para uma atualização normal posterior ao deploy.

A decisão é separar três estados fechados no mesmo bootstrap: `predeploy`,
`failed-first-deploy` e `active-release`. O terceiro exige ponteiro corrente
root-only íntegro, release schema 2 no cache, nove migrations, gate de produção
`passed`, PVC `Bound`, API/worker/PostgreSQL Ready, validação descartável ausente
e nenhuma instância do Pod administrativo efêmero. O controlador instalado antes
da troca e a versão recém-instalada precisam aprovar `verify` para a mesma
release.

Nesse modo a fundação Kubernetes não é reaplicada. Impressões digitais de todo o
runtime de produção e do edge são comparadas antes e depois da troca dos arquivos
do controlador. O edge pode estar `blocked` e sem runtime ou `connector-only`
com exatamente um Deployment/Pod e o único Secret do Tunnel; o token nunca é
lido como valor. Qualquer mudança em workload, PVC, Secret, configuração,
ownership ou inventário falha fechado e aciona o rollback transacional dos
arquivos instalados. D041 não concede `kubectl`, shell, migration ou alteração
de release e não transforma upgrade do controlador em deploy da aplicação.

## Resolvida D042 - Upgrade fechado da imagem PostgreSQL do DRE

Em 2026-09-02, a primeira exportação lógica real revelou que o diretório
`emptyDir` já preparado pelo Kubernetes não pode receber `chmod` pelo usuário
não root da imagem. A correção fica exclusivamente no helper da imagem
PostgreSQL. O deploy normal recusa por projeto qualquer troca desse digest, e
editar Pod, StatefulSet ou arquivo dentro do container contornaria assinatura,
recibo e rollback.

A decisão é acrescentar `upgrade-postgres` à interface fechada. A ação exige
release schema 2 já importada e validada, plano ainda vigente e backup `full` ou
`diff` aprovado da release corrente, concluído depois da geração desse plano. A
candidata precisa manter exatamente a imagem Rust, a quantidade de migrations
e os estágios de migration e runtime. Os manifestos de plataforma e acesso ao
banco, depois de normalizar todas as ocorrências esperadas do digest PostgreSQL,
precisam ser byte a byte equivalentes. A contagem esperada também é validada
para impedir que uma imagem estranha seja escondida pela normalização.
Assim, a operação não serve como caminho genérico para alterar schema,
configuração ou versão principal do banco.

Durante a troca, o namespace recebe gate `postgres-upgrade` e os locks DRE,
Blindou e slot secundário permanecem ativos. Como o campo da imagem já pertence
ao gerenciador `kubectl-set`, o controlador altera somente
`statefulset/dre-postgres:postgres` para o digest extraído do manifesto assinado;
ele não reaplica toda a plataforma nem toma ownership com `--force-conflicts`.
Depois do rollout, `stanza-create`, `check`, readiness, migrations existentes,
API e worker são conferidos antes de avançar o ponteiro da release. O recibo
vincula release anterior, digests antigo/novo e SHA-256 do recibo de backup, sem
segredos. Qualquer falha primeiro restaura esse campo para o digest anterior,
reaplica a release anterior, restaura alertas e exige que o runtime antigo volte
a passar na verificação; falha nessa compensação fecha o gate como
`rollback-failed`.

## Resolvida D043 - UID canônico no restore PostgreSQL DRE

Em 2026-09-02, o primeiro restore drill da release ativa chegou ao rollout, mas
o StatefulSet não ficou Ready no timeout de 1.200 segundos. O renderer fixava
`runAsUser`, `runAsGroup` e `fsGroup` em `999`; a imagem PostgreSQL Alpine
distribuída e o StatefulSet permanente usam o usuário `postgres` de UID/GID
`70`. Executar a imagem como identidade inexistente impede que pgBackRest e
PostgreSQL resolvam corretamente o usuário e a propriedade dos arquivos.

A decisão é usar `70` nos três campos do Pod descartável, mantendo
`runAsNonRoot`, seccomp, capabilities removidas, filesystem raiz somente leitura
e PVC separado. O teste do renderer passa a afirmar explicitamente a identidade
para impedir regressão. A instalação continua no modo `active-release`, com
verificação antes/depois e fingerprints imutáveis; ela não executa restore nem
altera workloads por efeito colateral. O bootstrap aceita o PVC preservado
somente quando recibo, operação, labels, StorageClass, claim e PV recompõem o
estado falho exato e exige fingerprint idêntico antes/depois.

A ação `cleanup-restore RELEASE_ID FAILED_OPERATION_ID OPERATION_ID` exige um
novo ID de operação e remove apenas o PVC fixo do restore cujo recibo está
`failed`, depois de confirmar ausência de workload,
vínculo do PV e release corrente. Ela aguarda o PV `Delete` desaparecer,
reverifica produção e projetos protegidos e grava recibo próprio; nome de
recurso, caminho ou alvo livre continuam inexistentes na interface.

## Resolvida D044 - Diagnóstico durável e falha rápida no restore DRE

Em 2026-09-02, o segundo restore descartável também atingiu o timeout de 1.200
segundos. O tratador removia StatefulSet e Pod antes de registrar estado ou log,
por isso o recibo comprovava a falha sem explicar se a causa era agendamento,
init container, imagem ou PostgreSQL. Repetir ciclos de vinte minutos sem essa
evidência atrasaria a recuperação e esconderia a condição operacional real.

A decisão é observar o StatefulSet e o Pod a cada dois segundos, encerrar cedo
em erro definitivo de agendamento, pull, configuração ou processo e manter o
timeout total de 1.200 segundos para operações apenas lentas. Antes de remover
os workloads, o tratador grava no recibo root-only a fase, condições e estados
estruturados do Pod e os últimos logs de `restore` e `postgres`, limitados a 16
KiB por container e processados pelo sanitizador de credenciais. A mesma
evidência sanitizada aparece na saída da operação para diagnóstico imediato.
O PVC continua preservado e só pode ser removido por `cleanup-restore` com IDs
distintos; a mudança não amplia a interface para shell ou `kubectl` genéricos.
