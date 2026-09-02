# Histórico de execução

metadata:
  canon_id: canon-historico-execucao
  source_path: memory/canon/historico-execucao.md
  generated_from: auditorias e implementações autorizadas no laboratório
  updated_at: 2026-08-31
  status: canonical

## Regra de registro

O histórico é append-only. Correção de uma entrada cria nova seção referenciando
a anterior; não apagar uma evidência operacional já registrada. Nunca incluir
segredo, payload sensível, conteúdo de chave ou senha.

## 2026-08-15 - Auditoria inicial

Resultado: concluído.

- Acesso SSH por identidade permanente e host key estrita validado.
- Host, rede, portas, serviços, recursos, K3s, PostgreSQL, backups e Prometheus
  inspecionados sem alteração.
- Somente `apiwpp` estava implantado; Deployment 1/1 Ready e smoke registrado
  como aprovado.
- Dois pods antigos estavam em `ContainerStatusUnknown`.
- Do PC administrativo, somente 22 e 6443 responderam entre as portas testadas.
- Backups local/R2, WAL e três targets Prometheus estavam saudáveis.
- Atualizações de sistema e ausência de receptor externo de alertas foram
  registradas como pendências.
- Concluiu-se que o host suporta três projetos para validação funcional com uma
  réplica e limites, mas não representa HA ou capacidade de produção.

## 2026-08-15 - Autorização das Fases 0 a 2

Resultado: em execução.

- O usuário aprovou a arquitetura proposta.
- O usuário pediu registro RAG para continuidade com baixo consumo de contexto.
- O usuário autorizou criar a base declarativa e estabilizar o servidor.
- Alterações externas que exijam escolha de receptor ou credencial continuam
  dependentes de decisão explícita; nenhum destino será presumido.

## 2026-08-15 - Memória RAG local

Resultado: concluído.

- Criados canons separados para estado, arquitetura, plano, decisões e
  histórico append-only.
- Criados índice BM25, manifestos de fontes e scripts de reconstrução, busca e
  verificação sem serviço externo.
- A consulta `qual e o proximo passo` retornou o plano de implementação como
  primeira fonte.
- `AGENTS.md` tornou obrigatória a consulta seletiva e a atualização da memória
  após mudança operacional.

## 2026-08-15 - Backup e restauração antes da manutenção

Resultado: concluído.

- Restore do repo2/R2 executado em data directory, socket e porta isolados.
- Foram restaurados 23,5 GB em aproximadamente 542 segundos; banco
  `clone_wpp`, checksums e 18 migrations foram confirmados.
- Backups incrementais repo1/local e repo2/R2 foram forçados e terminaram com
  `Result=success`.
- K3s foi parado por janela curta; datastore e configuração foram copiados para
  `/var/backups/shared-lab/20260815T113334Z` com permissão root-only e checksum
  SHA-256 aprovado.

## 2026-08-15 - Base compartilhada e auditoria K3s

Resultado: concluído.

- Criados e aplicados os namespaces vazios `cia-pixel-lab` e `saferwpp-lab`.
- Aplicados Pod Security `restricted` v1.36, ServiceAccount padrão sem token,
  cotas, limites, default deny e DNS explícito.
- ValidatingAdmissionPolicy aplicada; um NodePort em dry-run server-side foi
  recusado como esperado.
- Audit log de metadados ativado com rotação 14 dias/5 arquivos/50 MiB, sem
  corpos de Secret nos eventos amostrados.
- `apiwpp` permaneceu Ready durante a validação pós-restart.

## 2026-08-15 - Limpeza e verificação do apiwpp

Resultado: concluído.

- Removidos somente os pods órfãos `apiwpp-5c745897b7-jrp7v` e
  `apiwpp-5c745897b7-kjg6g`, ambos não Ready e pertencentes a ReplicaSet.
- O verificador passou a selecionar a única réplica Running e Ready antes de
  aguardar a condição do pod.
- Rollout, uma réplica, 18 migrations, health, ready, autenticação de métricas e
  smoke test passaram.

## 2026-08-15 - Atualização e correção dos dependentes

Resultado: concluído após correção.

- Atualizados 15 pacotes sem remoções: PostgreSQL 18.6, libpq, pgBackRest 2.59,
  linux-firmware, Kerberos e Apport entre eles.
- A primeira validação pós-update detectou PostgreSQL Exporter e gateway
  privado inativos. A causa foi `Requires` propagar a parada sem propagar a
  partida.
- O exporter 0.15 também consultava `stat_bgwriter` incompatível com PostgreSQL
  18. Apenas esse coletor foi desabilitado; os demais permaneceram ativos.
- Adicionado `PartOf` nas fontes declarativas e partida explícita na rotina de
  manutenção. Três targets Prometheus ficaram `up`, sem novo erro do coletor.
- Gateway voltou a escutar somente em `10.203.0.2:8443` e `apiwpp` passou
  novamente no smoke test.
- Verificação final confirmou K3s v1.36.2, PostgreSQL 18.6, pgBackRest 2.59,
  zero pacote pendente, sem reboot requerido e nenhuma unit systemd falha.
- Pela LAN, somente TCP 22 e 6443 responderam; todas as portas de app, banco,
  gateway privado, métricas e NodePort testadas permaneceram fechadas.

## 2026-08-15 - Encerramento das Fases 0 a 2

Resultado: concluído.

- Todos os critérios verificáveis das Fases 0, 1 e 2 passaram.
- D005, receptor externo de alertas, continua pendente porque exige escolha e
  credencial do usuário; nenhum destino fictício foi configurado.
- Próximo passo canônico definido como Fase 3.1, preparação do SaferWPP lab.

## 2026-08-15 - Preparação do repositório Git

Resultado: preparado, commit não autorizado.

- `C:\github\servidor` foi inicializado na branch `main`.
- Os 36 arquivos foram staged e passaram em `git diff --cached --check`, na
  verificação da RAG e na varredura por padrões conhecidos de segredo.
- Nenhum commit foi criado porque a política global exige pedido específico.
- As mudanças localizadas no `apiwpp` não foram staged nem commitadas para não
  misturar o trabalho já existente do usuário.

## 2026-08-15 - Autorização de commit e publicação

Resultado: concluído.

- O usuário autorizou explicitamente commit e push do repositório
  `C:\github\servidor`.
- Criado o remoto público `https://github.com/GleisonSette/servidor`.
- Adicionada licença MIT, copyright 2026 Gleison Sette.
- O commit e o push abrangem somente este repositório; as mudanças no
  `apiwpp` permanecem separadas porque seu working tree já continha trabalho do
  usuário.

## 2026-08-15 - Guias de acesso segregado dos três projetos

Resultado: documentação concluída; nenhuma mudança operacional no servidor.

- Confirmados por SSH estrito o hostname `apiwpp` e o escopo de `sudo` do
  usuário administrativo, sem ler segredo.
- `apiwpp-deployctl` e `apiwpp-backupctl` estavam presentes; os controladores
  Pixel e SaferWPP estavam ausentes.
- Criado `README-SERVIDOR-LOCAL.md` nos repositórios `apiwpp`, Pixel/CIA e
  SaferWPP, com ownership, acesso, operações permitidas, proibições e
  encerramento.
- Os `AGENTS.md` passaram a exigir o guia antes do acesso ao host.
- Commits isolados criados: `31e9637` no apiwpp, `608a3de4` no CIA/Pixel e
  `d8fce28` no SaferWPP. Nenhuma alteração anterior do usuário foi incluída.
- Pixel e SaferWPP permanecem bloqueados para alterações até a plataforma
  instalar controladores próprios. Nenhum workload, namespace, banco, serviço,
  Secret, porta ou configuração do servidor foi alterado.

## 2026-08-15 - Progresso parcial da Fase 3.1

Resultado: auditoria iniciada e pausada para priorizar os guias de acesso.

- A base SaferWPP foi confirmada limpa em `e8a0427` antes das mudanças
  documentais desta tarefa.
- Foram lidos `AGENTS.md`, política RAG, arquitetura, invariantes e decisões do
  produto; chart, Dockerfiles, migrations, dependências e configurações foram
  inventariados em modo somente leitura.
- O chart declara `kubeVersion >=1.34.9-0 <1.35.0-0`, incompatível com o K3s
  1.36.2 do laboratório. O schema aceita `development`, `test`, `staging` e
  `production`, mas não `lab`.
- O chart implanta quatro workloads e pressupõe PostgreSQL/PgBouncer, NATS,
  Keycloak/Control Plane e ClamAV em namespaces separados. UAZAPI e R2 reais
  continuam gates externos.
- PrometheusRule e dashboard vêm habilitados por padrão; o perfil lab precisa
  compatibilizar isso com a observabilidade realmente instalada.
- Nenhuma imagem foi construída, nenhum controlador SaferWPP foi instalado e
  nenhuma mudança ocorreu no servidor. A próxima ação é concluir o perfil lab,
  riscos, aceite, rollback e diff previsto da Fase 3.1.

## 2026-08-19 - Auditoria de contenção do Blindou

Resultado: preparação declarativa concluída; isolamento físico pendente.

- O usuário autorizou reclassificar o uso do servidor para receber o Blindou e
  alterar este repositório em commit separado da aplicação.
- A ONT foi identificada sem autenticação como Huawei HG8145V5, perfil `OI2`,
  em `192.168.100.1`; somente 80/443 responderam entre as portas administrativas
  verificadas. Nenhuma configuração do equipamento foi alterada.
- SSH estrito confirmou `apiwpp`, Ubuntu 24.04.4, kernel 6.8.0-137, K3s,
  PostgreSQL, AppArmor e atualizações automáticas ativos. O servidor continuava
  em `192.168.100.59/24`, com rota direta para a ONT; `eno1` estava inativa.
- Concluiu-se que a topologia atual não contém comprometimento do host em
  relação à rede residencial. Uma segunda NIC no mesmo host não corrige essa
  fronteira.
- Foi definida barreira externa com zonas HOME, EDGE e BLINDOU-DMZ, negação por
  padrão, `cloudflared` fora do servidor, allowlist de providers e kill switch
  externo. A função DMZ host da ONT, UPnP e port forwarding foram proibidos.
- Foram preparados namespace vazio, admissão de produção, contrato de rede,
  verificador fail-closed e runbook. Nada foi aplicado ao host, K3s, ONT,
  Cloudflare ou rede.
- A conferência final somente leitura manteve a rota direta já registrada e
  confirmou AppArmor/atualizações automáticas ativos, sem processo ou unit
  `cloudflared` no host.

## 2026-08-19 - Preparação da contenção temporária do Blindou

Resultado: artefatos validados offline; aplicação root pendente.

- O usuário decidiu adiar o firewall externo, preservar somente o serviço
  `apiwpp` existente e reservar toda a capacidade restante ao Blindou. Nenhum
  workload Pixel/CIA ou SaferWPP será adicionado ao host.
- Foi preparado `blindou-hostctl`, controlador root-owned de interface fechada,
  com backup, aplicação idempotente, detecção de estado parcial, verificação e
  rollback seletivo.
- As regras propostas negam destinos privados tanto para processos do host
  quanto para tráfego encaminhado dos Pods, negam entrada da LAN exceto
  22/6443 do PC administrativo e preservam DNS/DHCP.
- O rollback não depende da saúde do K3s ou do `apiwpp` e restaura os valores
  IPv6 capturados antes da aplicação.
- Foram preparados `blindou-edge`, Pod Security, quota, default deny e o
  contrato temporário com risco de `root` e expiração no cutover Vultr.
- Sintaxe Bash, YAML, contrato, ausência de segredo e coerência dos artefatos
  passaram no verificador offline. Nenhuma regra, sysctl, namespace, Secret,
  credencial, workload ou configuração Cloudflare foi aplicada ao runtime.
- O RAG da plataforma ganhou a suíte obrigatória de recuperação e passou em
  6/6 consultas canônicas depois da reconstrução e verificação do índice.
- A política `blindou-hostctl.sudoers` foi copiada para diretório temporário do
  usuário, aprovada pelo `visudo` real do Ubuntu e comparada por SHA-256 com a
  fonte local. O arquivo e o diretório temporários foram removidos; nada foi
  instalado em `/etc/sudoers.d`.

## 2026-08-19 - Staging do bootstrap Blindou no servidor

Resultado: inbox versionado preparado; instalação root pendente.

- Os quatro artefatos do commit de plataforma `4a2bf78` foram enviados para
  `/home/apiadmin/blindou-platform-bootstrap-4a2bf78/operations/remote`.
- Scripts ficaram com modo `0700` e a política sudoers com modo `0600`, todos
  pertencentes ao usuário não privilegiado antes do bootstrap humano.
- `bash -n` e `visudo -cf` passaram no Ubuntu; SHA-256 local e remoto coincidiu
  para cada arquivo.
- Nenhum arquivo foi instalado em `/usr/local/sbin`, `/etc/sudoers.d`,
  `/etc/ufw` ou `/etc/sysctl.d`; firewall, IPv6, K3s e `apiwpp` não foram
  alterados.

## 2026-08-19 - Primeira tentativa e rollback da contenção temporária

Resultado: falha detectada pelo gate; rollback concluído; serviços restaurados.

- O bootstrap humano instalou o controlador e a política sudoers root-owned
  com os modos esperados.
- A aplicação criou backup em
  `/var/backups/shared-lab/blindou-temporary-containment/20260820T014722Z` e
  instalou as regras novas, mas o gate recusou o estado por ausência do marcador
  `blindou-deny-lan`.
- A inspeção mostrou que o UFW deduplicou três regras semanticamente
  equivalentes já pertencentes ao `apiwpp`. As exceções DNS antigas ficaram
  abaixo da nova negação `192.168.0.0/16`, bloqueando resolução do host.
- O rollback humano removeu somente regras `blindou-*`, apagou o sysctl
  temporário e restaurou os valores IPv6 capturados no baseline.
- Depois do rollback, DNS e HTTPS pública passaram; `apiwpp-deployctl verify`
  confirmou uma réplica Ready, 18 migrations, API, métricas e gateway privado
  saudáveis.
- A correção passa a exigir exceções DNS específicas com origem
  `192.168.100.59`, confirmação imediata de cada marcador e rollback automático
  em falha de instalação ou verificação. A contenção permanece inativa até a
  versão corrigida ser instalada e aprovada.

## 2026-08-19 - Ativação corrigida da contenção temporária

Resultado: camada de host aplicada e verificada; nenhum workload Blindou foi
implantado.

- O inbox do commit `7cceebf` foi validado e o bootstrap humano instalou o
  controlador corrigido. O SHA-256 instalado coincidiu com a fonte versionada.
- A reaplicação criou backup root-only em
  `/var/backups/shared-lab/blindou-temporary-containment/20260820T015517Z`.
- Exceções DNS específicas foram inseridas acima das negações; DNS e HTTPS
  pública permaneceram funcionais, enquanto a ONT deixou de ser alcançável a
  partir do host.
- `blindou-hostctl verify` aprovou UFW, IPv6, DNS, Internet, ONT, K3s e
  `apiwpp`. O IPv6 da `enp2s0` ficou desabilitado.
- `apiwpp-deployctl verify` confirmou uma réplica Ready, 18 migrations, API,
  métricas e gateway privado saudáveis. Não havia unit systemd falha nem
  processo/unit `cloudflared` no host.
