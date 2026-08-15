# Plano de implementação da plataforma

metadata:
  canon_id: canon-plano-implementacao
  source_path: memory/canon/plano-implementacao.md
  generated_from: plano aprovado pelo usuário em 2026-08-15
  updated_at: 2026-08-15
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

## Fase 3 - SaferWPP lab

Status: Fase 3.1 em andamento; auditoria inicial concluída parcialmente e
nenhuma mudança feita no servidor.

Controle transversal concluído em 2026-08-15: os três repositórios de aplicação
possuem guia obrigatório de acesso segregado. O apiwpp já usa controladores
restritos; o SaferWPP e o Pixel não podem alterar o host até seus controladores
próprios serem implementados nas respectivas fases. Isso não muda a ordem: a
Fase 3.1 continua sendo a próxima ação canônica.

Este é o próximo projeto depois das Fases 0 a 2.

Já confirmado na Fase 3.1:

- base de código `e8a0427` limpa, seguida apenas pelo commit documental
  `d8fce28`;
- chart limitado a Kubernetes 1.34, enquanto o laboratório usa K3s 1.36.2;
- schema sem ambiente `lab` e quatro imagens/workloads separados;
- dependências reais de dados, mensageria, identidade e armazenamento;
- observabilidade padrão do chart precisa ser adaptada ao stack instalado.

Próxima ação exata para concluir a Fase 3.1:

- terminar o inventário de migrations, contratos de startup e gates sem alterar
  o servidor;
- fechar o perfil `lab` para K3s 1.36, namespace `saferwpp-lab`, uma réplica,
  Services ClusterIP e acesso inicial por port-forward;
- definir dependências, sequência, capacidade, riscos, critérios de aceite,
  rollback e o contrato mínimo do futuro `saferwpp-deployctl`;
- apresentar o diff previsto e somente então iniciar a Fase 3.2 quando o
  usuário pedir o próximo passo.

Objetivos:

- criar valores Helm `lab` para K3s 1.36, uma réplica e ingress desligado;
- construir, escanear, assinar e importar quatro imagens por digest;
- provisionar banco/papéis, PgBouncer, NATS, Keycloak, MinIO e ClamAV reais de
  laboratório;
- implantar API, worker, relay e web com políticas mínimas;
- validar login, migrations, health, métricas e rollback por port-forward;
- manter UAZAPI/R2 externos como gates explícitos da Fase 4 do produto.

## Fase 4 - Pixel/CIA lab

Status: pendente.

Objetivos:

- preservar e consolidar o trabalho Pixel ainda não commitado;
- tratar Pixel como SDK + collector + worker + Control Plane, não só `pixel.js`;
- criar imagens OCI e manifests K3s;
- provisionar PostgreSQL, KMS mTLS e NATS TLS reais de laboratório;
- iniciar em modo interno/shadow com ingestão pública desligada;
- validar durabilidade antes de `202`, replay, DLQ, retenção e rollback.

## Fase 5 - Entrada externa controlada

Status: pendente.

Objetivos:

- escolher borda Cloudflare ou VM pública já autorizada;
- encaminhar apenas webhook/collector por WireGuard ou mTLS;
- aplicar TLS, WAF, rate limit, origem restrita e monitoramento externo;
- manter SSH, 6443, PostgreSQL e métricas privados.

## Fase 6 - Ensaio combinado e operação

Status: pendente.

Objetivos:

- testar reboot, queda de dependência, backup/restore e rollback dos três
  projetos;
- executar degraus de carga com margem e monitorar HDD, memória, swap e rede;
- realizar soak de 24 horas no maior degrau aprovado;
- registrar limites observados e critérios para SSD, NIC Gigabit e nobreak.
