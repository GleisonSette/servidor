# Plano de implementação da plataforma

metadata:
  canon_id: canon-plano-implementacao
  source_path: memory/canon/plano-implementacao.md
  generated_from: plano aprovado pelo usuário em 2026-08-15
  updated_at: 2026-08-31
  status: canonical

## Regra de continuidade

Ao perguntar "qual é o próximo passo", consultar primeiro este documento e o
histórico. Uma fase só muda para concluída depois de todos os critérios de
aceite aplicáveis estarem comprovados. Decisão pendente não é concluída por
suposição.

## Fase 0 - Memória e controle de mudança

Status: concluída em 2026-08-15.

Objetivos:

- criar a memória RAG local, índice BM25 e política de composição;
- registrar estado, decisões, plano e histórico;
- criar o repositório de infraestrutura sem segredos;
- preservar alterações existentes nos repositórios relacionados;
- estabelecer revisão, verificação e commit por repositório.

Aceite:

- busca retorna o documento correto para "qual é o próximo passo";
- índice pode ser reconstruído e verificado;
- `AGENTS.md` obriga o uso da memória;
- nenhum segredo ou kubeconfig foi versionado.

## Fase 1 - Base declarativa compartilhada

Status: concluída e verificada em 2026-08-15.

Objetivos:

- declarar os espaços `cia-pixel-lab` e `saferwpp-lab`;
- aplicar Pod Security, default deny, DNS, quotas e limites;
- manter `apiwpp` intacto até ajustar seus limites no próprio repositório;
- documentar acesso, backup, rollback e validação;
- preparar auditoria do Kubernetes e controles comuns.

Aceite:

- namespaces vazios existem com labels e controles esperados;
- nenhum serviço novo fica acessível pela LAN ou internet;
- manifests passam em dry-run e validação no servidor;
- configuração aplicada está representada neste repositório.

## Fase 2 - Estabilização do host e do apiwpp

Status: concluída e verificada em 2026-08-15, com D005 pendente por escolha do
usuário e sem bloquear a próxima fase.

Objetivos:

- validar backup PostgreSQL local/R2 e criar backup consistente do K3s;
- aplicar atualizações de segurança e manutenção em janela controlada;
- preservar e validar UFW, SSH, WireGuard, PostgreSQL e observabilidade;
- resolver os pods antigos `ContainerStatusUnknown`;
- corrigir a verificação do `apiwpp` para selecionar a réplica ativa;
- habilitar audit log do Kubernetes e revisar o hardening;
- preparar Alertmanager; o receptor externo depende de decisão/credencial do
  usuário e não será inventado.

Aceite:

- nó Ready, `apiwpp` Ready, smoke test e backup saudáveis;
- zero pod antigo `ContainerStatusUnknown` no namespace `apiwpp`;
- atualizações aplicadas ou impedimento explicitamente registrado;
- audit log ativo com retenção limitada;
- nenhuma nova porta exposta;
- destino externo de alerta registrado como pendente se não houver escolha.

## Fase 2B - Contenção externa do Blindou

Status: preparação declarativa concluída em 2026-08-19 e substituída pela
exceção temporária da Fase 2C. Nenhuma barreira física será comprada agora.

Concluído sem alterar o runtime:

- identificar a ONT Huawei HG8145V5 e confirmar que o servidor ainda está
  diretamente conectado à LAN residencial;
- registrar HOME, EDGE e BLINDOU-DMZ como zonas distintas;
- declarar negação por padrão, conector Cloudflare externo, allowlist de saída,
  kill switch e testes negativos;
- preparar namespace vazio, baseline de admissão, verificador e rollback.

O aceite externo permanece referência futura, mas não é gate da primeira
operação temporária.

## Fase 2C - Contenção local temporária do Blindou

Status: camada de host concluída em 2026-08-19 e persistência pós-reboot
corrigida e verificada em 2026-08-21. A primeira aplicação foi revertida após
falha de DNS; o reboot posterior revelou que o `systemd-networkd` reativava
IPv6 depois do sysctl inicial. O unit pós-`network-online` está habilitado e
ativo, e o gate voltou a passar sem regressão do `apiwpp`.