- Do PC administrativo, TCP 22 e 6443 responderam; 80, 443, 5432, 8090, 8443,
  9090, 9100, 9187 e 30000 permaneceram fechadas.
- Uma segunda execução do mesmo `apply-firewall` reconheceu o estado existente,
  repetiu o gate e comprovou idempotência.

## 2026-08-19 - Preparação da plataforma isolada do Blindou

Resultado: artefatos de controle e dados aprovados offline; bootstrap root e
mudança viva ainda pendentes.

- `blindou-deployctl` ganhou interface fechada, lock, assinatura de release,
  cache root-owned, validação de archive, escopo Kubernetes e rollback.
- `blindou-production` e `blindou-edge` foram separados da base compartilhada e
  passam a nascer vazios, em quarentena, com gate `blocked`.
- A fundação de dados declara database vazio, quatro logins sem privilégio,
  CA/certificado cliente e HBA com SCRAM mais certificado.
- O backup lógico valida o catálogo e usa CMS AES-256-GCM. Somente chaves
  públicas foram versionadas; as privadas ficaram fora do Git e do servidor.
- O contrato de release aceitou os manifests reais e recusou uma cópia
  adulterada com `NodePort`.
- O commit Blindou `18b493e` produziu o mesmo SHA-256 em dois empacotamentos; a
  assinatura Ed25519 foi aceita pela chave pública versionada e o bundle
  assinado passou novamente no verificador fechado da plataforma.
- Sintaxe Bash, Python/PyYAML, YAML, segredo e invariantes da fundação passaram
  localmente. Nenhum namespace, database, login, Secret, workload, Tunnel ou
  credencial externa foi aplicado nesta preparação.

## 2026-08-20 - Fundação interna isolada do Blindou no servidor físico

Resultado: fundação interna concluída; ativação externa e primeira release
permanecem bloqueadas.

- O bootstrap humano instalou a revisão final `6a21fb8` do
  `blindou-deployctl`; o SHA-256 instalado e o staging versionado coincidiram em
  `681c8723d77c3cf18c03ca3e96d21d02a37d8fa92acb50e1a6be8ad7e00dcc8e`.
- `blindou-production` e `blindou-edge` foram aplicados vazios, com gates
  `blocked`, quarentena, Pod Security `restricted`, default deny e testes
  negativos de Pod/Service público. A reaplicação comprovou idempotência e os
  dois namespaces permaneceram com zero objetos operacionais.
- O database vazio `blindou`, quatro logins sem privilégios administrativos,
  papéis separados, CA/certificado cliente e HBA `hostssl` com SCRAM foram
  provisionados e reaplicados de forma idempotente. Nenhuma migration ou tabela
  de aplicação foi criada.
- A validação viva revelou e corrigiu dois defeitos fail-closed: aspas simples
  inválidas no `include_if_exists` do HBA e falta de travessia do usuário
  `postgres` no staging plaintext do backup. Também foi eliminada uma detecção
  falsa de `cloudflared` por linha de comando, passando a comparar o nome exato
  do processo.
- O backup `blindou-20260820T111734Z` teve catálogo validado antes de ser
  criptografado por CMS AES-256-GCM. O envelope exportado possui SHA-256
  `048b0ac1413a39790f3a38755185179e0d881a46ffd4430ef89f8a6178782d4f`.
  A prova local com a chave DPAPI recuperou um dump `PGDMP`; chave e plaintext
  temporários foram removidos imediatamente.
- `blindou-hostctl verify`, `apiwpp-deployctl verify`, fundação, dados e backup
  passaram. O `apiwpp` manteve uma réplica Ready, 18 migrations, API, métricas
  e gateway privado saudáveis; zero unit systemd falhou.
- O timer de métricas está habilitado e ativo. Node Exporter e Prometheus
  observaram fundação `1`, dados `1`, coleta `1`, timestamp do backup e gates
  `0`. Não havia processo `cloudflared` nem staging plaintext em `/var/tmp`.
- Cloudflare, Secrets, migrations, workloads e release permaneceram ausentes.
  Receptor externo, retenção, RPO/RTO e credenciais externas continuam em P005.

## 2026-08-20 - Preparação do conector Cloudflare isolado

Resultado: artefatos locais aprovados; ativação viva depende somente da entrada
humana do token sem exibição.

- Zero Trust foi ativado e o Tunnel remoto `blindou-physical` foi criado no
  painel Cloudflare mediante autorização do usuário.
- O controlador ganhou fluxo fechado de `stdin` para criar o único Secret do
  edge, imagem `cloudflared` por digest, rollout, verificação e rollback
  automático.
- O novo gate `connector-only` admite somente um Pod `cloudflared`; quota mantém
  Services e PVCs em zero e `blindou-production` continua integralmente
  bloqueado.
- O script administrativo nunca lê o clipboard por automação: o usuário cola o
  token em campo oculto e o material não é salvo em disco, argumento ou Git.
- Sintaxe Bash/PowerShell, YAML, invariantes de segredo, quota e imagem imutável
  passaram localmente. Nenhuma mudança viva no cluster foi realizada por este
  registro.

## 2026-08-20 - Ativação do conector Cloudflare isolado

Resultado: concluído e saudável; aplicação permaneceu bloqueada.

- A primeira atualização do controlador instalou os arquivos, mas retornou
  código 1 porque sondagens esperadas chamavam funções que encerravam o shell e
  porque a coleta inicial podia disputar o lock com a verificação final.
- As sondagens foram isoladas em subshell e o bootstrap passou a aguardar o
  término da coleta inicial. Sintaxe e contrato dos artefatos passaram no
  staging antes da reinstalação root-owned; fonte e controlador instalado
  apresentaram o mesmo SHA-256.
- Mediante autorização explícita, o token do Tunnel foi lido da sessão
  autenticada do Chrome, enviado somente por `stdin` ao controlador e removido
  da área de transferência. O valor não foi exibido, salvo em arquivo,
  argumento, Git ou namespace da aplicação.
- O Tunnel `blindou-physical` apareceu como `Saudável` no Zero Trust. O
  controlador confirmou `cloudflare_connector=ready`, um único Pod e Secret em
  `blindou-edge`, gate `connector-only`, nenhum Service/PVC e
  `blindou-production` ainda `blocked` com zero objetos operacionais.
- `blindou-hostctl verify` e `apiwpp-deployctl verify` passaram após a mudança;
  DNS, Internet, ONT, K3s e `apiwpp` permaneceram saudáveis.

## 2026-08-20 - Cofre da credencial Cloudflare for SaaS

Resultado: credencial restrita validada e instalada; runtime da aplicação
permaneceu bloqueado.

- Cloudflare for SaaS foi ativado para a zona `blindou.com`, mantendo o limite
  operacional da aplicação em 90 hostnames para reservar margem dentro da
  franquia inicial.
- Foi criado um API token limitado à zona e à permissão
  `SSL and Certificates: Edit`. A primeira credencial apareceu na árvore de
  acessibilidade do navegador durante a criação e foi revogada imediatamente,
  antes de ser usada. Uma credencial substituta foi criada e transferida sem
  exibir seu valor.
- O controlador passou a receber a credencial somente por `stdin`, validar
  atividade e acesso à coleção de custom hostnames e usar configuração do
  `curl` por entrada padrão, mantendo o segredo fora dos argumentos de processo.
- A primeira verificação da credencial substituta confirmou que o token estava
  ativo, mas recusou o acesso por uso indevido do ID da conta como ID de zona.
  O controlador foi corrigido para a zona exata `blindou.com`, reinstalado e a
  validação passou.
- A credencial foi gravada fora do Kubernetes em diretório `root-only`, com
  arquivo `root:root 0600`. Seu rollback exige autenticação humana e só é aceito
  enquanto não existir release corrente.
- Nenhum custom hostname, Secret da aplicação, migration ou release foi criado.
  `blindou-production` continuou `blocked`; o Tunnel isolado e o `apiwpp`
  permaneceram saudáveis.
- O painel confirmou a lista vazia de custom hostnames e informou que a origem
  de fallback ainda não está ativa. Ela só será configurada depois que a origem
  da API estiver publicada e validada em fase autorizada.

## 2026-08-20 - Correção do estado da origem de fallback SaaS

Resultado: registro anterior corrigido por nova evidência visual completa;
nenhuma configuração externa foi alterada.

- O primeiro snapshot do painel ainda não havia carregado o formulário e o
  estado da origem de fallback, levando à conclusão prematura registrada na
  seção anterior.
- Um novo snapshot completo exibiu `domains.blindou.com` como origem de
  fallback com status `Ativo` e manteve a lista com zero custom hostnames.
- O runtime da aplicação, migrations, Secrets e release continuaram ausentes;
  somente o canon, o plano e o índice foram corrigidos.

## 2026-08-20 - Contrato privado de imagens e receptor externo

Resultado: suporte GHCR somente leitura preparado no repositório; nenhuma
credencial, imagem, Secret Kubernetes, migration ou release foi criada.

- O usuário aprovou GHCR privado e acesso do servidor limitado a download. O
  controlador preparado recebe PAT classic somente por `stdin`, valida o ator
  `GleisonSette` e exige exatamente `read:packages`.
- O token ficará no cofre root-only fora do Kubernetes enquanto o runtime
  permanecer bloqueado. `blindou-ghcr-pull` só será materializado durante uma
  release autorizada, e o verificador exige sua referência exclusiva pela
  `ServiceAccount` `blindou-runtime`.
- O local de compilação não foi alterado: GHCR é o registro. Usar GitHub Actions
  para compilar conflita com a regra atual de Rust somente no servidor isolado e
  aguarda decisão explícita.
- O usuário definiu `gleisonsette@gmail.com` como receptor externo. D005 deixou
  de ser escolha pendente, mas provedor autenticado, credencial e teste de
  entrega ainda bloqueiam a primeira release operacional.
- `blindou.com` foi removido do Pages e `app.blindou.com` foi associado; o
  primeiro deployment público continua pendente.

## 2026-08-20 - Autorização do build efêmero e pipeline GHCR

Resultado: pipeline preparado e commitado somente no workspace Blindou; nenhum
`push`, workflow, pacote ou deploy foi executado.

- O usuário autorizou runner efêmero hospedado pelo GitHub exclusivamente para
  build, testes e publicação das imagens privadas. D015 registra que o servidor
  físico permanece consumidor somente leitura do GHCR.
- O Blindou preparou e validou o workflow manual, toolchain, Dockerfiles,
  verificadores e documentação no commit
  `08c35204f4f4d67df8e8065a516efb414d1166d2`.
- A consulta viva ao host ainda não apresentou estado de credencial GHCR; o
  provisionamento humano do PAT `read:packages` e a atualização correspondente
  do controlador permanecem inconclusos.
- O projeto Cloudflare Pages continua ligado à `main` com implantações
  automáticas. Antes de qualquer `push`, produção e previews precisam ser
  desativados e confirmados para preservar a ordem imagens/API Ready antes do
  painel.

## 2026-08-21 - Pages automático mantido por decisão do usuário

Resultado: a recomendação operacional anterior de pausar o Pages foi
substituída; nenhuma configuração Cloudflare foi alterada neste registro.

- O usuário autorizou o `push` do Blindou e decidiu manter automática a
  integração da `main` com o Pages.
- A indisponibilidade temporária do painel enquanto a API compatível ainda não
  estiver Ready foi aceita. O build deve ser acompanhado.
- O deployment estático não libera o namespace `blindou-production`, migrations
  ou release da API; esses efeitos continuam separados.

## 2026-08-21 - Primeiro push, Pages e gate remoto do Blindou

Resultado: painel publicado; pipeline de imagens bloqueado antes da publicação;
nenhuma mudança foi aplicada ao host neste evento.

- A `main` Blindou foi enviada ao GitHub no SHA
  `83e7f387f3fd5477d5882d292532fb2151d68d14`.
- O Cloudflare Pages concluiu o deployment
  `e9ed9cde-328c-40f8-9ef1-60c162fb65e2` em 1m10s. Raiz e `/relatorios`
  responderam HTTP 200 com os headers de segurança esperados; a API permaneceu
  ausente.
- O workflow `32442604845` executou duas tentativas em runners novos. Ambas
  passaram autorização, checkout, toolchain, fmt/check/Clippy e falharam quando
  `rust-lld` recebeu sinal 7 (`Bus error`) ao ligar testes grandes diferentes.
- O job de build/scan/publicação de imagens ficou `skipped`. Nenhum digest foi
  produzido e nenhum deploy, migration ou Secret de runtime foi autorizado.

## 2026-08-21 - Persistência da contenção, GHCR e candidata assinada

Resultado: cadeia de pull e candidata assinada preparadas; runtime permaneceu
bloqueado e o `apiwpp` continuou saudável.

- Um reboot revelou que o `systemd-networkd` reativava IPv6 em `enp2s0` depois
  da aplicação inicial do sysctl. O `blindou-hostctl` passou a reaplicar a
  contenção de forma idempotente, e o unit
  `blindou-temporary-containment.service` foi instalado depois de
  `network-online`, habilitado e validado.
- A transferência do bootstrap foi reduzida a um único archive/SCP para evitar
  o rate limit observado no SSH. A extração Windows/Linux exigiu correção
  explícita do modo executável dos dois scripts. As mudanças ficaram nos
  commits locais `89c474d`, `895c850` e `40de4d6`; não houve push deste
  repositório.
- O usuário autorizou uma exceção pontual e consciente a D011 para usar
  `KEY_SERVIDOR` somente nesses dois bootstraps. A senha passou apenas por
  `stdin`, não foi exibida nem persistida, e a exceção expirou após a instalação.
- O `blindou-hostctl` instalado ficou com SHA-256
  `b51278e6b490a87483156b66968e381593b23a9b5b48a784756549f151e284be` e
  o `blindou-deployctl` com
  `2f433a869db8ea4eac367f874e2bf56f752895a3a78c3310cc9d9f67c2de5dc6`.
- O PAT classic foi criado com vencimento em 2026-11-19 e exatamente
  `read:packages`. O valor foi transferido por `stdin`, removido da área de
  transferência e guardado root-only fora do Kubernetes. O controlador
  confirmou identidade, atividade e escopo; o pull Secret não foi criado.
- O workflow Blindou `32534879401` passou gates Rust/PostgreSQL, scans e
  publicação para o SHA
  `1265c3be1e808d522887f38ff47e9a110533677a`. Backend e redirector ficaram no
  GHCR somente por digest.
- O bundle SHA-256
  `d22fb791e2fd9c68d95b98493a97a03c724cb83f66bc536a2417dfa1889035fb`
  foi assinado fora do servidor, validado contra o contrato fechado e
  armazenado no cache do controlador. `current_release` permaneceu ausente.
- A verificação final aprovou host/UFW/IPv6/DNS/Internet/ONT/K3s, fundação,
  conector EDGE, Cloudflare for SaaS, GHCR, dados, backup e `apiwpp`. Não havia
  unit systemd falha; `blindou-production` permaneceu com gate `blocked`, zero
  objetos operacionais e nenhuma migration, Secret Kubernetes ou aplicação.
- Continuam pendentes antes do primeiro deploy: scan operacional das imagens
  terceiras fixadas, Secrets de runtime, alertas externos, gates `passed` e
  autorização específica de migration/deploy.

## 2026-08-21 - Preparação da prova integral de pull GHCR

Resultado: controlador e testes preparados no repositório; instalação viva
pendente de bootstrap humano.

