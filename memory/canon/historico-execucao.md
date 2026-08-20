# Histórico de execução

metadata:
  canon_id: canon-historico-execucao
  source_path: memory/canon/historico-execucao.md
  generated_from: auditorias e implementações autorizadas no laboratório
  updated_at: 2026-08-19
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
