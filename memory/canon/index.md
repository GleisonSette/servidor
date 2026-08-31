# Índice canônico da plataforma local

metadata:
  canon_id: canon-indice-canonico
  source_path: memory/canon/index.md
  generated_from: decisão do usuário e auditoria do servidor em 2026-08-15
  updated_at: 2026-08-31
  status: canonical

## Regra de entrada

Este é o primeiro documento da memória. Use a busca BM25 para localizar os
trechos relevantes e depois abra a fonte canônica indicada. Não carregue todo o
corpus por padrão.

## Roteamento

- Situação do host, versões, portas, capacidade, workloads, backups ou riscos:
  `memory/canon/estado-atual.md`.
- Namespaces, isolamento, acesso, dados, rede, deploy ou topologia desejada:
  `memory/canon/arquitetura-plataforma.md`.
- Perguntas como "qual é o próximo passo", ordem, gate, aceite ou rollback:
  `memory/canon/plano-implementacao.md`.
- O que já foi executado, quando, evidência e resultado:
  `memory/canon/historico-execucao.md`.
- Decisões confirmadas, suposições e escolhas ainda necessárias:
  `memory/canon/decisoes.md`.

## Estado resumido

- Auditoria inicial concluída em 2026-08-15.
- Fases 0, 1 e 2 concluídas e verificadas em 2026-08-15.
- Os namespaces vazios `cia-pixel-lab` e `saferwpp-lab` estão protegidos por
  Pod Security, cotas, limites, negação de rede e admissão privada.
- PostgreSQL 18.6, pgBackRest 2.59 e K3s v1.36.2 estão saudáveis; audit log do
  Kubernetes está ativo e há backup consistente do cluster com checksum.
- Blindou possui runtime implantado. O slot APIWPP/SaferWPP está sem ocupante;
  DRE possui fundação, Secrets e release validada, mas produção continua sem
  runtime. Pixel e SaferWPP permanecem sem runtime.
- Os cinco projetos possuem fronteiras documentadas. APIWPP, Blindou e DRE têm
  controladores próprios instalados; Pixel e SaferWPP falham fechados para
  alterações.
- D022 mantém o Blindou sempre ativo e reserva a capacidade residual a um slot
  alternável entre APIWPP e SaferWPP, com exclusão mútua. Em 2026-08-31,
  `secondary-slotctl verify` aprovou a geração 2 com ocupante `none` e zero
  workload nos dois membros. Fundação e controladores SaferWPP continuam
  ausentes; Pixel/CIA não recebe novos workloads.
- D024 está implantada. `blindou_redirect_login` usa o grupo mínimo
  `blindou_redirector`, sem `BYPASSRLS`; a migration `0012` está registrada e a
  release `d5766d87a0cf5ba1d5827fa35e8e6a0cac801185` está ativa. O link Amazon
  em `go.guiadoconsumo.com` redirecionou preservando o identificador de
  afiliado, registrou Analytics e códigos desconhecidos continuaram em 404.
  Pagar.me permaneceu ativo; UAZAPI e Resend continuam adiados.
- D028 prepara o PostgreSQL 18 exclusivo em `blindou-data`. I1 foi aprovada
  para publicar a imagem/bundle, instalar somente `blindou-datactl` e executar
  `pull-proof` direto pelo cofre GHCR. A prova mantém gate `blocked` e zero
  Secret, PVC, Job, Pod ou workload; o banco nativo continua autoridade e I2
  permanece bloqueada.
- D031, alinhada à D064 do Blindou, autoriza temporariamente apenas o build e o
  scan da imagem PostgreSQL dedicada no host não privilegiado até o usuário
  pedir retorno ao GitHub Actions. A estação conserva toda autoridade GHCR de
  escrita; o bundle aceita somente as linhas imutáveis Trivy 0.67.2 normal ou
  Trivy 0.70.0 com recibo D064; `foundation`, dados, K3s e I2 permanecem fora
  do escopo.
- D029 definiu o DRE fora do slot, e D030 autorizou seu helper de bootstrap
  fechado. Fundação, controlador schema 2, identidade, cinco Secrets sem FCM,
  timers, alertas e métricas estão instalados. A release assinada
  `dre-20260831T202100Z-f6b06765ff61` passou em `dre-validation`: nove
  migrations, acessos, bootstrap, E2E e reinícios dos três componentes foram
  aprovados, e namespace/PVC/PV temporários foram removidos. Produção continua
  `release=none`, `gate=secrets-only`, sem PVC ou workload. D032 mantém a
  coordenação do token da ponte; migration/deploy, backup/restore de produção,
  HTTPS, contas, dispositivos e saldo inicial continuam gates independentes.
- D036 está executada: `make release-check` e `make e2e` passaram no executor
  rootless sintético do servidor, sem daemon ou acesso ao K3s, e os recursos
  efêmeros foram descartados.
- A execução I1 publicou o digest PostgreSQL final, instalou somente o
  `blindou-datactl`/quarentena e comprovou uma imagem, 15 blobs e 157.256.746
  bytes. O estado permanece `blocked`, sem objeto operacional, aguardando
  confirmação humana; `foundation` e I2 continuam bloqueados.