- O controlador ganhou uma operação fechada que aceita somente uma release já
  validada no cache e descobre nela backend e redirector pelos repositórios
  privados fixos do Blindou.
- O verificador dedicado recebe o PAT por `stdin`, desabilita proxy herdado,
  limita tempo e bytes, remove autorização em redirect para outro host HTTPS e
  valida manifesto, config e todas as camadas por SHA-256.
- Os bytes baixados usam workspace temporário autoclean; somente um recibo
  root-only sem segredo permanece e alimenta status/métrica.
- Cinco testes determinísticos e o verificador de artefatos passaram sem rede e
  sem usar credencial. Nenhum Secret Kubernetes, gate, migration ou workload
  foi alterado nesta preparação.

## 2026-08-21 - Extensão da prova para NATS e cloudflared privados

Resultado: o contrato local do controlador passou a exigir as quatro imagens
privadas da candidata; instalação viva e pull continuam pendentes.

- O Blindou assumiu, por decisão explícita, builds endurecidos de NATS e
  `cloudflared` no GHCR privado; Redis continua oficial por digest.
- O controlador agora descobre exclusivamente backend, redirector, NATS e
  `cloudflared` no bundle validado e recusa candidata que não contenha as quatro
  referências privadas distintas.
- O verificador baixa manifesto, config e camadas de cada componente, preserva
  os limites, valida todos os digests e produz recibo fechado de 24 linhas.
- Seis testes determinísticos, compilação Python, sintaxe Bash e o verificador
  de artefatos passaram localmente. Nenhum bootstrap, Secret, gate, migration
  ou workload foi executado.

## 2026-08-22 - Transporte fechado da nova candidata para a prova GHCR

Resultado: orquestração preparada no repositório; host ainda não alterado.

- A candidata Blindou `0ba8384` passou na publicação e no scan fechado
  `32550929031`, contendo backend, redirector, NATS e `cloudflared` privados e
  Redis oficial.
- O orquestrador da prova passou a exigir o diretório do bundle e transportar,
  no mesmo archive do controlador, somente `release.manifest`,
  `release.manifest.sig` e `rendered.tar.gz`.
- A ordem foi fechada em bootstrap humano, `validate-release` no cache e somente
  depois `verify-ghcr-candidate-pull` para as quatro imagens.
- Nenhum Secret Kubernetes, gate, migration, workload ou release corrente foi
  criado nesta preparação.

## 2026-08-22 - Bootstrap automatizado fechado e prova integral da candidata

Resultado: controlador atualizado e candidata comprovada no host; runtime
permaneceu bloqueado e o `apiwpp` saudável.

- Após o protocolo de conflito, D018 autorizou o helper versionado a carregar
  `KEY_SERVIDOR` do `.env` ignorado somente em memória e enviá-la por `stdin`
  aos bootstraps fechados. Host, staging e instaladores são fixos; `sudo`
  genérico e rollback destrutivo continuam proibidos.
- O `blindou-deployctl` instalado coincidiu com a fonte local no SHA-256
  `e6e06d77aa83558e1911424e3c7b7389d628281fa685fd1f4ff37f83bdc16d70`.
- O bundle assinado `0ba83846102a480ae79d44fce971de13b91f9d04` passou em
  `validate-release` e foi armazenado no cache root-only.
- A prova GHCR baixou e verificou quatro imagens privadas, 24 blobs e
  111.683.519 bytes. O recibo sem segredo ficou associado ao mesmo release ID.
- A verificação independente aprovou fundação, conector EDGE, credencial GHCR,
  dados, backup, UFW/IPv6/DNS/Internet/ONT/K3s e `apiwpp`; zero unit systemd
  estava falha.
- `current_release` permaneceu ausente; `blindou-production` continuou
  `blocked` e com zero objetos operacionais. Nenhum Secret Kubernetes,
  migration ou workload foi criado.

## 2026-08-22 - Preparação fechada da primeira release

Resultado: controlador, orquestrador e runbooks preparados no repositório;
nenhuma mudança viva desta etapa foi aplicada ao host.

- Corrigido o gate que exigia indevidamente o sender WhatsApp enquanto o 2FA
  está desabilitado; a ausência do token agora é uma invariante verificada.
- Preparado `secrets-only`, que permite ConfigMap e Secrets sem permitir Pods,
  além da geração server-side das chaves internas e TLS do NATS.
- UAZAPI e Resend passam por validação autenticada; o Alertmanager fica em
  loopback, integrado ao Prometheus, e exige alerta sintético confirmado pelo
  usuário antes da liberação.
- A continuidade temporária foi fechada em RPO de 15 minutos, RTO de 4 horas e
  retenção offsite de 30 dias, com checksum conferido na estação administrativa
  antes do recibo.
- A liberação dos namespaces exige o mesmo SHA da release assinada e da prova
  GHCR. A imagem privada do `cloudflared` recebe pull secret somente leitura na
  EDGE, sem montar a credencial no container.
- O bootstrap de `gleisonsette@gmail.com` como `super_admin` recebe a senha por
  entrada protegida e valida o login público sem imprimir tokens.
- Sintaxe Bash e PowerShell, testes do verificador GHCR, verificador de
  artefatos e diff check passaram. Commit, bootstrap vivo, Secrets, gates,
  migrations, deploy e usuário continuam pendentes nesta entrada.

## 2026-08-22 - Correção do contrato da candidata com 2FA desabilitado

Resultado: a primeira tentativa de validar a nova candidata falhou fechada e
não iniciou workload; o contrato do servidor foi alinhado à decisão D027.

- O bundle assinado continha os 18 workers aprovados e omitia somente
  `auth-whatsapp-delivery`, como exigido enquanto não existe sender UAZAPI de
  segurança e `AUTH_REQUIRE_2FA=false`.
- O verificador do servidor ainda continha a contagem histórica de 19 workers;
  ele recusou o archive antes de criar release, migration, Secret ou workload.
- A contagem passou a ter uma única constante normativa de 18 workers, usada
  tanto na estrutura do archive quanto nos Deployments extraídos.
- Assinatura, SHA-256, escopo de recursos, imagens por digest e demais gates
  permanecem inalterados.

## 2026-08-22 - Ordem corrigida para revisão da UI sem provedores

Resultado: fontes do controlador e do orquestrador foram alinhadas à D019;
nenhuma mudança viva desta etapa foi aplicada ao host.

- O usuário esclareceu que UAZAPI, Resend e Pagar.me só serão configurados
  depois que ele entrar no painel e aprovar a interface.
- A janela de credenciais anterior foi encerrada sem gravar segredo, criar
  Secret Kubernetes, executar migration ou iniciar workload. A candidata de 18
  workers não foi implantada e permanece apenas como prova histórica do GHCR.
- Foi preparado um modo de revisão fail-closed com 16 workers, 2FA desabilitado
  e ausência verificável das credenciais dos três provedores.
- O fluxo da primeira release passa a solicitar somente a senha protegida do
  superadmin, mantendo assinatura, prova GHCR, backup, cópia offsite,
  contenção, gates e smoke público obrigatórios.
- Sintaxe, verificadores, commits, push, nova candidata e deploy vivo ainda
  precisavam ser concluídos no momento deste registro.

## 2026-08-22 - Correção do bootstrap do cofre no primeiro runtime

Resultado: corrigida no repositório a ordem de criação do cofre interno da
revisão de UI; a tentativa viva falhou fechada antes de Secrets, migrations ou
workloads.

- A candidata `d8bc0969a6820172559773503813e4ce67490906` passou nos gates e na
  prova integral de download das quatro imagens privadas.
- No primeiro host vazio, `write_ui_review_runtime_config` tentou criar
  `production.env.tmp` antes da existência de `/etc/blindou/runtime`.
- `provision-ui-review-runtime` passa a criar o diretório `root:root` `0700`
  antes da configuração; o verificador de artefatos protege também a ordem das
  duas operações.
- UAZAPI, Resend e Pagar.me continuam ausentes. A release permaneceu sem
  aplicação durante a falha observada.

## 2026-08-22 - Retry classificado para concorrência do coletor

Resultado: o orquestrador da primeira release passou a tolerar somente a
contenção transitória do lock compartilhado com o coletor de métricas.

- Depois do backup offsite verificado, o coletor periódico adquiriu o lock
  entre duas operações e o controlador recusou a continuação com `exit 2`.
- O retry é limitado a 12 tentativas de cinco segundos e aceita somente esse
  código; falha de rede, contrato, segurança, migration ou workload continua
  interrompendo imediatamente.
- Ativação dos gates e `apply` são invocações separadas, evitando repetir um
  efeito concluído como parte de um comando composto.
- A segunda tentativa também permaneceu sem release aplicada e sem credenciais
  UAZAPI, Resend ou Pagar.me.

## 2026-08-22 - Errexit restaurado no corpo da release

Resultado: corrigida na fonte a semântica de falha do primeiro `apply`; a
contenção viva da candidata recusada ainda precisava ser confirmada ao registrar
esta entrada.

- O Kubernetes recusou o StatefulSet Redis porque um item de `args` chegou como
  número YAML, não string.
- `apply_cached_release` era chamado diretamente por `if !`, contexto em que o
  Bash suprime `errexit` também dentro da função e continuava pelos timeouts.
- O corpo passa a rodar em subshell com `set -Eeuo pipefail`; o pai captura o
  status fora de uma condição e executa o rollback de primeira release na
  primeira falha.
- A correção do manifesto pertence ao repositório Blindou e exige novo SHA;
  editar ou reassinar o bundle recusado continua proibido.

## 2026-08-22 - Contenção fechada de apply legado preso

Resultado: preparada no repositório uma operação emergencial de escopo único;
a execução viva ainda precisava ser comprovada ao registrar esta entrada.

- A sessão SSH foi interrompida, mas o `sudo` remoto manteve o controlador
  antigo órfão e preso em timeouts posteriores à falha conhecida.
- O helper independente só encerra um único holder root cujo `cmdline` seja o
  `apply` exato do SHA informado e cuja autoridade atual seja ausente ou o mesmo
  SHA.
- Depois do término, ele remove somente workloads e Services do Blindou,
  restaura os gates temporários, remove o recibo da candidata e exige zero
  objeto operacional na aplicação.
- O sudoers admite apenas a interface fechada com confirmação literal; `sudo`
  genérico continua proibido.
- A primeira chamada viva foi recusada sem alterar estado porque `fuser` não
  entregou os PIDs pelo canal esperado; a seleção passou a combinar `pgrep` com
  cmdline exata e prova independente de lock ocupado.
- A segunda chamada encerrou a árvore exata, removeu workloads e Services,
  restaurou `secrets-only`/`connector-only` e manteve `current_release` ausente.
  Depois da reconciliação, o conector ficou `ready`, o backup offsite presente,
  host e `apiwpp` passaram seus gates e a API pública permaneceu em `502` sem
  backend parcial.

## 2026-08-22 - Download offsite consolidado em uma conexão

Resultado: o orquestrador passou a transferir cada backup em uma única sessão
SCP e validar o conjunto fechado localmente.

- Duas execuções baixaram envelope e manifesto, mas o terceiro handshake rápido
  expirou ao buscar o certificado público; após intervalo, o mesmo arquivo foi
  transferido e o checksum integral passou.
- O novo fluxo copia o diretório cujo ID veio do status autenticado e exige
  exatamente três arquivos regulares, sem link simbólico nem conteúdo extra.
- O backup `blindou-20260822T222900Z` foi confirmado offsite antes da nova
  candidata; nenhuma credencial de provedor participou do fluxo.

## 2026-08-22 - Timeout fail-closed do primeiro Job de migration

Resultado: a candidata chegou pela primeira vez ao Job de migration, não
concluiu em 600 segundos e foi integralmente contida; o controlador foi
corrigido no repositório para distinguir falha terminal de espera real.

- O workflow `32602526360` concluiu testes Rust/PostgreSQL e publicação das
  imagens da candidata `794d92235ea5ad14a001bac103f23435bb32fcf0` em 25
  minutos e 38 segundos.
- A assinatura local, a prova integral das quatro imagens e o backup offsite
  `blindou-20260822T225840Z` passaram antes da ativação dos gates.
- NATS e Redis ficaram Ready. O Job `blindou-migrate-794d92235ea5` não recebeu
  condição `Complete` em 600 segundos; o controlador removeu os workloads e
  Services, restaurou `secrets-only`/`connector-only`, manteve
  `current_release` ausente e o conector voltou a Ready.
- A espera anterior observava somente `Complete`, portanto consumia o timeout
  mesmo quando o Kubernetes já pudesse ter marcado `Failed` e removia o Job
  antes da coleta da causa.
- A fonte passa a observar `Complete` e `Failed` a cada dois segundos, mantém o
  limite de 600 segundos e emite antes do rollback somente as últimas linhas do
  container de migration após redaction explícita de URL PostgreSQL, senha,
  token, segredo e chave privada. O verificador inclui exercício dinâmico dessa
  sanitização.
- UAZAPI, Resend e Pagar.me permaneceram ausentes durante toda a tentativa.

## 2026-08-22 - Causa da migration e fronteira de extensão administrativa

Resultado: o diagnóstico fail-fast reduziu a repetição de dez minutos para
segundos e provou que a falha era uma extensão administrativa no baseline da
aplicação; a correção foi preparada sem elevar a role de migration.

- O controlador corrigido foi instalado e a candidata `794d922` repetida com
  as mesmas imagens já comprovadas.
- O Job registrou início de `0001` e falhou ao criar `pg_stat_statements` porque
  `blindou_migration_login` não possui superuser. O rollback removeu todos os
  workloads e restaurou os dois gates temporários.
- Conceder superuser à identidade foi recusado pela arquitetura. A fundação
  PostgreSQL passa a criar idempotentemente a extensão no database `blindou`,
  schema `public`, com owner `postgres`, e `verify-data` exige essa autoridade.
- Como `0001` nunca foi concluída nem registrada pelo SQLx e não há dados de
  cliente, o baseline Blindou pode retirar a criação e o comentário dessa
  extensão antes da primeira release. `citext` e `pgcrypto` continuam sob a
  migration.
- A mudança do schema embutido exige novo commit, suíte externa, imagens,
  assinatura e bundle; a candidata `794d922` não será alterada ou promovida.

## 2026-08-22 - Pré-requisito PostgreSQL instalado sem elevar migration

Resultado: a fronteira administrativa corrigida foi aplicada ao host e
verificada; o database está pronto para a nova candidata, ainda sem migration
aplicada.

- O commit de plataforma `5aaae67` foi publicado e o bootstrap fechado instalou
  o controlador com SHA-256
  `2851f28073b22840c3d52c4ea602a3b82498522bb94472744053f87f8a2306d8`.
- Antes da mudança, o status confirmou `migration_history_count=0` e
  `pg_stat_statements=absent`, provando que o baseline antigo não havia sido
  aceito.
- `provision-data blindou-data-foundation` criou a extensão no database
  `blindou`; `verify-data` confirmou quatro logins não administrativos, TLS,
  SCRAM, schema `public` e owner `postgres`.
- Depois da mudança, o status confirmou `migration_history_count=0`,
  `pg_stat_statements=present`, `current_release=absent`, aplicação em
  `secrets-only` e conector em `connector-only` Ready.
- O `apiwpp` permaneceu com uma réplica Ready, 18 migrations, API, métricas e
  gateway privado saudáveis. Nenhum provedor externo do Blindou foi configurado.
