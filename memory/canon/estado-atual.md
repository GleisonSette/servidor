# Estado atual da plataforma local

metadata:
  canon_id: canon-estado-atual
  source_path: memory/canon/estado-atual.md
  generated_from: auditoria SSH, runtime K3s, Prometheus e repositórios locais
  updated_at: 2026-08-22
  status: canonical

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
  `blindou-edge`; a aplicação, migrations e release continuam bloqueadas,
  portanto nenhum deploy comercial do Blindou é autorizado no estado atual.

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
- `blindou-deployctl` está instalado como root com suporte fechado ao conector,
  às credenciais Cloudflare for SaaS/GHCR, à release assinada e à prova de pull
  das quatro imagens privadas. O SHA-256 da
  fonte final é
  `e6e06d77aa83558e1911424e3c7b7389d628281fa685fd1f4ff37f83bdc16d70`.
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
  controles admitidos por esse gate. A candidata `794d922` iniciou NATS, Redis
  e o Job de migration, mas o Job não marcou conclusão em 600 segundos. O
  rollback de primeira release removeu workloads e Services, restaurou a
  contenção e manteve `current_release` ausente.
  `blindou-edge` está em gate `connector-only` e contém somente os três objetos
  permitidos do Tunnel: um Deployment com um Pod Ready, ServiceAccount e Secret
  exclusivos. Não existe Service, PVC, release Blindou corrente nem outro
  workload de aplicação nesses namespaces.
- O audit log do Kubernetes está ativo em nível `Metadata`, sem corpos de
  Secrets e com limites de 14 dias, cinco arquivos e 50 MiB por arquivo.
- Pixel/CIA e SaferWPP não estão implantados e não receberão workloads nesse
  host. A capacidade livre foi reservada ao Blindou; `apiwpp` permanece.

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
- O database vazio `blindou` foi criado com quatro logins sem privilégios
  administrativos e papéis separados para migration, runtime, redirector e
  conector ML. Conexões do CIDR K3s exigem `hostssl`, certificado de cliente
  confiável e SCRAM; nenhuma migration foi executada.
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
  aplicação antes da primeira migration concluída. Ainda exige novo SHA e nova
  candidata Blindou.

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