Concluído no repositório:

- controlador `blindou-hostctl` com interface fechada, backup e rollback;
- regras UFW para negar destinos privados no host e no encaminhamento dos Pods,
  além de negar entrada da LAN sem interromper DNS/DHCP/SSH/K3s autorizados;
- desativação reversível de IPv6 somente na interface física;
- namespace `blindou-edge` com quota, Pod Security e default deny;
- contrato do `cloudflared` por digest, Secret exclusivo, TCP/7844 e origem
  ClusterIP;
- decisão de preservar `apiwpp`, reservar o restante ao Blindou e impedir novos
  workloads Pixel/CIA/SaferWPP;
- risco de `root` e expiração na Vultr registrados.

Aceite concluído no host:

- controlador root-owned corrigido e único caminho sem senha do Blindou;
- UFW e sysctl verificados sem perda de DNS, Internet, SSH, K3s ou `apiwpp`;
- ONT inacessível a partir do host;
- somente 22/6443 acessíveis a partir do PC administrativo entre as portas
  testadas;
- reaplicação idempotente e zero unit systemd falha.

Próxima ação exata, mediante autorização específica:

1. preparar `blindou-deployctl` e provisionar os namespaces vazios com gates
   inicialmente bloqueados;
2. provisionar banco, identidades, backup e observabilidade do Blindou;
3. configurar domínios, Tunnel, Access/mTLS, Secrets e imagens por digest;
4. repetir o gate integrado antes da primeira release.

Aceite ainda pendente:

- confirmar na ONT a ausência de DMZ host, UPnP e port forward para o servidor;
- `cloudflared` somente em `blindou-edge` e token somente no Secret da EDGE;
- API/redirector apenas ClusterIP e saúde pública validada fora do host;
- migração Vultr mantida como encerramento obrigatório da exceção.

## Fase 2D - Plataforma e controlador de deploy do Blindou

Status: fundação interna e conector concluídos e verificados em 2026-08-20;
cadeia de pull e candidata assinada preparadas e verificadas em 2026-08-21. Em
2026-08-22, a nova candidata `0ba8384` e o scan fechado das imagens passaram;
o controlador foi instalado, o bundle entrou no cache fechado e a prova viva
das quatro imagens passou. A Fase 2D continua aberta pelos Secrets internos e
demais gates prévios à primeira release.
A candidata `27495b0` e sua extensão de 18 workers foram substituídas antes do
deploy pela D019. O repositório prepara agora uma nova candidata de 16 workers,
gate intermediário `secrets-only`, recibo de backup offsite, transição vinculada
ao SHA e bootstrap do superadmin sem configurar UAZAPI, Resend ou Pagar.me.
Essa extensão ainda não descreve estado vivo enquanto commit, bootstrap, prova
GHCR e deploy não forem concluídos.
Zero Trust e o Tunnel remoto `blindou-physical` estão saudáveis; somente
`blindou-edge` passou para `connector-only`, enquanto `blindou-production`,
migrations e release continuam bloqueados. Cloudflare for SaaS está ativado no
plano da zona e sua credencial restrita foi validada e guardada fora do
runtime; nenhum custom hostname de cliente foi criado.
O contrato de imagens próprias usa GHCR privado. O controlador atualmente
instalado ainda precede a extensão para quatro imagens; o PAT classic do host
foi validado com exatamente `read:packages`,
mantido root-only e fora do Kubernetes. O workflow `32534879401` aprovou os
gates, scans e publicação para o SHA
`1265c3be1e808d522887f38ff47e9a110533677a`. O bundle desse SHA foi assinado
fora do servidor, validado e armazenado no cache fechado. `current_release`
permanece ausente e nenhuma migration ou workload foi executado.
O contrato local de prova integral do pull baixou e conferiu os quatro pacotes
privados da candidata sem criar Secret ou workload. O orquestrador transportou
os três artefatos assinados, validou a release no cache e só então executou a
prova pelo helper local fechado autorizado em D018.