- O SHA Blindou `ccc4edd6a85e87b4c15100afbc5ec386bf94aac5` foi publicado e o
  workflow `32605412093` iniciado para gerar uma candidata integral nova.

## 2026-08-22 - `0001` aplicada e ACL de `0002` contida por ownership

Resultado: a candidata corrigiu a criação da extensão e concluiu `0001`, mas a
ACL global de `0002` cruzou a fronteira de ownership; a falha foi diagnosticada
e contida sem elevar a identidade de migration ou publicar release parcial.

- O workflow `32605412093` aprovou o SHA
  `ccc4edd6a85e87b4c15100afbc5ec386bf94aac5` em 43 minutos e 23 segundos,
  incluindo testes Rust/PostgreSQL, scans e quatro imagens privadas.
- A prova integral no host confirmou quatro imagens, 25 blobs e 113.292.669
  bytes. O backup `blindou-20260823T002003Z` foi criptografado, baixado em
  conexão única, comparado ao manifesto e confirmado offsite.
- NATS e Redis ficaram Ready. `0001` foi concluída e registrada; `0002` tentou
  executar `REVOKE` sobre `pg_stat_statements_reset`, pertencente a `postgres`,
  e o PostgreSQL recusou `blindou_migration_login` como esperado.
- O controlador publicou o diagnóstico sanitizado, removeu os workloads e
  restaurou `secrets-only`/`connector-only`. O status autenticado confirmou
  `migration_history_count=1`, `pg_stat_statements=present`,
  `current_release=absent` e conector Ready.
- A análise também encontrou `COMMENT ON ROLE` incompatível com a ausência de
  `CREATEROLE`. O SHA Blindou `6365832bf1e271f4bfb49441b273a346ba0ba5c8`
  limita ACL aos objetos de `CURRENT_USER`, não comenta roles do cluster e
  adiciona ao workflow um ensaio do binário real com identidade não
  administrativa e extensão de owner distinto.
- O novo workflow `32608484692` foi iniciado. UAZAPI, Resend e Pagar.me
  permaneceram ausentes durante toda a tentativa.

## 2026-08-23 - Oito migrations preservadas e release contida por ausência de R2

Resultado: o schema inicial foi concluído, mas nenhum backend parcial ficou
publicado; o próximo bloqueio foi isolado no armazenamento obrigatório do
worker de miniaturas.

- O SHA `48bc9f0fb14db6dedda34598ced3f702a96749bf` passou no workflow
  `32612301391`, na assinatura e na prova integral de quatro imagens privadas,
  25 blobs e 113.293.810 bytes.
- O backup `blindou-20260823T025908Z` foi criptografado, transferido, conferido
  e confirmado offsite antes do `apply`.
- As migrations `0001` a `0008` foram registradas. NATS, Redis e os demais
  workloads avançaram, mas `worker-report-thumbnail` recusou a configuração
  porque `R2_PREVIEW_IMAGES_ENABLED` estava desabilitado.
- O controlador removeu workloads e Services, restaurou
  `secrets-only`/`connector-only`, manteve o Tunnel Ready e deixou
  `current_release=absent`. O banco com oito migrations foi preservado.
- UAZAPI, Resend e Pagar.me permaneceram ausentes; desabilitar o worker foi
  recusado porque a função faz parte do núcleo já aprovado.

## 2026-08-23 - Fronteira R2 preparada para o runtime Blindou

Resultado: recursos Cloudflare foram criados e o caminho de provisionamento
fechado foi preparado no repositório; a credencial ainda não foi entregue ao
host no momento deste registro.

- Foi criado o bucket exclusivo `blindou-media-prod` e ativado o domínio
  `media.blindou.com`, com TLS mínimo 1.2; o URL público `r2.dev` permaneceu
  desabilitado.
- CORS permite somente `GET` e `HEAD` originados de
  `https://app.blindou.com`. Uma credencial Account R2 de leitura/gravação de
  objetos foi limitada somente ao bucket Blindou, sem permissão administrativa.
- O controlador preparado fixa conta, bucket e domínio, guarda as chaves em
  cofre root-only e exige um ciclo real de escrita, leitura pública, comparação
  SHA-256 e exclusão antes do gate de release.
- O orquestrador local solicita os dois valores em campos protegidos e os envia
  somente por `stdin`; não lê nem exporta o segredo da sessão autenticada do
  Chrome. Instalação, prova viva e repetição do rollout ainda estavam pendentes.

## 2026-08-23 - Credencial R2 instalada e prova viva aprovada

Resultado: cofre e runtime técnico concluídos; a release da aplicação continua
ausente e será reaplicada em etapa própria.

- O operador copiou o ID e a chave secreta diretamente da sessão autenticada
  para os campos protegidos; nenhum valor foi lido, exibido, salvo ou indexado
  pelo Codex.
- O controlador guardou a credencial restrita no cofre root-only e executou no
  bucket `blindou-media-prod` um ciclo assinado de escrita, leitura pública com
  comparação SHA-256 e exclusão do sentinela.
- Duas tentativas de republicação encontraram o lock transitório do coletor de
  métricas; o retry classificado aguardou cinco segundos e concluiu sem repetir
  o provisionamento da credencial.
- `provision-ui-review-runtime` republicou o material técnico com R2 e manteve
  UAZAPI, Resend, Pagar.me e alertas externos ausentes.
- A verificação autenticada confirmou `r2_runtime_credential_state` em
  `secure_local_store`, `r2_runtime_live_probe` em `passed`, conector Cloudflare
  `ready`, oito migrations e `current_release=absent`.

## 2026-08-23 - Hotfix RLS implantado e atualização segura concluída

Resultado: a release `8e17210e34767935158ba5c8b863b48724297a93` está ativa e
saudável; a confirmação visual do bootstrap do superadmin permanece com o
operador.

- O workflow `32645928340` passou Check, Clippy, suíte completa, PostgreSQL de
  menor privilégio, bootstrap real `NOBYPASSRLS`, scans e publicação das quatro
  imagens por digest.
- A prova fechada confirmou quatro imagens, 25 blobs e 113.212.411 bytes sem
  iniciar workload. O backup `blindou-20260823T152218Z` foi comparado ao
  manifesto e confirmado offsite antes do rollout.
- A primeira tentativa de liberar a candidata revelou que o controlador exigia
  EDGE `connector-only` também durante atualização, embora a release corrente
  saudável mantenha a EDGE em `passed`. O controlador passou a distinguir os
  estados: primeira instalação exige ausência de `current_release`; atualização
  exige ponteiro regular `root:root 0600` com SHA válido e EDGE verificada.
- O rollout concluiu backend, redirector, NATS, Redis, 16 workers e
  `cloudflared`; `current_release` aponta para `8e17210`, as oito migrations
  permanecem registradas e API/painel responderam pela borda pública.
- UAZAPI, Resend e Pagar.me permaneceram ausentes. O helper protegido adquiriu e
  liberou o lock do bootstrap; seu resultado final ainda aguarda confirmação
  visual do operador na janela local.

## 2026-08-23 - Superadmin criado e login público validado

Resultado: o primeiro acesso real do Blindou está pronto para a revisão da UI.

- A janela protegida concluiu o bootstrap de `gleisonsette@gmail.com` como
  `super_admin`, com tenant, usuário, ownership e membership criados na mesma
  transação sob RLS.
- A senha entrou somente pelo prompt oculto e não foi salva em arquivo, log ou
  output; o registro técnico expôs apenas IDs operacionais e prefixo reduzido
  do e-mail.
- O controlador validou o login pela API pública sem exibir tokens e orientou o
  acesso por `https://app.blindou.com`.
- UAZAPI, Resend e Pagar.me continuam ausentes. A próxima ação é a validação da
  interface pelo usuário; a ativação dos provedores permanece separada.

## 2026-08-24 - Fluxo Pagar.me-first preparado após aprovação da UI

Resultado: o repositório passou a descrever provisionamento e ativação segura
do Pagar.me; nenhum controlador, segredo, plano ou workload foi alterado no
host por esta etapa.

- A UI foi aprovada e a D020 fixou a ordem Pagar.me, domínio personalizado,
  marketplaces e UAZAPI/Resend.
- Os sete planos live serão mensais `prepaid`, com descritor `BLINDOU`, preços
  e limites idênticos ao catálogo versionado no repositório Blindou.
- A secret key chega por prompt protegido, é validada contra a API live e fica
  com o segredo aleatório do webhook em cofre dedicado, fora do Kubernetes.
- A ativação exige uma release assinada corrente com o marcador explícito de
  compatibilidade no backend e nos 16 workers; falha de prontidão restaura
  ConfigMap, Secret e workloads anteriores.
- Os verificadores de artefatos e de bundle rejeitam ausência do marcador,
  exposição por argumento e contratos sudo mais amplos que os comandos
  fechados. UAZAPI e Resend permanecem desligados.

## 2026-08-24 - Convenção atual de chaves e executor dos planos Pagar.me

Resultado: a regra de prefixos foi alinhada à API V5 e o executor local dos
sete planos foi preparado; neste registro ainda não houve chamada de criação,
mudança no host, Secret Kubernetes, migration ou ativação do runtime.

- Produção passou a aceitar `sk_*` e recusar explicitamente `sk_test_*`; a
  secret key continua sujeita à prova autenticada antes de qualquer efeito.
- O executor usa entrada protegida, catálogo fechado equivalente à `0005`,
  confirmação humana imediatamente antes dos `POST`, metadata por código e
  reconciliação sem retry cego.
- O recibo operacional fica fora dos repositórios e contém somente IDs
  `plan_*`; a vinculação ao catálogo local continua dependendo de migration
  separadamente autorizada.

## 2026-08-24 - Credencial, webhook e sete planos Pagar.me provisionados

Resultado: a fronteira externa Pagar.me foi cadastrada e verificada, enquanto o
runtime permaneceu deliberadamente inativo e sem segredo no Kubernetes.

- A secret key live foi autenticada contra a API V5 e guardada somente em
  `/etc/blindou/pagarme`, com owner `root`, modo `0600` e recibo de validação.
- A primeira URL de webhook deixou de ser confiável após exposição no chat. O
  segredo foi rotacionado no cofre, a URL substituta foi cadastrada no painel
  para assinatura, cobrança, fatura e pedido, e a área de transferência foi
  limpa sem registrar o valor.
- O Iniciante criado durante a codificação antiga foi corrigido por atualização
  autenticada e fetch-back. Operador Júnior, Operador Pleno, Operador Sênior,
  Elite I, Elite II e Elite III foram criados com idempotência própria.
- A verificação independente confirmou sete planos live mensais `prepaid`, uma
  parcela, sem trial, não físicos e com descritor `BLINDOU`. O recibo root-only
  e a cópia local não secreta contêm somente os IDs externos.
- `pagarme_credential_state=secure_local_store`,
  `pagarme_plans_state=seven_live_verified` e
  `pagarme_runtime_state=inactive` foram confirmados após a operação.
- Public key do frontend, migration dos IDs, candidata assinada, deploy e
  ativação do runtime permanecem operações futuras com autorização própria.

## 2026-08-25 - Transporte completo dos bootstraps Blindou

Resultado: corrigido no repositório; a repetição da prova viva permanece
registrada separadamente depois do aceite no host.

- A primeira tentativa de provar a candidata Pagar.me-first parou antes de
  instalar o controlador porque o orquestrador GHCR não transportava o novo
  provisionador fechado de planos exigido pelo bootstrap.
- Os seis orquestradores que reinstalam o `blindou-deployctl` passaram a incluir
  controlador emergencial, verificador GHCR e provisionador Pagar.me.
- O verificador offline agora compara todos eles contra o conjunto obrigatório,
  evitando que a evolução de um módulo quebre silenciosamente outro caminho de
  bootstrap.
- Nenhum workload, migration, Secret ou gate de produção foi alterado pela
  tentativa recusada.

## 2026-08-25 - Primeira ativação Pagar.me recusada pela checagem interna

Resultado: a release e a migration foram aplicadas; a ativação não recebeu
recibo de sucesso e preservou o journal para recuperação na próxima execução.

- A release `ab15a31b8b0538b772763cb0b5a52d6ef3c7c463` passou na prova integral
  das quatro imagens, aplicou a migration `0009` e deixou backend, redirector,
  NATS, Redis, 16 workers e `cloudflared` Ready.
- O backup `blindou-20260825T092915Z` foi criptografado, baixado e confirmado
  offsite antes da migration.
- A credencial Pagar.me live foi revalidada, mas a ativação tentou executar
  `curl` dentro da imagem mínima do backend. A ferramenta não existe por
  endurecimento; a mesma checagem impediu a conclusão formal do rollback.
- O controlador preservou o journal root-only, não criou recibo de ativação e
  continuou reportando `pagarme_runtime_state=inactive`. App e API públicos
  permaneceram em HTTP 200.
- A correção passa a usar o `rollout status`, que já depende das probes HTTP
  `/ready` declaradas na release assinada, e o gate offline recusa dependência
  de ferramenta executada dentro do Pod.

## 2026-08-25 - Ativação Pagar.me concluída após recuperação do journal

Resultado: a repetição com o controlador corrigido recuperou o estado
interrompido, ativou o par Pagar.me na release corrente e emitiu recibo de
sucesso sem reexecutar migration ou deploy.

- O bootstrap instalou a correção `ab4a936` do controlador fechado.
- A operação recuperou primeiro o journal root-only preservado pela tentativa
  anterior e só então iniciou uma nova ativação.
- O backend e os 16 workers concluíram `rollout status`; suas probes HTTP
  `/ready` passaram pelo kubelet sem exigir ferramenta dentro dos Pods.
- O estado final confirmou
  `current_release=ab15a31b8b0538b772763cb0b5a52d6ef3c7c463`,
  `migration_history_count=9`, `pagarme_credential_state=secure_local_store`,
  `pagarme_plans_state=seven_live_verified` e
  `pagarme_runtime_state=active`.
- Aplicação e API públicas permaneceram em HTTP 200; UAZAPI, Resend e o receptor
  externo de alertas continuam adiados conforme D020.
- A validação autenticada posterior confirmou sete planos disponíveis e abriu o
  formulário do checkout transparente. Nenhum cartão, assinatura, pedido ou
  cobrança real foi criado.

## 2026-08-26 - Decisão do slot alternável APIWPP/SaferWPP

Resultado: documentação canônica concluída; runtime inalterado.

- O usuário decidiu manter o Blindou sempre ativo e intacto.
- A capacidade residual será compartilhada em exclusão mútua: APIWPP ativo com
  SaferWPP suspenso, ou APIWPP suspenso com SaferWPP ativo.
- A suspensão futura do APIWPP preservará namespace, objetos, Service, PVC,
  banco, papéis, migrations, ConfigMaps, Secrets, imagens, releases e backups;
  o gateway privado continuará ativo.
- A retomada foi dividida em auditoria viva de capacidade, contratos de
  suspensão/retomada, plataforma declarativa, `saferwpp-deployctl`, janela de
  suspensão e somente então deploy SaferWPP.
- O canon, o `AGENTS.md`, o runbook de contenção e a recuperação RAG foram
  atualizados; nenhum recurso ou arquivo do repositório da aplicação Blindou
  foi alterado.
- Nenhum acesso ao servidor físico, suspensão, instalação, migration, backup ou
  deploy foi executado.

