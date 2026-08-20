# Estado atual da plataforma local

metadata:
  canon_id: canon-estado-atual
  source_path: memory/canon/estado-atual.md
  generated_from: auditoria SSH, runtime K3s, Prometheus e repositórios locais
  updated_at: 2026-08-20
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
- IPv6 público observado em `enp2s0`, com prefixo `/64` e rota padrão pela ONT.
- PC administrativo: `192.168.100.57`.
- WireGuard `wg-apiwpp`: `10.203.0.2/30`.

## Segurança e exposição

- Gateway/ONT observado em `192.168.100.1`: Huawei HG8145V5, perfil `OI2`.
- O servidor e a estação administrativa ainda compartilham
  `192.168.100.0/24`; a rota padrão do host aponta diretamente para a ONT.
- Não existe firewall externo entre servidor e residência. A camada de host da
  exceção temporária está ativa: UFW bloqueia redes privadas e entrada lateral,
  e o IPv6 da `enp2s0` está desabilitado. A fundação Kubernetes interna do
  Blindou está provisionada e bloqueada; Cloudflare, Secrets, migrations e
  workloads ainda não foram aplicados, portanto nenhum deploy comercial do
  Blindou é autorizado no estado atual.

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
- `blindou-deployctl` está instalado como root a partir do commit `6a21fb8`. O
  SHA-256 instalado `681c8723d77c3cf18c03ca3e96d21d02a37d8fa92acb50e1a6be8ad7e00dcc8e`
  coincide com o staging versionado. A interface sudo sem senha continua
  restrita às operações fechadas do controlador; rollbacks destrutivos exigem
  autenticação humana.
- `blindou-hostctl` corrigido foi instalado como root em 2026-08-19. A primeira
  aplicação foi revertida depois que o gate detectou falha de DNS; a segunda
  aplicação passou e deixou a contenção ativa. O controlador confirmou cada
  marcador UFW e faz rollback automático se instalação ou verificação falhar.
- O inbox corrigido do commit `7cceebf` está validado em
  `/home/apiadmin/blindou-platform-bootstrap-7cceebf`; ele é somente staging no
  diretório do usuário. O controlador instalado possui o mesmo SHA-256 da fonte
  versionada.
- Não havia processo nem unit systemd `cloudflared` no host na conferência
  final pós-ativação de 2026-08-19.

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
- `blindou-production` e `blindou-edge` existem vazios, com Pod Security
  `restricted`, default deny, quota de quarentena e gate `blocked`. Ambos
  registraram zero objetos operacionais; testes negativos recusaram Pod e
  Service público. Não existe release Blindou corrente nem `cloudflared` no
  host ou no cluster.
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
  para os dois namespaces, preservando o significado de bloqueados.
- Prometheus, Node Exporter e PostgreSQL Exporter estão `up`, com três targets
  saudáveis e zero alertas ativos.
- O coletor `stat_bgwriter`, incompatível com PostgreSQL 18 no exporter 0.15,
  foi desabilitado. Exporter e gateway privado agora acompanham o restart de
  PostgreSQL e K3s por `PartOf`.
- Ainda não existe destino externo para notificações de alerta.

## Manutenção

- Os 15 pacotes identificados foram atualizados, incluindo PostgreSQL 18.6,
  libpq, pgBackRest 2.59, linux-firmware, Kerberos e Apport.
- Não há pacote atualizável restante nem reboot requerido após a manutenção.
- K3s, PostgreSQL, WireGuard, gateway privado, observabilidade e `apiwpp`
  passaram na verificação final; não há unit systemd falha.
- Depois da fundação Blindou, `blindou-hostctl verify`,
  `apiwpp-deployctl verify`, os três verificadores do `blindou-deployctl`, a
  recuperação do backup e a coleta Prometheus passaram; zero unit systemd
  falhou e nenhum arquivo plaintext de backup permaneceu em `/var/tmp`.
- A contenção temporária passou em DNS, HTTPS pública, bloqueio da ONT, K3s,
  `apiwpp` e reaplicação idempotente. IPv6 da `enp2s0` está desabilitado.
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