Objetivos:

- criar `blindou-deployctl` root-owned com release assinada, imagem por digest,
  lock, escopo fechado e rollback;
- aplicar `blindou-production` e `blindou-edge` vazios com admissão, quotas,
  NetworkPolicies e gates inicialmente bloqueados;
- provisionar banco, papéis, TLS, backup e observabilidade exclusivos do
  Blindou, sem acessar dados do `apiwpp`;
- configurar domínios, Tunnel, WAF, Access/mTLS e Secrets por canal seguro;
- atestar os gates somente depois dos testes negativos e da verificação do
  `apiwpp`.

Aceite:

- somente o controlador fechado consegue alterar recursos Blindou;
- nenhum Service público, porta na ONT ou segredo fora do namespace correto;
- `apiwpp-deployctl verify` continua aprovado;
- backup, alertas, rollback e monitor externo comprovados.

Estado Pagar.me concluído nesta etapa:

Em 2026-08-25, o contrato de transporte dos bootstraps foi fechado para exigir
o mesmo conjunto completo de fontes em todos os seis orquestradores. Isso evita
que a prova GHCR ou uma rotação de credencial falhe antes da instalação quando
o controlador ganha um novo helper obrigatório.
Na primeira ativação viva, o gate redundante que executava `curl` dentro da
imagem mínima impediu também o rollback. O journal root-only foi preservado. A
correção manteve a prontidão pelas probes `/ready` observadas no rollout e
proibiu dependência de ferramenta no Pod; a repetição recuperou o journal e
concluiu a ativação.

1. secret key live validada e preservada somente no cofre root-only;
2. webhook HTTPS cadastrado com segredo forte rotacionado;
3. sete planos live mensais `prepaid`, com descritor `BLINDOU`, criados ou
   corrigidos e conferidos contra o catálogo versionado;
4. release `ab15a31` aprovada, backup `blindou-20260825T092915Z` confirmado
   offsite, migration `0009` aplicada e runtime Pagar.me ativo;
5. catálogo e checkout transparente validados sem enviar cartão ou criar
   cobrança real.

Estado D024/D052/D053 concluído em 2026-08-27:

1. os dois gates corrigidos foram instalados e revalidados;
2. o backup `blindou-20260827T120324Z` foi confirmado offsite;
3. a migration `0012` e a release `d5766d8` foram aplicadas uma única vez;
4. o link Amazon redirecionou, preservou o identificador de afiliado e
   registrou Analytics; host/código desconhecido permaneceu em HTTP 404;
5. Pagar.me permaneceu ativo e UAZAPI/Resend continuaram adiados.
6. a release `11e21b3` eliminou a concorrência do relatório, passou nos gates
   e foi validada com carga fria e novo redirect Amazon;
7. o relatório passou a sete acessos e o código desconhecido continuou em 404.

Próxima ação exata, ainda dependente de autorizações próprias:

1. publicar a release Blindou compatível com D026 e, sem migration, executar a
   ativação fechada da Shopee; AppID/App Secret serão informados depois,
   diretamente em `/marketplaces`, e testados com um produto ativo;
2. Mercado Livre depende da extensão Blindou publicada e de seus parâmetros
   próprios; Magazine Luiza depende do identificador comercial do cliente;
3. quando houver decisão explícita de compra live, validar tokenização direta,
   assinatura, webhook, reconciliação e cancelamento
   sem PAN/CVV na API, logs ou banco;
4. somente depois dos marketplaces, seguir com UAZAPI/Resend;
5. manter a cota global da aplicação em 90 custom hostnames e monitorar a
   origem de fallback e o domínio já ativo sem criar hostname adicional.

## Fase 2E - Primeira release e capacidade do Blindou