## 2026-08-26 - Auditoria viva de capacidade do slot SaferWPP

Resultado: auditoria somente leitura concluída; capacidade conjunta reprovada
antes de qualquer mutação.

- A identidade SSH e o host foram validados. A coleta usou `/proc`, Node
  Exporter, PostgreSQL Exporter e operações `status` fechadas; não usou
  `kubectl`, `psql`, kubeconfig, segredo ou comando de alteração.
- O host possuía quatro CPUs, 15,52 GiB de memória, mínimo de 9,62 GiB
  disponíveis em 24 horas, 252,21 GiB livres e 3% de inodes usados.
- CPU média/pico de cinco minutos foram 23,79%/50,72%; `iowait`
  2,64%/19,69%; HDD 10,29%/61,35%. Esses valores permitem continuar o desenho
  de laboratório, mas não comprovam pico de produção nem HA.
- APIWPP permaneceu Ready na release `86bb7f886778`, com 18 migrations, PVC de
  20 GiB, backup local/R2 saudável, cerca de 1,93 GiB de memória e 0,805 CPU na
  amostra de cinco segundos.
- O primeiro status Blindou foi recusado por lock operacional, que não foi
  tocado. Após a operação terminar, release `dc2aa63`, 11 migrations, gates
  `passed`, conector, Pagar.me e backup/offsite estavam saudáveis.
- PostgreSQL possuía teto 50, três conexões reservadas, 41 backends correntes e
  pico de 48 em sete dias. Blindou usava 35 e chegou a 43; APIWPP usava quatro
  e chegou a cinco. PgBouncer do host estava inativo.
- Suspender APIWPP não abre espaço seguro para os dez backends runtime e dois
  slots de migration planejados pelo SaferWPP. O teto 60 do contrato SaferWPP
  diverge dos 50 reais.
- A quota viva de memória do namespace também é inferior aos requests estáveis;
  Keycloak, Control Plane, backup SaferWPP e `saferwpp-deployctl` continuam
  ausentes.
- Nenhum workload, banco, namespace, quota, serviço, controlador, backup,
  segredo ou recurso Blindou/APIWPP foi alterado. D023 registra a decisão de
  topologia PostgreSQL necessária antes da continuação.

## 2026-08-26 - PostgreSQL exclusivo decidido para o SaferWPP

Resultado: D023 resolvida e contratos documentais alinhados; nenhum recurso do
servidor foi alterado.

- O usuário escolheu um segundo cluster/processo PostgreSQL 18 exclusivo do
  SaferWPP no mesmo servidor físico, sem alterar o cluster compartilhado atual,
  o Blindou ou o APIWPP.
- O alvo `saferwpp-lab` usa porta 55432, banco e papéis próprios, teto de 24
  conexões, PgBouncer de dez backends, unidade/slice, dados, TLS, backup e
  exporter exclusivos.
- O envelope limita CPU a um core, `MemoryHigh=1536Mi`, `MemoryMax=2048Mi` e
  pisos de 20 GiB para dados e 20 GiB para backup local. A stanza pgBackRest
  exclusiva usa repositórios local/R2 e restore isolado.
- O próximo gate passou a ser implementar essa fundação declarativamente no
  repositório do servidor, junto da quota e dos orçamentos Keycloak/Control
  Plane, antes de suspensão do APIWPP, instalação de controlador ou deploy.

## 2026-08-26 - Fundação exclusiva do SaferWPP declarada

Resultado: artefatos e contratos implementados e validados offline; servidor
inalterado.

- `platform/saferwpp` passou a declarar o segundo cluster PostgreSQL 18 na
  porta 55432, teto 24, slice de um core/2Gi, HBA TLS/SCRAM, pgBackRest local e
  R2, timers, exporter exclusivo em loopback, métricas e alertas.
- O schema `saferwpp.backup-preflight/v2` exige dois repositórios, WAL contínuo,
  restore-base antes do database e restore pós-migration antes do rollout.
- A quota-alvo de `saferwpp-lab` foi recalibrada para 2 CPU/4Gi de requests,
  7 CPU/8Gi de limits, 12 pods, três PVCs e 24Gi. Keycloak e Control Plane
  receberam namespaces, cotas e limites exclusivos, inicialmente vazios e sem
  PVC.
- Certificados, senhas, DSNs, endpoint e credenciais R2 permanecem fora do Git;
  o verificador offline recusará divergência de porta, conexões, ownership,
  quotas, backup, listener ou material sensível.
- Nenhum acesso ao servidor, cluster PostgreSQL, stanza, bucket, namespace,
  quota, Secret, workload, suspensão, migration ou recurso Blindou/APIWPP foi
  executado.
- O próximo gate é implementar, no repositório APIWPP, o contrato fechado de
  `suspend`, `verify-suspended` e `resume`; a operação viva continua separada e
  depende de autorização própria.

## 2026-08-26 - Plataforma declarativa do slot alternável implementada

Resultado: o contrato compartilhado passou a existir no repositório; servidor
e runtime permaneceram inalterados.

- `platform/secondary-slot` passou a declarar fonte de verdade root-only,
  estados permitidos, membros, lock global, admissão fail-closed e alertas.
- `secondary-slotctl` é o escritor exclusivo do atestado e implementa
  inicialização, início/conclusão de suspensão, reserva, conclusão de ativação,
  aborto seguro e reconciliação baseada no runtime observado.
- O gate de admissão bloqueia workloads em namespace inativo, ausente ou com
  estado desconhecido, incluindo criações diretas de ReplicaSet,
  ReplicationController e Pod.
- Runtime inequívoco pode ser reconciliado sem ficar indefinidamente em estado
  desconhecido. Split-brain, rollout parcial ou membro não Ready permanece
  bloqueado e emite auditoria, métrica e evento operacional persistente.
- A mudança do Blindou durante uma transição é detectada por saúde e fingerprint
  anterior/posterior. O controlador compartilhado não chama controladores de
  aplicação sob o lock, nem aplica, remove, escala, rotula ou anota recurso
  Blindou.
- Bootstrap, sudoers, timer de métricas, alertas Prometheus, testes unitários,
  verificador offline e runbook foram adicionados. A validação offline passou.
- Nenhum artefato foi transportado ou instalado no host; não houve suspensão,
  criação de atestado, aplicação Kubernetes, migration, deploy ou mudança no
  Blindou/APIWPP. O próximo gate é `saferwpp-deployctl`.

## 2026-08-26 - Contrato de restore SaferWPP alinhado entre repositórios

Resultado: schema e validações da plataforma corrigidos offline; servidor e
runtime permaneceram inalterados.

- O repositório SaferWPP já implementa `saferwpp-deployctl`,
  `saferwpp-backupctl` e `saferwpp-secretsctl`, ainda sem transporte ou
  instalação no host.
- O schema `saferwpp.backup-preflight/v2` da plataforma passou a exigir
  `rolesVerified`, `grantsVerified` e `rlsVerified` verdadeiros na prova de
  restore pós-migration; na fase `foundation`, `postMigrationRestore` deve ser
  nulo.
- O contrato autoritativo, o coletor de métricas, o verificador offline, o
  runbook e a memória canônica foram alinhados à mesma regra fail-closed.
- O runbook do slot deixou de usar o comando inexistente `activate`; a sequência
  agora produz `plan`, usa seu hash exato em `deploy` e conclui com `verify`,
  enquanto o controlador lê a reserva root-only sem argumento arbitrário.
- Nenhum acesso ao servidor, backup, Secret, database, namespace, suspensão,
  migration, imagem, controlador ou workload foi executado.
- O próximo gate é a segunda validação formal da Fase 3.1. Somente após o aceite
  os três binários SaferWPP podem ser construídos, examinados, assinados e
  transportados para um bootstrap fechado; instalação e qualquer mudança viva
  continuam dependentes de autorização própria.

## 2026-08-26 - Cadeia assinada dos controladores SaferWPP preparada

Resultado: release e materialização da plataforma aprovadas offline; host e
runtime permaneceram inalterados.

- O repositório SaferWPP produziu a release
  `swpc-20260827T010424Z-5e8b21d60cd9`, commit
  `5e8b21d60cd9c90546434e2f45ee366b892ff797`, SHA-256
  `d2827620e0fb9733d1e157d9e45e43e328ef8c5938df7bac3894284de721e284`.
- Os três binários Linux/amd64, Node e Cosign isolados passaram contratos em
  container restrito, SBOM SPDX, scan Trivy de vulnerabilidade/segredo,
  proveniência, assinatura ECDSA e verificação independente do bundle exato.
- A plataforma ganhou verificador próprio com trust root fixa, limites contra
  archive malicioso, inventário/modos/hashes exatos e validação das evidências
  antes da extração.
- O bootstrap root fecha release, commit e SHA, exige APIWPP, Blindou e slot
  íntegros, salva arquivos e objetos Kubernetes para rollback, instala somente
  paths e manifests fixos e repete as três provas ao final.
- `saferwpp-deployctl` e `saferwpp-secretsctl` recebem certificados Kubernetes
  exclusivos, sem grupo administrativo, com kubeconfigs root-only, renovação
  diária antecipada, reversão da credencial anterior quando aplicável, métricas
  e alertas de expiração/reconciliação.
- Os testes offline passaram contra o bundle real. Nenhum controlador,
  kubeconfig, RBAC, admission, timer, namespace, Secret, banco, backup, workload
  ou release SaferWPP foi instalado ou aplicado no servidor.
- A primeira validação no Linux recusou corretamente a unit systemd porque o
  gate verificava `ExecStart` antes de instalar o binário no path final. O
  commit `a8127c90757e2f62340ee814881374488060816e` moveu a verificação para
  depois da cópia protegida e ainda dentro do rollback.
- Plataforma, release dos controladores, release da aplicação e trust root
  pública foram transportadas para
  `/home/apiadmin/saferwpp-platform-bootstrap-a8127c9-5e8b21d`, com diretório
  `0700` e arquivos `0600`. Os quatro hashes coincidiram.
- No Linux passaram verificador/testes da plataforma, assinatura e evidências
  do bundle real, três sudoers, duas regras Prometheus, Node/Cosign e os três
  contratos. A análise offline da unit systemd também passou.
- Depois do transporte, `apiwpp-deployctl verify`, `blindou-deployctl status` e
  `blindou-hostctl verify` permaneceram aprovados. `secondary-slotctl` e os três
  controladores SaferWPP continuam ausentes.
- O próximo gate é materializar primeiro o slot e a fundação vazia. Instalação
  dos controladores, suspensão do APIWPP e primeiro deploy permanecem operações
  separadas.

## 2026-08-26 - Papel mínimo do redirector Blindou preparado

Resultado: causa do `not found` confirmada e correção declarativa validada
offline; servidor, banco e runtime permaneceram inalterados.

- O hostname próprio passou a alcançar o redirector após a correção separada da
  rota catch-all do Tunnel; a resposta `not found` isolou a falha na autorização
  PostgreSQL.
- `blindou_redirect_login` pertence ao grupo amplo `blindou_app`, mas o bypass
  tentado pelo processo é aceito pelas policies somente para
  `blindou_runtime`; `FORCE RLS` ocultava o link válido.
- D024 escolheu o grupo dedicado `blindou_redirector`, sem `BYPASSRLS` nem
  privilégios administrativos, em vez de ampliar o papel runtime.
- `blindou-deployctl` passou a preparar o grupo antes da migration e a revogar o
  legado somente depois de registrar `0012`; seu verificador cobre ordem,
  privilégios e proibição do grant amplo.
- O verificador integral dos artefatos da plataforma e seus seis testes de
  contrato passaram, além da sintaxe shell e da verificação de diferenças.
- Nenhum commit, push, bootstrap, instalação, grant vivo, backup, migration,
  imagem ou deploy foi executado. Os próximos gates exigem autorizações próprias
  e o SHA Blindou limpo e publicado.

## 2026-08-27 - Gate de atualização do Blindou corrigido offline

Resultado: defeito do caminho de atualização reproduzido e correção validada;
migration e rollout permaneceram bloqueados antes de qualquer alteração de
schema ou workload.

- A release Blindou `d5766d87a0cf5ba1d5827fa35e8e6a0cac801185` foi assinada,
  validada no cache e passou na prova integral de quatro imagens, 25 blobs e
  119.720.015 bytes.
- A contenção IPv6 foi reconciliada pelo comando idempotente fechado depois de
  o gate detectar uma reconfiguração tardia da interface; UFW, DNS, Internet,
  ONT, K3s e APIWPP voltaram a passar.
- O backup criptografado `blindou-20260827T095256Z`, com 3.023.505 bytes, foi
  baixado em uma única conexão, conferido por SHA-256 e confirmado offsite.
- `activate-release-gates` recusou corretamente antes de alterar namespaces,
  porque sua implementação ainda exigia `blindou-production=secrets-only` em
  uma atualização cujo estado vivo válido era `passed`/`passed`.
- O controlador passou a aceitar somente os pares
  `secrets-only`/`connector-only`, sem release corrente, e `passed`/`passed`,
  com ponteiro root-only válido. Pares mistos continuam falhando fechados.
- Sintaxe, diff e o verificador integral passaram, inclusive os seis testes da
  prova GHCR. A correção ainda não foi instalada no host neste registro.

## 2026-08-27 - Adiamento Pagar.me-first preservado no gate de atualização

Resultado: segunda divergência do controlador corrigida offline; Pagar.me,
schema e workloads permaneceram inalterados.

- Depois da instalação da correção dos pares de gates, a candidata e os gates
  vivos passaram novamente, com Pagar.me ativo e UAZAPI/Resend ausentes.
- `activate-release-gates` ainda exigia o receptor D005 sempre que o modo de
  revisão estivesse encerrado, contradizendo a ordem D020 que deixa
  UAZAPI/Resend por último.
- O usuário confirmou que o Pagar.me já ativo deve ser preservado e autorizou
  alinhar o gate: recibo root-only Pagar.me íntegro mais
  `PAGARME_ENABLED=true` comprovam o adiamento específico; receptor externo já
  confirmado continua aceito e ausência dos dois caminhos falha fechada.
- A correção não lê nem muda chaves, planos, webhook, ConfigMap, Secret,
  migration ou workload. Neste registro ela ainda não foi instalada no host.

## 2026-08-27 - D024 implantada e link protegido validado ponta a ponta

Resultado: migration `0012`, release do redirector mínimo e validação real do
link concluídas; Pagar.me permaneceu ativo e UAZAPI/Resend continuaram adiados.

- Os controladores dos commits `60a9510` e
  `7a3e7e9374fa6d26f7e327ffd0cc373b6d00b760` foram reinstalados pelo fluxo
  fechado. A candidata confirmou quatro imagens, 25 blobs e 119.720.015 bytes.
- A contenção IPv6 foi reconciliada de forma idempotente; UFW, DNS, Internet,
  bloqueio da ONT, K3s e APIWPP passaram novamente.
- O backup criptografado `blindou-20260827T120324Z`, com 3.023.504 bytes e
  SHA-256 `7b64e59b05d948cb516b1f593774a5483202ce9f98be0ec0d33e686741e674de`,
  foi baixado, conferido e confirmado offsite.
