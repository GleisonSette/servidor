# Índice canônico da plataforma local

metadata:
  canon_id: canon-indice-canonico
  source_path: memory/canon/index.md
  generated_from: decisão do usuário e auditoria do servidor em 2026-08-15
  updated_at: 2026-08-19
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
  servidor. Somente o apiwpp tem controladores instalados; Pixel, SaferWPP e
  Blindou falham fechados para alterações até receberem controladores próprios.
- O servidor preserva o serviço `apiwpp`; toda a capacidade restante foi
  reservada ao Blindou. Pixel/CIA e SaferWPP não recebem novos workloads.
- O firewall externo foi adiado. A contenção temporária UFW/IPv6/Kubernetes e o
  namespace `blindou-edge` estão preparados, mas ainda não aplicados. Ela não
  contém `root` e termina no cutover Vultr.
- A próxima ação é o bootstrap humano do `blindou-hostctl`, aplicação e
  verificação do firewall temporário, preservando `apiwpp`. Nenhum workload
  Blindou foi aplicado e `blindou-deployctl` ainda não existe.
- O receptor externo de alertas permanece como decisão D005 e precisa ser
  resolvido antes da primeira release operacional do Blindou.

## Precedência

Decisão explícita atual do usuário vence. Runtime verificado vence a memória ao
descrever o presente. O canon vigente orienta o alvo. O índice BM25 é apenas um
mecanismo de recuperação e nunca substitui a fonte canônica.