Status: a release `11e21b3319c197ef18440e7f494290b298f2db1e` está aplicada
com 12 migrations, todos os workloads Ready, aplicação e EDGE em `passed`,
Tunnel e R2 saudáveis e backup `blindou-20260825T092915Z` confirmado offsite.
O gate de atualização foi corrigido para aceitar EDGE `passed` somente quando
há um ponteiro seguro de release corrente; a primeira instalação continua
exigindo `connector-only` e ausência desse ponteiro. A janela protegida criou
`gleisonsette@gmail.com` como `super_admin` e validou o login real pela API
pública. A UI foi aprovada em 2026-08-24. O Pagar.me foi ativado em 2026-08-25
após migration e deploy separados; UAZAPI e Resend continuam deliberadamente
ausentes até a última etapa da D020. Nenhuma cobrança real foi criada na
validação.

Objetivos:

- executar migration, primeira release do núcleo e smoke público pela borda
  Cloudflare, sem configurar UAZAPI, Resend ou Pagar.me;
- validar primeiro o login e a interface; depois, em trabalhos separados e
  autorizados, validar captura, dispatch, redirect, Analytics, UAZAPI e filas
  sem reativar o provider local `api-wpp`;
- testar reboot, queda de dependência, backup/restore e rollback do Blindou;
- executar degraus de carga e soak com margem, observando HDD, memória, swap e
  Fast Ethernet;
- registrar o limite que dispara expansão e posterior cutover para Vultr.

## Fase 2F - PostgreSQL dedicado do Blindou

Status: I0 aprovada; I1 automatizada concluída em 2026-08-29, com imagem,
bundle, controlador, quarentena e `pull-proof` aprovados. A confirmação humana
final está pendente antes de qualquer próxima fase.
O pacote `platform/blindou-data/` nasce bloqueado; imagem privada, supply chain,
bundle, `blindou-datactl`, backup, restore-base e gates descartáveis estão
preparados. O PostgreSQL nativo continua autoridade. O workflow hospedado foi
recusado antes dos steps por bloqueio de cobrança; D031/D064 autoriza, até o
usuário solicitar o retorno ao GitHub Actions, somente o build/scan efêmero da
imagem PostgreSQL no servidor, com publicação executada pela estação.

Ordem:

1. concluído: D031/D064 gerou a imagem do SHA Blindou exato no executor
   efêmero; a estação publicou e obteve scan, SBOM, proveniência e identidade
   OCI;
2. concluído: bundle assinado e controlador separado da plataforma foram
   publicados;
3. concluído: instalar somente o `blindou-datactl` e a quarentena vazia;
4. concluído: `pull-proof` direto validou uma imagem, 15 blobs e 157.256.746
   bytes, mantendo gate `blocked` e zero Secret, PVC, Job, Pod ou workload de
   banco;
5. parar novamente para autorização: `foundation`, I2, dados e cutover não são
   consequência da prova.

Aceite I1 operacional limitado:

- imagem privada `linux/amd64` acessível integralmente por digest;
- bundle aceito pela assinatura `blindou-data` e evidência vinculada ao mesmo
  sujeito OCI;
- controlador instalado por bootstrap exato, sem `sudo` genérico;
- namespace `blindou-data` bloqueado, com quarentena/admissão e zero objeto
  operacional;
- host, APIWPP, Blindou ativo, portas e autoridade PostgreSQL anterior
  preservados.

I2 permanece uma operação separada: exige backup offsite, pausa de escritores,
restore final, comparação, troca de DSNs/rede, rollout e smoke. Remoção do
database, logins ou HBA nativos exige autorização posterior própria.

## Fase 3 - Slot alternável APIWPP/SaferWPP

Status: auditoria viva, decisão D023, fundação SaferWPP e contratos dos itens 4
a 7 concluídos nos repositórios. Em 2026-08-27, `secondary-slotctl` foi instalado
e inicializado na geração 1 com APIWPP ativo e SaferWPP vazio. Fundação e
controladores SaferWPP ainda não foram materializados.
Nenhuma etapa desta fase autoriza, por si só, alterar o servidor.

Objetivo:

- manter o Blindou sempre ativo e provar que nenhuma transição altera seus
  recursos ou sua saúde;