- Uma única execução de `apply` registrou `0012`, reconciliou
  `blindou_redirect_login` para o grupo mínimo e implantou
  `d5766d87a0cf5ba1d5827fa35e8e6a0cac801185`. O status final confirmou 12
  migrations, `redirector=dedicated`, todos os workloads Ready e aplicação e
  EDGE em `passed`.
- Fundação, dados, backup, Cloudflare SaaS, GHCR, R2, Pagar.me, contenção do
  host e APIWPP passaram. API, prontidão, painel e Links protegidos responderam
  HTTP 200; host/código desconhecido permaneceu em HTTP 404.
- O link Amazon abriu o produto correto preservando o identificador de
  afiliado. O Relatório de proteção registrou seis acessos, sendo três humanos,
  três bots/previews e zero bloqueados.
- A primeira carga do relatório teve timeout parcial de pool em dois rankings;
  as repetições isoladas em sete e 30 dias concluíram sem erro. A concorrência
  de inicialização ficou registrada para manutenção própria, sem aumentar o
  teto do PostgreSQL nem alterar dados.
- `pagarme_runtime_state=active` foi preservado; nenhuma chave, plano, webhook
  ou cobrança foi modificada. O receptor segue `deferred_uazapi_resend`.

## 2026-08-27 - D053 implantada e relatório validado com redirect real

Resultado: a amplificação de conexões do Relatório de proteção foi removida da
carga inicial, a release nova foi implantada e o link Amazon passou novamente
ponta a ponta.

- O SHA `11e21b3319c197ef18440e7f494290b298f2db1e` passou nos cinco gates D046;
  backend, redirector, NATS e `cloudflared` foram publicados, examinados e
  reunidos em bundle assinado.
- A prova de pull viva confirmou quatro imagens, 25 blobs e 119.734.965 bytes.
- O backup `blindou-20260827T143510Z`, com 3.052.306 bytes e SHA-256
  `0ffcbf1eef8b4df0aa9f4be0dfaf3784451198bc4ce14354d235be4f39019614`,
  foi conferido e confirmado offsite antes do rollout.
- O `apply` implantou a release sem migration nova; aplicação, EDGE, workloads,
  fundação, dados, backup, Cloudflare, GHCR, R2, Pagar.me, contenção do host e
  APIWPP passaram.
- A carga fria autenticada respondeu HTTP 200, sem erro GraphQL, com somente
  `redirectAnalyticsOverview`. O clique real abriu a Amazon preservando
  `tag=guia030-20` e elevou o relatório de seis para sete acessos; código
  desconhecido continuou em HTTP 404.
- Pagar.me permaneceu ativo e UAZAPI/Resend permaneceram adiados.
- O usuário decidiu reter o `.env` administrativo ignorado até a entrada do
  primeiro cliente. Nenhum valor foi aberto ou registrado; D025 preserva a
  leitura exclusiva pelo helper fechado e exige remoção/rotação nesse marco ou
  antes diante de suspeita de exposição.
## 2026-08-27 - Ativação fechada da Shopee preparada

Resultado: D026 implementada e validada offline no repositório; nenhum arquivo
foi instalado no host e nenhum runtime ou segredo foi alterado nesta etapa.

- o controlador exige SHA corrente, aplicação/EDGE em `passed`, Pagar.me ativo
  e marcador de compatibilidade no backend e nos 16 workers;
- a chave de cifra Shopee é gerada no cofre root-only e só entra no Secret
  quando a flag é ativada;
- journal e rollback removem a chave recém-gerada e restauram configuração e
  workloads se a ativação falhar ou for recuperada antes do recibo;
- AppID/App Secret permanecem fora do terminal e serão informados diretamente
  no painel do tenant;
- o verificador offline passou em container Linux, incluindo sintaxe, sudoers
  contratual, marcador da release, observabilidade e orquestrador PowerShell;
- Mercado Livre, UAZAPI, Resend e 2FA permaneceram fora do escopo.

## 2026-08-27 - Slot secundário materializado e inicializado

Resultado: controlador compartilhado instalado e atestado na geração 1, com
APIWPP ativo e SaferWPP vazio; Blindou permaneceu íntegro.

- D027 criou o orquestrador fechado que usa a credencial administrativa somente
  em memória e por `stdin`, fixa host, commit, staging e SHA-256 e copia o
  arquivo autenticado para cache root-owned antes do bootstrap. Nenhum valor da
  credencial foi aberto, impresso ou persistido.
- Tentativas iniciais foram barradas pelo lock de outra operação Blindou ou
  revertidas automaticamente por falhas no coletor de métricas. O diagnóstico
  mostrou o textfile collector padrão como `prometheus:prometheus` `0755` e um
  disparo imediato do timer concorrendo pelo lock do slot. O contrato passou a
  aceitar somente ownership root ou Prometheus sem escrita de grupo/outros, a
  preservar o arquivo de métricas no rollback, limpar somente o estado failed
  da própria unidade e aguardar a coleta liberar o lock. Todos os testes e
  verificadores offline passaram após as correções.
- A instalação final usou o commit
  `76fec3cad8d2f58a37e43fc7bf6ce6ba095cf4cf`, SHA-256
  `5cd4b2ecfbf4199feb3509791b8602d786bef87e14f117132afafe4e2653bfcd`, e criou
  backup transacional em
  `/var/backups/servidor-local/secondary-slot-bootstrap/20260827T220310Z`.
- A operação `20260827T220459Z-b332c6c44b27` inicializou a geração 1 com
  `active_occupant=apiwpp`, um workload APIWPP, zero SaferWPP, admissão instalada
  e nenhuma transição pendente. `verify`, métricas e status passaram.
- Depois da mudança, APIWPP permaneceu Ready com 18 migrations e gateway
  privado; `blindou-deployctl status` e `blindou-hostctl verify` passaram. Não
  houve suspensão, fundação PostgreSQL, Secret, migration, controlador ou
  workload SaferWPP.

## 2026-08-29 - PostgreSQL dedicado Blindou I0/I1 preparado offline

Resultado: contratos e ensaios aprovados; operação externa ainda não executada
neste registro.

- D028 substituiu o destino compartilhado por `blindou-data`, mantendo o banco
  nativo como autoridade até cutover;
- a quarentena declara gate `blocked`, quota zero, Pod Security `restricted`,
  ServiceAccount sem token, default deny e admissão específica;
- a imagem privada deriva do PostgreSQL 18.6 fixo, roda como UID/GID 999 e
  remove `gosu` e snakeoil sem instalar pacotes;
- bundle, controladores e testes recusam extra, traversal, link, evidência,
  imagem, assinatura e envelope de segredo divergentes;
- o laboratório K3s descartável passou TLS+SCRAM, seis logins limitados,
  backup lógico/físico/WAL cifrado, restore-base em PVC novo e recusa de rede;
- nenhuma publicação, instalação, Secret, PVC, workload, backup, restore,
  migration, DSN ou mudança de host foi executada por este registro.

## 2026-08-29 - Fronteira da prova viva I1 corrigida

Resultado: desenho corrigido antes da operação e ampliação mínima autorizada.

- o comando `foundation` existente foi rejeitado para a prova inicial porque
  criaria PVCs, Services, Secret de pull e Job, contrariando o limite aprovado;
- o usuário autorizou `pull-proof`, que usa o PAT GHCR root-only existente,
  baixa todos os blobs do digest assinado e não altera objetos Kubernetes;
- D025 passou a permitir `DataController` somente para o staging por SHA e o
  bootstrap exato de `blindou-datactl`; não há `sudo` genérico;
- publicação, instalação e prova direta foram autorizadas. `foundation`,
  Secrets Kubernetes, PVCs, Pods, backup/restore operacional, migration, DSN,
  workload PostgreSQL, I2 e cutover permaneceram bloqueados.

## 2026-08-29 - Exceção D031/D064 autorizada para a publicação PostgreSQL

Resultado: exceção temporária delimitada e documentada; nenhuma execução viva
foi realizada por este registro.

- O workflow hospedado do Blindou foi recusado antes de qualquer step por
  bloqueio de cobrança do GitHub.
- O usuário autorizou o servidor como executor temporário até solicitar o
  retorno ao GitHub Actions, exclusivamente para a imagem PostgreSQL dedicada.
- D031/D064 mantém a credencial GHCR de escrita na estação e limita o host a
  derivação OCI sem daemon e scan em workspace `apiadmin`, 1 CPU/4 GiB,
  prioridade baixa e sem concorrência com Cargo/Rust.
- `sudo`, Docker/BuildKit, K3s, banco, serviço, segredo, outra imagem,
  `foundation`, migration, restore e cutover continuam proibidos.

## 2026-08-29 - Publicação I1 e correção do caminho administrativo

Resultado: imagem e bundle assinados concluídos; bootstrap ainda não executado
neste registro e helper corrigido antes de acessar a credencial.

- O SHA Blindou `753ec66aab3040cd81a766ffeafe1e9cb0850e18` passou no executor
  efêmero D031/D064, scan bloqueante, SBOM, proveniência, publicação e releitura
  do GHCR. O sujeito aceito foi
  `sha256:2f1c8787a0f689fdc34bf94c59b7f30add5da8c5514930575dc383603a8f3f6d`.
- O bundle SHA-256
  `729d1caafd1691c3d9bd3ea15cacec791cd97e081f5cc1573ea33b2737ad85d7`
  passou nas assinaturas `blindou-data` e `blindou-data-image` para o principal
  público `blindou-local`; a chave privada permaneceu na estação.
- O bootstrap foi interrompido antes de qualquer mudança no host porque o
  helper derivava `.env` do worktree limpo, enquanto a credencial autorizada
  existe somente em `C:\github\servidor\.env`. O arquivo não foi aberto,
  copiado nem vinculado.
- Com autorização específica, o helper passou a fixar esse caminho canônico e
  o gate passou a recusar regressão para caminho relativo ao worktree. Até a
  execução posterior, `blindou-datactl`, namespace, Secret, PVC, Job, Pod,
  migration e banco dedicado continuavam ausentes.

## 2026-08-29 - Bootstrap I1 instalado e prova local corrigida

Resultado: controlador e quarentena instalados; prova de pull interrompida
localmente antes do transporte e correções fail-closed preparadas.

- O bootstrap do commit de plataforma
  `3194252bb5a2f732994b7e8a897cf8aadb45610a` instalou `blindou-datactl` e
  criou `blindou-data` com gate `blocked`, zero PVC, zero Pod pronto, nenhuma
  imagem e zero prova de pull. Host, K3s, Blindou e APIWPP foram validados
  separadamente depois que seus locks periódicos ficaram livres.
- O bloco pós-bootstrap não usava `set -eu` e podia imprimir `passed` depois de
  um lock transitório do `blindou-deployctl`. A correção passa a propagar a
  primeira falha remota ao orquestrador.
- A primeira chamada de `pull-proof` foi recusada ainda na estação, antes de
  archive, upload ou acesso ao host: com `StrictMode`, uma única linha de imagem
  era escalar e não expunha `.Count`. A correção materializa explicitamente o
  array e continua exigindo exatamente um digest PostgreSQL privado.
- Nenhum Secret, PVC, Job, Pod, Service, workload PostgreSQL, migration, DSN,
  backup, restore, I2 ou cutover foi criado por essas tentativas.

## 2026-08-29 - Contrato do scanner D064 corrigido antes do pull

Resultado: tentativa recusada antes do download e verificador corrigido de
forma fail-closed para as duas linhas imutáveis autorizadas.

- A tentativa seguinte alcançou a validação do bundle no host, mas foi
  recusada antes do pull porque o verificador conhecia somente o caminho
  normal Trivy 0.67.2 por imagem, enquanto a candidata autorizada contém o
  binário Trivy 0.70.0 e o recibo D064.
- O contrato passou a aceitar exatamente a linha normal sem recibo D064 ou a
  linha excepcional com archive SHA-256
  `8b4376d5d6befe5c24d503f10ff136d9e0c49f9127a4279fd110b727929a5aa9`,
  versão 0.70.0 e recibo completo vinculado ao SHA, base, source index,
  Dockerfile, recursos e negativas de acesso.
- Testes positivos cobrem ambas as linhas; versões, hashes, ausência de recibo
  e combinações híbridas são recusados. A candidata real
  `sha256:2f1c8787a0f689fdc34bf94c59b7f30add5da8c5514930575dc383603a8f3f6d`
  passou localmente no contrato corrigido.
- Não houve download da imagem nem criação de Secret, PVC, Job, Pod, Service,
  workload PostgreSQL, migration, DSN, backup, restore, I2 ou cutover.

## 2026-08-29 - Escopo Bash do recibo corrigido antes do download

Resultado: nova tentativa recusada depois das assinaturas e antes do download;
o defeito de escopo recebeu correção e gate de regressão.

- O bundle real passou no verificador D064 instalado pelo commit
  `37b7e21f293f4c112f509837932a89c9a3c70b98`, mas `set -u` recusou a função
  `receipt_passes`: `name` era referenciada na mesma declaração `local` que a
  atribuía, antes de ficar disponível para a expansão do caminho.
- `require_receipt` e `receipt_passes` agora atribuem `name` e somente na linha
  seguinte derivam o caminho root-only. Gates Windows e Linux recusam a forma
  regressiva.
- A falha ocorreu antes do downloader e preservou `pull_proofs=0`, gate
  `blocked` e zero Secret, PVC, Job, Pod, Service ou workload PostgreSQL.

## 2026-08-29 - PostgreSQL dedicado I1 comprovado sem materializar banco

Resultado: imagem, bundle, controlador, quarentena e pull integral aprovados;
fase pronta para confirmação humana.

- O controlador final veio do commit
  `8b892b962f4096678c8ae6e0fb89bfe27b25b6de`, archive SHA-256
  `aecec330574a99e28aecddb2505241b81a86ca2696c4fd7c722245ca765af1d6`.
- A candidata Blindou
  `753ec66aab3040cd81a766ffeafe1e9cb0850e18` passou nas assinaturas e o
  downloader comprovou o digest
  `sha256:2f1c8787a0f689fdc34bf94c59b7f30add5da8c5514930575dc383603a8f3f6d`:
  uma imagem, 15 blobs e 157.256.746 bytes. O archive de transporte possui
  SHA-256 `6bfc13df24df7356055e4fcf37a4cad0df1c1d17779006983dffa6d292f2fa8e`.
- A auditoria independente terminou em `namespace=blindou-data gate=blocked
  ready=0 pvc=0 image=none pull_proofs=1 cutover=false`; host, APIWPP e Blindou
  passaram.
- Três workspaces efêmeros de tentativas falhas foram validados como 0700,
  pertencentes a `apiadmin`, e removidos por caminhos exatos. Imagens órfãs no
  GHCR permaneceram intactas por falta de autorização destrutiva específica.
- Nenhum Secret, PVC, Job, Pod, Service, StatefulSet, database, migration,
  backup, restore, DSN, I2 ou cutover foi criado ou executado.

## 2026-08-29 - Controlador fechado DRE preparado offline

Resultado: fundação, controlador, identidade, empacotamento e verificadores DRE
foram preparados no repositório sem alterar o host.

- D029 definiu o DRE sempre ativo fora do slot APIWPP/SaferWPP, com namespaces,
  banco, PVC, rede, release, backup e chave de assinatura exclusivos;
- a interface `dre-deployctl` limitou importação, inicialização de Secrets,
  plano, deploy, verificação, backup e restore-drill, sem shell ou `kubectl`
  genérico;