- D026 prepara, ainda sem instalação no host, a ativação separada da Shopee
  Open API. A release compatível entra com a flag desligada; depois o
  controlador gera a chave interna root-only e só conclui após backend e 16
  workers passarem nas probes. Credenciais do tenant entram pelo painel, não
  pelo servidor administrativo.
- A auditoria viva de 2026-08-26 aprovou somente a continuidade do planejamento
  de hardware. O PostgreSQL real possui teto 50 e pico de 48 backends, por isso
  reprovou o orçamento SaferWPP de dez conexões runtime mais duas de migration.
  D023 escolheu um segundo cluster PostgreSQL exclusivo do SaferWPP na porta
  55432, com teto 24, recursos, backup e exporter próprios. Em 2026-08-26, o
  repositório passou a declarar cluster, stanza local/R2, restore v2, exporter,
  alertas, quota 2 CPU/4Gi e orçamentos exclusivos de Keycloak/Control Plane. Nada
  foi aplicado: APIWPP não foi suspenso e SaferWPP continua vazio.
- O firewall externo foi adiado. A primeira aplicação da contenção temporária
  foi revertida porque o gate detectou DNS bloqueado por ordenação de regras
  UFW preexistentes. O controlador corrigido foi instalado e a reaplicação
  passou em DNS, Internet, bloqueio da ONT, K3s, `apiwpp`, portas e
  idempotência. A contenção de host está ativa; ela não contém `root` e termina
  no cutover Vultr.
- A fundação interna da Fase 2D foi concluída em 2026-08-20:
  `blindou-deployctl` root-owned, `blindou-production` com gate `blocked` e
  `blindou-edge` com gate `connector-only`,
  database sem migrations, quatro logins isolados, TLS mais SCRAM, backup
  lógico criptografado recuperável e métricas Prometheus. O Tunnel
  `blindou-physical` está saudável com um único Pod e Secret exclusivos da
  EDGE; nenhum workload de aplicação, migration ou release foi aplicado.
- Cloudflare for SaaS está ativo para `blindou.com`; o API token mínimo foi
  validado e está em cofre root-only fora do Kubernetes. A origem de fallback
  `domains.blindou.com` está ativa, nenhum hostname de cliente foi criado e a
  cota operacional da aplicação permanece em 90.
- `blindou.com` foi removido do projeto Pages. `app.blindou.com` publicou o SHA
  `83e7f387` e serve o painel; a API compatível ainda não está Ready.
- A credencial GHCR `read:packages` está validada em cofre root-only. O
  controlador instalado aceita as quatro imagens privadas; a candidata
  `0ba8384` passou nos gates, no scan fechado, na validação do bundle no cache e
  na prova integral viva do host. A prova confirmou quatro imagens, 24 blobs e
  111.683.519 bytes sem criar Secret, migration ou workload.
- Em 2026-08-25, todos os seis orquestradores que reinstalam o controlador do
  Blindou passaram a transportar o conjunto completo de fontes exigido pelo
  bootstrap; o gate offline impede regressão desse contrato.
- A primeira tentativa de ativação Pagar.me preservou o journal porque uma
  checagem redundante exigia `curl` na imagem mínima. A correção usa as probes
  `/ready` observadas pelo rollout; a repetição recuperou o journal e concluiu a
  ativação na release `ab15a31`, com nove migrations e checkout disponível.
- O workflow `32442604845` executou o SHA Blindou `83e7f387` duas vezes:
  fmt/check/Clippy passaram, mas `rust-lld` caiu com `Bus error` ao ligar testes
  grandes diferentes. O job de imagens foi pulado e não publicou candidatas.
- Por D016, o Pages permanece automático: o `push` autorizado pode publicar o
  painel enquanto o workflow de imagens é acompanhado.
- A D019 permitiu a primeira release sem provedores. A release
  `8e17210e34767935158ba5c8b863b48724297a93` passou no workflow
  `32645928340`, no gate RLS de menor privilégio, nos scans, na prova integral
  do host e no rollout. O estado vivo possui oito migrations,
  `current_release=8e17210`, aplicação e EDGE em `passed`, Tunnel e R2
  saudáveis e backup `blindou-20260823T152218Z` confirmado offsite. A janela
  protegida criou `gleisonsette@gmail.com` como `super_admin` e o login real
  passou pela API pública sem expor tokens. Em 2026-08-24, a UI foi aprovada e
  a D020 definiu Pagar.me, domínio personalizado, marketplaces e UAZAPI/Resend
  como nova ordem. A secret key Pagar.me live já foi validada e guardada no
  cofre root-only do host, o webhook HTTPS foi cadastrado após rotação do
  segredo exposto e os sete planos mensais `prepaid` com descritor `BLINDOU`
  passaram na verificação autenticada. Em 2026-08-25, a release `ab15a31`, o
  backup prévio, a migration `0009` e a ativação fechada passaram; o runtime
  Pagar.me está ativo e UAZAPI/Resend permanecem ausentes. Nenhuma cobrança real
  foi criada na validação.

## Precedência

Decisão explícita atual do usuário vence. Runtime verificado vence a memória ao
descrever o presente. O canon vigente orienta o alvo. O índice BM25 é apenas um
mecanismo de recuperação e nunca substitui a fonte canônica.