- permitir que APIWPP e SaferWPP usem, de forma mutuamente exclusiva, o slot de
  capacidade residual do host;
- suspender APIWPP de modo reversível, preservando todo estado durável e o
  gateway privado;
- ativar SaferWPP somente por controlador próprio, release assinada, capacidade
  comprovada, backup validado e gates negativos.

Ordem obrigatória:

1. concluído em 2026-08-26: auditar em modo somente leitura consumo vivo,
   requests, limits, picos, disco, I/O, conexões PostgreSQL e margem operacional
   de Blindou, APIWPP, K3s, backup e monitoramento;
2. concluído em 2026-08-26: resolver D023 e atualizar o contrato SaferWPP para
   cluster PostgreSQL exclusivo na porta 55432, teto 24 e recursos próprios;
3. concluído no repositório em 2026-08-26: declarar cluster, stanza, backup,
   exporter e alertas exclusivos, fechar orçamentos separados de Keycloak e
   Control Plane e recalibrar a quota `saferwpp-lab`; nenhum artefato foi
   aplicado ao servidor;
4. concluído no repositório APIWPP em 2026-08-26: fechar os contratos de estado
   e implementar operações
   `suspend`, `verify-suspended` e `resume`, incluindo lock, auditoria,
   reconciliação, rollback e recusa de retomada com SaferWPP ativo;
5. concluído declarativamente no repositório `servidor` em 2026-08-26:
   implementar atestado root-only, lock global, admissão fail-closed,
   reconciliação, auditoria, alertas e gates dos namespaces, sem mudar nenhum
   recurso Blindou e sem instalar os artefatos no host;
6. concluído nos repositórios em 2026-08-26: criar e validar
   `saferwpp-deployctl`, `saferwpp-backupctl` e `saferwpp-secretsctl`, fechar a
   prova pós-migration com papéis, grants e RLS e alinhar o schema consumidor
   da plataforma; nenhum controlador foi instalado no host;
7. concluído nos repositórios em 2026-08-26: construir os três controladores em
   Linux/amd64, gerar SBOM, executar scan de vulnerabilidade e segredo, assinar
   a release, implementar verificador independente, bootstrap root fechado,
   certificados Kubernetes exclusivos com renovação e alertas; nenhum
   artefato foi instalado no host;
8. concluído parcialmente em 2026-08-27: materializar e inicializar o
   controlador do slot com APIWPP ativo, zero workload SaferWPP, admissão e
   métricas verificadas; ainda em janela e autorização próprias, materializar a
   fundação vazia, instalar os três controladores SaferWPP e produzir as
   evidências reais de backup e Secrets;
9. somente em janela e autorização próprias, criar backup prévio, suspender o
   APIWPP, validar sua recuperabilidade e provar que Blindou permaneceu igual;
10. somente após todos os gates, criar dados/dependências e implantar a release
   SaferWPP assinada; validar rollback completo até APIWPP ativo e SaferWPP
   suspenso.

Resultado da auditoria:

- hardware observado: continuidade do lab permitida para planejamento, sem
  alegação de capacidade de produção;
- PostgreSQL compartilhado: reprovado para o orçamento SaferWPP atual;
- quota viva `saferwpp-lab`: continua reprovada com 1536Mi; o manifesto-alvo
  agora fecha 2 CPU/4Gi de requests, 7 CPU/8Gi de limits, 12 pods, três PVCs e
  24Gi;
- backup vivo SaferWPP: ainda ausente; o repositório agora define stanza
  local/R2, WAL, RPO/RTO, timers e evidência de restore v2;
- Keycloak e Control Plane: workloads ainda ausentes; namespaces exclusivos,
  cotas, limites, default deny e orçamentos de uma réplica estão declarados;
- Blindou final: release `dc2aa63`, 11 migrations, gates `passed`, backup e
  conector saudáveis; nenhum recurso foi alterado pela auditoria;
- D023 resolvida: cluster SaferWPP exclusivo com teto 24 e PgBouncer de dez
  backends; nenhum recurso foi criado no host;