- releases exigem assinatura Ed25519, quatro estágios fixos, imagens por digest,
  SBOM SPDX e scans sem vulnerabilidade alta/crítica;
- a fundação declarou admissão fail-closed, RBAC mínimo, identidade renovável,
  métricas, alertas e restore em PVC descartável;
- testes offline cobriram archives maliciosos, segredos, restore, sintaxe,
  contratos e isolamento. Instalação e operação permaneceram separadas.

## 2026-08-29 - Fundação vazia e controlador DRE instalados

Resultado: fundação e controlador instalados no host, com estado vazio,
bloqueado e observável. Nenhuma release ou carga financeira foi aplicada.

- a auditoria viva aprovou hostname/arquitetura, quatro CPUs, 10.671.804 KiB de
  memória disponível, 183.666.928 KiB livres no K3s, versão
  `v1.36.2+k3s1`, zero units falhas e os projetos protegidos;
- a chave Ed25519 foi criada fora dos repositórios. Somente a chave pública de
  SHA-256 `4902604dad96d9b07f4010308d30e3815cb4e76446855d925079be0e3b922ce9`
  entrou no host;
- D030 autorizou somente o helper fechado a ler `KEY_SERVIDOR`, mantê-la em
  memória e enviá-la por `stdin`, com host, staging, hashes e bootstrap fixos;
- o bundle root-owned final teve SHA-256
  `6b8e0e81190b4cda040abd8806c32ccd104fd291cb9dc325790595f77953ced1`
  e backup transacional em
  `/var/backups/servidor-local/dre-controller-bootstrap/20260829T235150Z`;
- namespaces, StorageClasses, RBAC, admissão, identidade, sudoers, timers,
  alertas e controlador foram instalados. A pós-condição comprovou zero
  workload, Pod, Service, PVC ou Secret e recusou identidade não autorizada;
- `dre-deployctl status` retornou release `none`, gate `blocked`, PVC ausente e
  zero API/worker/PostgreSQL Ready; APIWPP, Blindou e slot passaram.

## 2026-08-30 - Primeira release DRE importada e token da ponte corrigido

Resultado: publicação e importação da candidata concluídas sem ativação. Uma
falha de coordenação do token Pages/API foi encontrada antes dos Secrets e
corrigida na fonte do controlador sob D032.

- as imagens privadas `dre-app` e `dre-postgres` foram publicadas por digest
  `linux/amd64`, com SBOM e scan remoto sem achado alto/crítico;
- o Pages `dre-familiar` publicou o commit
  `8949efc1e10df3607120932847449a9ca2b16ec7` e respondeu HTTP 200 em
  `https://dre-familiar.pages.dev`; o bucket privado e vazio
  `dre-familiar-backups` foi criado sem credencial operacional;
- a release `dre-20260830T010200Z-29aeeb82d5bc` passou assinatura Ed25519,
  conteúdo fechado e hashes. O archive
  `fa48fd316cee2e4c8553232dc0b3ef218b63555c72f9dda537e38ebb4a379ffe`
  foi aceito por `import-release`;
- depois da importação, `dre-deployctl status` permaneceu em release corrente
  `none`, gate `blocked`, PVC ausente e Ready `0/0/0`. APIWPP, Blindou e slot
  passaram novamente e nenhuma porta DRE foi aberta;
- a revisão pré-Secrets detectou que o token da ponte era gerado dentro do host
  e apagado, portanto não podia chegar ao Pages sem leitura indevida de Secret;
- D032 exige `web_bridge_token` forte na entrada protegida, preserva o mesmo
  valor para o Secret da API e nunca o imprime. Testes cobrem equivalência,
  ausência em saída e rejeição de campo ausente, curto ou inválido;
- a reconciliação, publicação e instalação do controlador corrigido foram
  autorizadas sem ampliar o escopo para credenciais, Secret, migration,
  workload, origem HTTPS ou dado financeiro.

## 2026-08-30 - Controlador DRE D032 reconciliado e instalado

Resultado: fonte canônica publicada, controlador corrigido instalado e release
anterior preservada, ainda sem Secrets ou ativação.

- o trabalho local divergente do repositório `servidor` foi preservado sem
  mistura; a reconciliação partiu de `origin/main` e conservou integralmente a
  entrega D031 do PostgreSQL Blindou;
- os commits `b1cdb26` e `ae7d5c9` publicaram respectivamente o controlador e a
  memória operacional em `origin/main`;
- o bundle fechado de 16 arquivos, SHA-256
  `85063b55e3a0325616bba69d28362a3aac1a175768a7c3394bebbc97efcceb2d`,
  coincidiu byte a byte com as fontes e foi instalado pelo helper D030;
- o bootstrap produziu backup transacional em
  `/var/backups/servidor-local/dre-controller-bootstrap/20260830T035453Z` e o
  contrato passou a declarar `secret_input_schema=1` e
  `bridge_token_source=orchestrator-stdin`;
- a release `dre-20260830T010200Z-29aeeb82d5bc` foi reverificada pelo caminho
  idempotente e já existia no cache com o mesmo digest. A release corrente
  permaneceu `none`, gate `blocked`, PVC ausente e Ready `0/0/0`;
- APIWPP, Blindou, slot, timers, métricas e zero units falhas passaram. Os
  listeners não mudaram: 443/8080 ausentes, 8443 somente em `10.203.0.2` e o
  PostgreSQL nativo preexistente em 5432 também exposto na LAN administrativa;
- nenhum Secret, PVC, Service, Pod, workload, migration, backup de dados,
  restore, origem HTTPS ou dado financeiro foi criado ou alterado.

## 2026-08-31 - Candidata DRE schema 2 construída e publicada

Resultado: três imagens finais publicadas e release assinada importada sem
ativar produção.

- O commit DRE `57984e1c19028f507acb0da5e7bd8c8af8f8c3bb` foi construído no
  executor BuildKit efêmero do servidor, sem Docker/WSL na estação e sem acesso
  ao containerd do K3s.
- `dre-app`, `dre-postgres` e `dre-validation-runner` foram publicados pelos
  digests `sha256:0bb138ec37338c4466acf50e6920894d5813fa5f39505e69b89359bb81869255`,
  `sha256:b78ad6ce6c7b376aa131eee464117fb26964f070ff5e336b99bbee1611c0bc06`
  e `sha256:3b3de731996456cedf999fe99afda3968c2a6a26a0998016cdfbcf87cf79d1cc`.
- Syft 1.51.0 gerou SBOMs SPDX e Trivy 0.72.0 registrou zero vulnerabilidade
  alta ou crítica para as três imagens. A credencial GHCR atravessou SSH apenas
  por `stdin` e não entrou em recibo ou argumento.
- A release `dre-20260831T053100Z-57984e1c1902` foi empacotada duas vezes com
  bytes idênticos. O archive SHA-256 é
  `014440dca9f6e187e2da4078dbecbce08d65355953e05af412eb166978001629`;
  a assinatura Ed25519 foi verificada independentemente e o controlador aceitou
  o bundle no cache root-only.
- Antes da validação, `dre-production` permaneceu em `release=none`, gate
  `secrets-only`, sem PVC e com Ready `0/0/0`; `dre-validation` estava ausente.

## 2026-08-31 - Falhas da validação schema 2 corrigidas por evidência viva

Resultado: quatro incompatibilidades foram corrigidas sem tocar produção e com
limpeza explícita de cada ambiente descartável bloqueado.

- A candidata `f270fd7` aprovou migrations e acessos, mas o runtime recusou
  `SET ROLE` porque os grupos funcionais estavam `SET FALSE`. O commit DRE
  `2a580fe` preservou `NOINHERIT` e concedeu somente `SET TRUE` aos logins que
  precisam assumir esses grupos.
- O controlador aprendeu no commit servidor `70fe4b2` o único `initContainer`
  `wait-for-postgres` admitido, com espera limitada para a convergência de rede;
  `91838ef` fixou esse verificador no bundle instalado.
- A candidata `2a580fe` deixou API, worker e PostgreSQL Ready, mas o E2E usou
  `/events` fora do prefixo `/v1`. `2ae2673` centralizou a derivação do endpoint
  e preservou o prefixo; a tentativa seguinte revelou rejeição indevida de
  query relativa. `57984e1` passou a aceitar query segura e a recusar URL
  absoluta, origem alternativa e escape de prefixo.
- Na operação `20260831T053600Z-57984e1c1902`, migrations, acessos, bootstrap,
  E2E e reinícios terminaram, mas o gate final chamou
  `blindou-deployctl status` enquanto o próprio DRE ainda mantinha o lock
  Blindou. O recibo falhou em `restarts` e preservou `dre-validation` para
  diagnóstico, sem alteração em produção.

## 2026-08-31 - Controlador corrigido e validação DRE concluída

Resultado: controlador publicado/instalado, validação integral aprovada e
ambiente descartável removido.

- O controlador passou a comparar fingerprints sob os locks e a liberá-los em
  ordem inversa antes de chamar os verificadores independentes. O gate estático
  cobre `validate-release`, `cleanup-validation` e `deploy`.
- O repositório servidor passou no gate integral e publicou o commit
  `4d0ed61`. O bundle de instalação SHA-256
  `689c3f0f97c7d4f5e9d14d4cfe6e11b7582fa82071d94685a617d2f0d5d6b004`
  foi reproduzido, verificado e instalado com backup transacional em
  `/var/backups/servidor-local/dre-controller-bootstrap/20260831T054354Z`.
- `cleanup-validation` removeu o namespace/PVC/PV preservado. A operação final
  `20260831T055000Z-57984e1c1902` confirmou nove migrations, papéis de acesso,
  bootstrap de contas sintéticas, E2E financeiro, SSE/queries e substituição
  controlada de API, worker e PostgreSQL; em sucesso, removeu novamente o
  namespace, PVC e PV.
- O estado final permaneceu `dre-production release=none gate=secrets-only`,
  PVC ausente e Ready `0/0/0`; `dre-validation` ficou ausente. Nenhuma migration
  persistente, banco, workload, backup/restore, rota HTTPS, conta ou dado real
  foi criado.
- `blindou-deployctl status` confirmou a release
  `ee4a335236b0e99e5fac4ee3e30a986f0ddc8bb2`, 12 migrations e gates saudáveis.
  `secondary-slotctl verify` passou na geração 2 com ocupante `none`, e
  `systemctl --failed` retornou zero unidade.

## 2026-08-31 - Executor rootless dos gates DRE preparado offline

Resultado: decisão e bootstrap fechados; instalação e execução viva ainda
pendentes neste registro.

- D036 escolheu Podman rootless porque o Makefile exige builds, Compose e bancos
  descartáveis, enquanto Windows, K3s genérico e daemon persistente permanecem
  proibidos;
- o bootstrap fixa Ubuntu 24.04 amd64, host, commit, archive, seis pacotes APT,
  inventário, recibo e rollback da diferença de pacotes novos;
- grupos, `subuid`, `subgid`, kubeconfig/socket K3s, units e sockets Podman são
  comparados antes/depois. Não há novo sudoers, grupo, `kubectl` ou autoridade
  de cluster;
- o orquestrador exige artefatos commitados e publicados, SSH estrito e intervalo
  entre conexões; a senha administrativa segue somente em memória e `stdin`;
- o smoke usa `--root`, `--runroot`, XDG e imagem por digest em `/tmp`, valida
  build, uidmap, `init` e podman-compose e apaga o storage ao terminar;
- nenhum pacote, serviço, container, namespace, migration, Secret, workload ou
  dado foi alterado por esta preparação offline.

## 2026-08-31 - Gates integrais e release final DRE validados

Resultado: revisão final aprovada nos gates integrais e no controlador vivo,
sem ativar produção; recursos descartáveis foram removidos.

- O commit DRE `f6b06765ff6196eb8dbd4a9a9fd8c3a422c42ce2` concluiu
  `make release-check` e, em uma stack sintética nova, `make e2e`. Os logs têm
  SHA-256 `4facb3f38ba66e7bf01a1c4767aad2b2dd35e6476a2874bc9136f3b5ec3d0024`
  e `422303c8796d137cd9909bb341bff11f6c0397b9b74b51dda1e41209a3ec423a`.
- BuildKit efêmero produziu as três imagens `linux/amd64`; Syft gerou os SBOMs
  SPDX e Trivy registrou zero vulnerabilidade alta ou crítica. O verificador do
  slot encontrou uma corrida curta com o lock do coletor depois do build; os
  artefatos foram conferidos independentemente e a fonte passou a repetir
  somente esse erro transitório exato, mantendo qualquer divergência fail-closed.
- Os digests publicados são `dre-app@sha256:4f91068dd559fe4852bdc19ee76ad2b4e700695364378265ce0674332891d3d6`,
  `dre-postgres@sha256:029bb2112afae1fca539381bf338fb9c64443b668230c17cd51447c0efb7f2e1`
  e `dre-validation-runner@sha256:7a62c80e8d0094f366d2dbfbfa6fa3c15b439aa20134e7450d63f981ce9615c5`.
- A release `dre-20260831T202100Z-f6b06765ff61` foi empacotada duas vezes com
  archive idêntico SHA-256
  `05c14e22ffa092e16f4a7530c8ecddf5216ad6faa54be401ab48d1c5e90b954d`;
  assinatura, conteúdo, SBOMs e scans passaram na importação fechada.
- A operação `20260831T202626Z-f6b06765ff61` aprovou nove migrations, acessos,
  duas contas/dispositivos sintéticos, fluxo financeiro, SSE e reinícios de
  API, worker e PostgreSQL. Em sucesso, removeu namespace, PVC e PV.
- A pós-condição manteve `dre-production` em `release=none`, gate
  `secrets-only`, sem PVC e Ready `0/0/0`; `dre-validation` ficou ausente.
  Blindou e o slot secundário passaram. Nenhuma migration persistente, rota,
  conta, dispositivo ou dado real foi criado.
- Containers, redes, volumes, imagens, processos, caches e raízes temporárias
  do executor foram removidos por caminhos exatos. Os pacotes rootless sem
  serviço ou socket permanecem instalados conforme D036.

## 2026-09-01 - Controlador DRE preparado para o primeiro deploy persistente

Resultado: bloqueio do plano corrigido, provisionamento atômico fechado e
controlador instalado sem ativar produção.

- O `plan` encerrava silenciosamente porque `capacity_values` não terminava sua
  saída com quebra de linha e o `read` retornava EOF sob `set -e`. O commit
  servidor `e26c528` adicionou a quebra de linha e um gate estático específico.
- O commit DRE `e1423b7` adicionou `provision-private-family`: Argon2id é
  calculado fora do executor assíncrono, as duas senhas chegam por `stdin` e o
  núcleo com Gleison/Aline é gravado em uma única transação. O controlador
  expõe somente `provision-accounts`, com UUIDs validados e recibo sem segredo.
- A suíte integral do repositório servidor passou no Windows sem WSL; o teste
  de modo `0600` foi tornado portável e continua exigindo o modo real em POSIX.
  O bundle de 18 arquivos teve SHA-256
  `56612eebcbd60726751dea0b30c04eebaad99f1ee2d5b151b615f652943603b7`.
- O helper D030 instalou o bundle e registrou backup transacional em
  `/var/backups/servidor-local/dre-controller-bootstrap/20260901T151732Z`.
  Hash vivo/fonte coincidiram; contrato, bootstrap, admissão e projetos
  protegidos passaram.
