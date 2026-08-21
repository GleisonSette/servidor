# Índice canônico da plataforma local

metadata:
  canon_id: canon-indice-canonico
  source_path: memory/canon/index.md
  generated_from: decisão do usuário e auditoria do servidor em 2026-08-15
  updated_at: 2026-08-20
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
- Somente `apiwpp` está implantado; Pixel e SaferWPP ainda não estão no cluster.
- Os quatro repositórios de aplicação possuem guia obrigatório de acesso ao
  servidor. `apiwpp` e Blindou têm controladores próprios instalados; Pixel e
  SaferWPP falham fechados para alterações.
- O servidor preserva o serviço `apiwpp`; toda a capacidade restante foi
  reservada ao Blindou. Pixel/CIA e SaferWPP não recebem novos workloads.
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
- `blindou.com` foi removido do projeto Pages e `app.blindou.com` foi associado,
  aguardando a primeira release válida.
- O contrato GHCR privado e o fluxo fechado de credencial `read:packages` estão
  preparados. O controlador instalado ainda não foi atualizado e nenhuma
  credencial GHCR foi criada ou transferida.
- O build foi decidido em D015: runner efêmero hospedado pelo GitHub, com o
  workflow manual preparado no commit Blindou
  `08c35204f4f4d67df8e8065a516efb414d1166d2`; ainda não houve `push`, execução
  ou pacote publicado.
- A próxima ação é ativar a credencial GHCR e pausar a produção/previews
  automáticos do Pages antes de publicar/executar o workflow sob autorizações
  próprias. UAZAPI, canal de alertas e os demais Secrets ainda precedem a
  primeira release assinada;
  `blindou-production` permanece bloqueado.
- O receptor aprovado em D005 é `gleisonsette@gmail.com`; provedor, credencial
  autenticada e teste de entrega ainda bloqueiam a primeira release operacional.

## Precedência

Decisão explícita atual do usuário vence. Runtime verificado vence a memória ao
descrever o presente. O canon vigente orienta o alvo. O índice BM25 é apenas um
mecanismo de recuperação e nunca substitui a fonte canônica.