- controlador compartilhado: instalado a partir do commit `76fec3c`, com
  sudoers, admissão, timer, métricas, alertas e reconciliação; o atestado
  root-only está válido na geração 1, com APIWPP ativo e SaferWPP vazio;
- controladores SaferWPP: deploy, backup/restore e inventário de Secrets estão
  implementados localmente; o schema da plataforma exige as mesmas provas de
  papéis, grants e RLS do consumidor;
- cadeia de release: `swpc-20260827T010424Z-5e8b21d60cd9` passou assinatura,
  manifesto, SBOM, Trivy, proveniência e os verificadores independentes local e
  da plataforma; o bootstrap fechado e a renovação de identidades foram
  implementados, mas continuam ausentes do host;
- transporte e validação Linux: concluídos no staging user-owned
  `/home/apiadmin/saferwpp-platform-bootstrap-a8127c9-5e8b21d`, sem instalação;
- próximo gate: materializar a fundação vazia e depois os controladores
  SaferWPP. Nenhuma suspensão do APIWPP ou mudança de workload SaferWPP foi
  executada por este registro.

Aceite automatizado:

- os dois controladores recusam o estado APIWPP ativo + SaferWPP ativo;
- estado ausente, divergente ou ambíguo falha fechado e pode ser reconciliado;
- suspensão preserva objetos, PVC, banco, backups e gateway do APIWPP;
- retomada do APIWPP é recusada enquanto qualquer workload SaferWPP estiver
  ativo;
- verificações antes e depois demonstram que release, recursos e saúde Blindou
  não mudaram;
- backup e restore do APIWPP e do futuro banco SaferWPP possuem evidência
  válida, e rollback restaura o estado anterior sem perda de dados;
- porta 5432 e cluster compartilhado são recusados pelo SaferWPP; porta 55432,
  teto 24, recursos, stanza e exporter exclusivos coincidem com o contrato
  assinado;
- nenhum novo Service público, porta na ONT, segredo no Git ou acesso cruzado a
  banco/namespace é introduzido.

Aceite manual:

- capacidade residual e margem de segurança são aprovadas com base na auditoria
  viva, sem reduzir o orçamento Blindou;
- o operador confirma APIWPP recuperável após a suspensão;
- o operador confirma o fluxo SaferWPP e o retorno ao estado APIWPP ativo;
- alertas e runbooks permitem identificar transição bloqueada ou reconciliada.

## Fase 3B - DRE familiar independente

Status: rollout persistente autorizado e em andamento. Fundação, Secrets
pré-deploy e executor rootless estão prontos. A candidata do commit DRE
`69716bb0a23e02cc839f1adac0a41fbc521f7f04` passou nos gates integrais, teve as
três imagens publicadas por digest e foi empacotada como
`dre-20260902T061906Z-69716bb0a23e`. As duas correções de inventário edge foram
instaladas; a validação descartável passou. O primeiro deploy persistente
falhou no `pgBackRest check` com código 82, antes das migrations, e o rollback
passou. Produção está com release `none`, gate `secrets-only`, PVC `Bound`,
PostgreSQL Ready e API/worker ausentes. O diagnóstico D038 confirmou que o
BusyBox recusava opções GNU de `realpath` no `archive-push` e que o rótulo de
projeto do namespace foi retirado. O commit DRE `8c52807` corrige ambos e passa
agora pela cadeia integral antes da nova tentativa.

Ordem obrigatória:

1. concluído offline: validar manifests, empacotamento determinístico,
   assinatura Ed25519, SBOM/scan, escopo Kubernetes e rejeições negativas;
2. concluído offline: validar fundação, RBAC, admissão fail-closed, interface
   sudo fechada, identidade renovável, retenção, alertas e restore descartável;
3. concluído em 2026-08-29: auditoria viva conjunta de CPU, memória, HDD,
   storage K3s, nó, Blindou, APIWPP e slot;
4. concluído em 2026-08-29 sob D030: chave privada Ed25519 protegida fora do
   servidor e instalação somente do controlador/fundação vazia;