- `dre-deployctl status` permaneceu em release `none`, gate `secrets-only`, PVC
  ausente e Ready `0/0/0`. O primeiro `plan` depois da correção retornou
  `status=passed` para a release já validada. Nenhum PVC, migration persistente,
  workload, conta, rota ou dado financeiro foi criado neste passo.

## 2026-09-02 - Candidata persistente DRE fixada no commit 601e422

Resultado: preparação declarativa e fonte autenticada concluídas; o gate
integral continua em execução e produção permanece intacta.

- O archive `source.tar` foi derivado por `git archive` do commit DRE
  `601e4224d59fb40f4418f6e9de153bbf6047fa2c`, possui 6.748.160 bytes e
  SHA-256 `d164da586cb6d8aac59c22cdf0ab785a5e6a2c9761e213a90749997fbd049f9f`.
- Os orquestradores fechados de build e publicação foram fixados no novo SHA,
  staging `/home/apiadmin/dre-image-build-601e4224d59f-20260902T043140Z` e
  hashes das ferramentas já aprovadas; o teste integral do repositório passou
  no Windows sem WSL.
- O gate sintético rejeitou uma duplicação do próprio roteiro externo depois de
  todos os testes do produto: `make dev-up` precedia `make e2e`, embora `e2e`
  já possua `foundation-e2e -> dev-up`. O roteiro externo foi corrigido para
  uma única subida limpa e reiniciado; nenhum código DRE ou runtime foi alterado
  por essa correção.
- Nenhuma imagem, release, migration, PVC, workload, conta, rota ou dado real
  foi criado por esta preparação.

## 2026-09-02 - Gate Android estabilizado e candidata DRE renovada

Resultado: a concorrência instável do gate foi removida da configuração padrão;
a candidata persistente passou a ser `69716bb` e produção permaneceu intacta.

- Uma execução limpa do `lintDebug` falhou no KSP2 com
  `NoClassDefFoundError` enquanto tarefas de compilador e lint de outros módulos
  estavam concorrentes. A repetição isolada, também em cache limpo, passou, o
  que caracterizou instabilidade do gate em vez de defeito das entidades Room.
- O commit DRE `69716bb0a23e02cc839f1adac0a41fbc521f7f04` serializou a execução
  entre projetos Gradle. `spotlessCheck` e `lintDebug` passaram nativamente no
  Windows, sem WSL ou Docker local, usando JDK 17 explícito.
- O novo `source.tar` possui 6.748.160 bytes e SHA-256
  `17ab942c6527f086e4c36298488840c05a981c8db9f2c60ec8305db787635640`.
  Build e publicação foram fixados no staging
  `/home/apiadmin/dre-image-build-69716bb0a23e-20260902T050116Z`.
- O gate integral contínuo foi reiniciado para a nova candidata. Nenhuma
  imagem oficial, release, migration, PVC, workload, conta, rota ou dado real
  foi criado por esta renovação.

## 2026-09-02 - Release oficial pronta e importação recusada antes da produção

Resultado: candidata oficial, imagens e pacote assinado concluídos; a primeira
importação falhou fechada antes de alterar o runtime persistente.

- Os gates integrais do commit DRE
  `69716bb0a23e02cc839f1adac0a41fbc521f7f04` passaram em duas pilhas sintéticas
  independentes. As três imagens `linux/amd64` foram publicadas por digest com
  SBOM e scan sem vulnerabilidade alta ou crítica.
- A release `dre-20260902T061906Z-69716bb0a23e` foi empacotada duas vezes com
  archive SHA-256
  `ee4f050c5eb202745e85a0d7d05d7771d4c29bb2ed1c6e8bb2b304a394a1bd36`;
  assinatura Ed25519 e envelope passaram na verificação independente.
- `import-release` recusou a operação com `edge contém objeto proibido` antes
  de copiar a candidata para o cache. A inspeção da fonte encontrou
  `verify_edge_baseline` agrupando qualquer `ConfigMap` com recursos proibidos,
  embora o Kubernetes materialize automaticamente `kube-root-ca.crt` no
  namespace.
- A correção mantém a quota em zero e admite no máximo esse único `ConfigMap`,
  somente com `data.ca.crt` em PEM, sem `binaryData` e não imutável. Qualquer
  outro nome, chave ou recurso continua falhando fechado.
- O estado permaneceu `release=none`, gate `secrets-only`, PVC ausente e Ready
  `0/0/0`. Nenhuma migration persistente, workload, conta, backup, rota ou dado
  financeiro foi criado pela tentativa recusada.

## 2026-09-02 - Importação DRE aprovada e prova de edge endurecida

Resultado: a release oficial entrou no cache, mas o avanço para validação foi
interrompido para corrigir uma prova de ausência com RBAC insuficiente.

- Os commits de plataforma `8900fee` e `861b827` publicaram e fixaram o bundle
  SHA-256
  `5b0b568d1597f6791f6e423224a6b6dc6a89312f76aee537decc553ade2d89f3`.
  O helper D030 o instalou com backup transacional em
  `/var/backups/servidor-local/dre-controller-bootstrap/20260902T064113Z`.
- Hash vivo, contrato schema 2 e estado vazio coincidiram. A importação da
  release `dre-20260902T061906Z-69716bb0a23e` então passou e armazenou a
  candidata no cache fechado.
- A saída também registrou `Forbidden` ao listar Deployment e Secret do edge.
  O inventário usava a identidade mutável DRE, cujo RBAC deliberadamente não
  concede `list` amplo; a combinação com a consulta agregada podia produzir
  lista vazia mesmo sem prova de acesso.
- O fluxo foi interrompido antes de `validate-release`. A correção usa a
  interface administrativa somente leitura já adotada no restante do baseline
  e adiciona gate que proíbe regressão para a identidade insuficiente.
- Produção continuou `release=none`, gate `secrets-only`, sem PVC, migration,
  workload, conta, backup, rota ou dado financeiro.

## 2026-09-02 - Validação aprovada e primeiro deploy DRE revertido antes das migrations

Resultado: a candidata oficial passou integralmente no ambiente descartável; o
primeiro deploy persistente falhou seguro no pgBackRest e preservou apenas o
banco/PVC para diagnóstico.

- O bundle de controlador
  `f4b0255daa03b989af83e23c28d40fb624307e3bdd8f7fa8f90b44a6d4e1a056`
  foi instalado com backup em
  `/var/backups/servidor-local/dre-controller-bootstrap/20260902T064811Z`.
  Hash fonte/vivo, contrato e reimportação idempotente passaram sem `Forbidden`.
- A operação descartável `20260902T064929Z-97891da83f92` aprovou nove
  migrations, acessos, E2E e reinícios de API, worker e PostgreSQL; removeu
  namespace, PVC e PV ao concluir.
- O plano autenticado retornou SHA-256
  `7136dd2106778f011b7b85b5195e24c229377edf4f940d9d8bc53cea38bad1e6`.
  O deploy `20260902T065643Z-f6defcfcb55d` aplicou a plataforma e iniciou o
  PostgreSQL, mas terminou com código 82 no `pgBackRest check`, antes das
  migrations.
- A compensação passou. O status final foi `release=none`, gate
  `secrets-only`, PVC `Bound`, Ready `api=0`, `worker=0`, `postgres=1`, edge
  bloqueado e validação ausente. A tabela `_sqlx_migrations` não existe.
- D038 limita a recuperação a um bootstrap que prova esse inventário, não
  reaplica a fundação, preserva fingerprint do runtime e instala somente
  `diagnose-production`, sem argumentos, escrita no R2, shell ou `kubectl`.
- A primeira chamada do helper para o bundle de diagnóstico exibiu `printf:
  usage` e retornou zero sem executar o script root: as aspas duplas internas
  foram reinterpretadas pelo `ssh.exe`. O contrato vivo continuou antigo e o
  novo comando permaneceu sem sudoers, comprovando ausência de mutação. O
  transporte foi corrigido para aspas simples do shell remoto e passou a exigir
  o marcador final com os hashes esperados; código zero isolado não declara
  mais sucesso.
- O bundle corrigido foi instalado de fato e gerou backup transacional em
  `/var/backups/servidor-local/dre-controller-bootstrap/20260902T075135Z`.
  A primeira coleta recusou o namespace porque o rótulo canônico de projeto não
  estava disponível após o rollback. O diagnóstico foi endurecido para
  recomprovar por leitura administrativa o recibo, os objetos exatos, a imagem
  assinada e a ausência de migrations, e passou a registrar o rótulo como
  evidência em vez de presumir que metadado ausente não integra a própria causa.
- O mesmo padrão de aspas ambíguas existia no helper root do build de imagens.
  Antes de renovar a candidata ele foi corrigido para o transporte já provado
  pelo bootstrap e passou a exigir o atestado final com revisão e diretório de
  saída exatos; código zero sem execução real também é recusado nesse fluxo.
- O bundle de diagnóstico
  `af943097715fb73f32d1aecba8aa6bc28f2b19bf414841357f0a6369c1f30c47`
  foi instalado com backup transacional `20260902T080118Z`. A coleta fechada
  provou o recibo/rollback, inventário exato, PostgreSQL Ready, PVC `Bound` e
  ausência de `_sqlx_migrations`.
- `pgBackRest info` confirmou stanza e repositório cifrado acessíveis, ainda sem
  backup. O log do PostgreSQL mostrou `realpath: -e` e `realpath: --` como
  caminhos inexistentes: a implementação usava opções GNU que o BusyBox da
  imagem Alpine não oferece. O rótulo `platform.servidor.local/project` também
  estava vazio após o apply da release.
- O commit DRE `8c5280709b2f648268eb38aae5972f1449facc98` substituiu a resolução
  por allowlist de `pg_wal`, arquivo regular não simbólico e `readlink -f`,
  acrescentou testes positivos/negativos no container e preservou o rótulo
  `project: dre` no manifesto. Nova release exige gates e imagens renovados.
- O archive Git dessa revisão possui 6.748.160 bytes e SHA-256
  `a88efcd650345cb6db8bf9c1162ef8608b251d672763e4f81748fb3c461a36a9`;
  o staging fechado do novo build é
  `/home/apiadmin/dre-image-build-8c5280709b2f-20260902T081043Z`.

## 2026-09-02 - Gates e imagens renovadas após a correção do pgBackRest

Resultado: revisão corrigida aprovada em duas pilhas sintéticas e três imagens
imutáveis publicadas; produção permaneceu no estado seguro do rollback.

- O commit DRE `8c5280709b2f648268eb38aae5972f1449facc98` passou no
  `make release-check` literal e em um segundo `make e2e` sobre stack limpa no
  executor rootless do servidor. Os logs possuem SHA-256
  `9ca57375175a00cef21fc985d7de7f9c163d33bafeee9a545ecc81c2eedd9cf3` e
  `69c4f3a04081cf161d82afc0edf019b5e102e6bdc142b8f18193e05891f0091f`.
- O build fechado produziu as três imagens `linux/amd64` a partir do archive
  Git SHA-256 `a88efcd650345cb6db8bf9c1162ef8608b251d672763e4f81748fb3c461a36a9`.
- A primeira chamada da publicação foi recusada localmente antes do SSH porque
  Windows PowerShell 5.1 não fornece `ProcessStartInfo.ArgumentList`. O
  orquestrador passou a montar `ProcessStartInfo.Arguments` com escape nativo
  explícito, mantendo a credencial GitHub somente em `stdin`; a suíte integral
  do repositório aprovou a correção.
- Syft 1.51.0 gerou os SBOMs e Trivy 0.72.0 registrou zero vulnerabilidade alta
  ou crítica. Foram publicados os digests
  `dre-app@sha256:9d2e0af0e3857ecd634f185d1c46e8dda99051b2b4b19d0b976d194e48fdd88e`,
  `dre-postgres@sha256:30ef6d4e0e695878f684e6fc50c97c84b903f79e582b9cfc5ad6155d02561cd5`
  e `dre-validation-runner@sha256:1e7ece3835bb075d8a70f023931dccbc74c543496c7ea82d51ee1f91f002ac5b`.
  O recibo técnico possui SHA-256
  `a0370a222abf005cd83e0641a26c622cdc1f5c40c51f6a968a6829919200ce1e`.
- Nenhuma release renovada, migration, conta, backup, rota ou dado financeiro
  foi criada neste passo. O próximo gate é empacotar e validar a release
  assinada antes da recuperação controlada do primeiro deploy.

## 2026-09-02 - Recuperação limitada do primeiro deploy preparada

Resultado: contrato fechado D039 implementado e validado offline; runtime ainda
permaneceu no estado do rollback.

- A importação da release `dre-20260902T094748Z-8c5280709b2f`, archive SHA-256
  `07980835cfc28c19b8ae2312c68cf08878aaa7f73bc877f0346160cf9161663e`,
  foi recusada antes do cache pelo rótulo de projeto ausente já diagnosticado.
- O controlador passou a admitir importação e validação nesse estado somente
  após recompor recibo falho, imagem anterior, inventário, cinco Secrets, PVC
  `Bound` e ausência de migrations.
- A nova ação `recover-first-deploy` exige release schema 2 validada e troca
  somente o rótulo canônico e a imagem PostgreSQL pelo digest assinado. Ela
  confere `pgBackRest`, preserva PVC/Secrets/projetos por fingerprint e não
  aplica migration nem publica release corrente.
- Rollback restaura a imagem/rótulo anteriores; falha de compensação fecha o
  gate. Sudoers, contrato, verificador independente e runbook foram atualizados
  sem adicionar shell, `kubectl` ou imagem livre.
- Nenhuma mutação adicional foi executada no cluster por este registro. O
  próximo passo é publicar/instalar o controlador e repetir importação,
  validação e recuperação sob os gates D038/D039.

## 2026-09-02 - Release renovada validada e recuperação compensada

Resultado: a candidata renovada passou no ambiente descartável; a primeira
recuperação D039 falhou no `pgBackRest` e restaurou integralmente o pré-estado.

- O controlador D039 foi instalado pelo bundle autenticado
  `c544f8c5eb73ceaed284fe2d7b0dc9944ba9ffc5b81d5f80084eb6fe81d04b90`.
- A release `dre-20260902T094748Z-8c5280709b2f` foi importada e a operação
  descartável `20260902T101302Z-2367f5a8676e` aprovou os estágios e removeu o
  namespace, PVC e PV de validação.
- A recuperação `20260902T101742Z-638ffcf33c96` recebeu código 50 no
  `pgBackRest`. A compensação restaurou a imagem anterior, removeu o rótulo
  temporário, manteve o gate `secrets-only`, o PVC `Bound`, PostgreSQL Ready e
  `_sqlx_migrations` ausente.
- Como a saída do comando havia sido suprimida, o controlador passou a devolver
  somente o erro sanitizado e limitado de `stanza-create`/`check`, sem
  persistir payload técnico no recibo nem ampliar a interface administrativa.
- A repetição `20260902T103328Z-570f872cbbf9` confirmou código 50 porque
  `archive-async` mantinha o lock `dre-archive-1.lock`; endpoint e credenciais
  R2 foram redigidos, e o rollback voltou a preservar o pré-estado.
- A correção classifica somente essa combinação de código e mensagens como
  transitória, com oito tentativas, backoff exponencial, jitter e espera máxima
  de 30 segundos. Ela também cria os diretórios efêmeros de log/lock em `0700`
  e é reutilizada pelo deploy normal.
