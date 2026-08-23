# Plano de implementação da plataforma

metadata:
  canon_id: canon-plano-implementacao
  source_path: memory/canon/plano-implementacao.md
  generated_from: plano aprovado pelo usuário em 2026-08-15
  updated_at: 2026-08-22
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

Próxima ação exata:

1. publicar uma nova candidata assinada com o modo explícito de revisão da UI,
   sem UAZAPI, Resend e Pagar.me e com 16 workers contínuos;
2. comprovar o pull integral dessa candidata e preparar somente os segredos
   internos, sem credenciais dos três provedores;
3. criar backup, cópia offsite e recibo, liberar os gates para o mesmo SHA,
   executar migrations, aplicar a release e criar
   `gleisonsette@gmail.com` como `super_admin` por entrada protegida;
4. validar login público, API e painel; somente depois da aprovação visual do
   usuário iniciar trabalhos separados para UAZAPI, Resend e Pagar.me;
5. manter a cota global da aplicação em 90 custom hostnames e revalidar a
   origem de fallback antes do primeiro fluxo autorizado de domínio por
   conta/tenant.

## Fase 2E - Primeira release e capacidade do Blindou

Status: a candidata `ccc4edd` foi assinada, comprovada e aplicada até a
fronteira entre `0001` e `0002`. `0001` foi registrada; `0002` falhou fechada
porque uma ACL em lote alcançou a função root-owned
`pg_stat_statements_reset`. O rollback restaurou a contenção, o histórico SQLx
ficou em um e não existe release corrente. O SHA Blindou corretivo `6365832`
está no workflow `32608484692`; o gate agora executa o binário real de migration
com login não administrativo e extensão sob outro owner. O próximo passo é,
após o gate passar, assinar e comprovar a nova candidata, criar backup offsite
recente, aplicar `0002` a `0008` e criar o superadmin sem introduzir credenciais
de UAZAPI, Resend ou Pagar.me.

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

## Fase 3 - SaferWPP lab (cancelada para este host)

Status: cancelada para este host por decisão D013; a auditoria histórica é
preservada no histórico, mas nenhum workload, banco, controlador ou dependência
será implantado. Reativação exigiria substituir explicitamente D013 e criar um
novo plano de capacidade fora do caminho reservado ao Blindou.

## Fase 4 - Pixel/CIA lab (cancelada para este host)

Status: cancelada para este host por decisão D013.

O inventário anterior permanece somente no histórico. Nenhum workload, banco,
controlador ou dependência Pixel/CIA será implantado. Reativação exige nova
decisão e capacidade fora do caminho reservado ao Blindou.

## Fase 5 - Entrada externa controlada

Status: substituída pela borda Cloudflare exclusiva do Blindou nas Fases
2C/2D. SSH, 6443, PostgreSQL e métricas continuam privados.

## Fase 6 - Ensaio combinado e operação

Status: substituída pelo ensaio exclusivo do Blindou na Fase 2E. Não haverá
ensaio combinado de três projetos neste host.