5. concluído em 2026-08-30: publicar imagens examinadas e importar a release
   assinada sem criar Secret ou workload;
6. concluído em 2026-08-30 sob D032: corrigir, publicar e instalar o contrato
   para que o token da ponte seja coordenado em memória com o Cloudflare antes
   da inicialização, sem criar Secrets;
7. concluído: criar credenciais mínimas GHCR/R2, coordenar o token da ponte e
   criar os cinco Secrets por entrada protegida, mantendo FCM desabilitado;
8. concluído em 2026-08-31: publicar as três imagens finais, importar o bundle
   schema 2 e aprová-lo integralmente em `dre-validation` descartável;
9. concluído em 2026-08-31: executor rootless sem daemon e sem acesso ao K3s
   instalado; `make release-check` e `make e2e` aprovados em ambiente sintético
   descartável, com limpeza comprovada dos recursos da execução;
10. em andamento sob autorização explícita de 2026-09-01: a segunda correção
   fail-closed e a validação `69716bb` passaram; o código 82 do pgBackRest foi
   diagnosticado sob D038; a causa foi corrigida em `8c52807`, cujos gates,
   imagens e release renovada passaram. D039 foi instalado, a validação
   descartável passou e a primeira recuperação limitada compensou um novo
   código 50 sem tocar migrations; capturar o erro sanitizado, concluir a
   recuperação, aplicar migrations/deploy persistentes, criar contas
   atomicamente e comprovar backup/restore;
11. em andamento sob a mesma autorização: criar rota HTTPS, configurar
   `DRE_API_ORIGIN` e chave Android definitiva. FCM, saldo inicial e dados
   financeiros reais permanecem fora desta operação.

Aceite automatizado offline:

- release real do repositório DRE é aceita pelo verificador independente;
- NodePort, archive malicioso e vulnerabilidade alta/crítica são recusados;
- DRE não integra o slot e não altera fingerprints de APIWPP/Blindou;
- PostgreSQL, credenciais, PVC, namespaces e chave de assinatura são exclusivos;
- restore usa volume descartável e não arquiva WAL no destino de produção;
- audit log possui retenção diária de 30 dias e planos antigos são limitados;
- token ausente, curto ou inválido é recusado e nenhum valor aparece em saída.

Aceite operacional:

- concluído: capacidade viva conjunta aprovada sem reduzir a margem dos
  projetos ativos;
- concluído: bootstrap vazio, prova negativa de admissão, métricas ingeridas,
  zero porta DRE e projetos protegidos íntegros;
- concluído: release assinada aceita no cache sem alterar gate, PVC, workload ou
  o ocupante do slot secundário;
- concluído: controlador instalado declara
  `bridge_token_source=orchestrator-stdin` e preserva o cache da release;
- concluído: release schema 2 aprovada no ambiente sintético, inclusive E2E e
  reinícios, com remoção comprovada de namespace/PVC/PV;
- concluído: executor rootless sem daemon/K3s e gates literais do Makefile
  aprovados, com
  remoção de containers, redes, volumes, imagens, processos e workspace;
- backup offsite e restore descartável comprovados com a release implantada;
- API, worker e PostgreSQL saudáveis sem exposição pública ou acesso cruzado.

## Fase 4 - Pixel/CIA lab (cancelada para este host)

Status: cancelada para este host por decisão D013.

O inventário anterior permanece somente no histórico. Nenhum workload, banco,
controlador ou dependência Pixel/CIA será implantado. Reativação exige nova
decisão e capacidade fora do caminho reservado ao Blindou.

## Fase 5 - Entrada externa controlada

Status: substituída pela borda Cloudflare exclusiva do Blindou nas Fases
2C/2D. SSH, 6443, PostgreSQL e métricas continuam privados.

## Fase 6 - Ensaio combinado e operação

Status: o ensaio simultâneo de três projetos continua cancelado. Por D022, o
ensaio futuro permitido combina apenas Blindou com um ocupante do slot
secundário: APIWPP ou SaferWPP, nunca ambos. Os critérios estão na Fase 3.
