# Fundação exclusiva do SaferWPP

## Estado e limite

Os artefatos estão implementados apenas neste repositório. Eles não foram
aplicados ao servidor. O APIWPP continua ativo, `saferwpp-lab` continua vazio e
nenhum recurso Blindou pode ser alterado por este procedimento.

O contrato autoritativo é `platform/saferwpp/foundation.yaml`. Ele fixa o
segundo cluster PostgreSQL 18 `saferwpp_lab` na porta 55432, dois repositórios
pgBackRest, exporter em loopback, quota do produto e orçamentos exclusivos de
Keycloak e Control Plane.

## Pré-condições para uma futura janela operacional

1. obter autorização específica para alterar o host e o K3s;
2. validar identidade do host, K3s 1.36.2, estado do APIWPP e saúde do Blindou;
3. comprovar backup atual do K3s e do cluster PostgreSQL compartilhado;
4. validar que 55432 e 9188 estão livres e não publicadas na LAN;
5. preparar, fora do Git, CA/certificado de servidor, CA/certificados de
   cliente, senhas SCRAM, endpoint/credenciais R2 e cifras dos dois repositórios;
6. comprovar ownership e modos dos materiais root-only antes de iniciar;
7. executar `operations/remote/verify-saferwpp-foundation-artifacts.py` no
   bundle transportado e comparar seu hash com o commit aprovado.

Sem qualquer item, a operação falha antes de criar o cluster ou um namespace.

## Ordem de materialização

Uma operação root fechada e auditada deve executar, nessa ordem:

1. capturar o baseline de serviços, listeners, consumo, arquivos de
   configuração, namespaces, quotas e saúde Blindou/APIWPP;
2. criar diretórios exclusivos com ownership e modos mínimos;
3. criar o cluster vazio `18/saferwpp_lab` sem iniciar, instalar o include
   PostgreSQL, HBA, TLS, slice e drop-in e validar a configuração;
4. instalar a configuração pgBackRest e o cofre externo, criar a stanza e
   validar separadamente repo1/local e repo2/R2;
5. iniciar somente o cluster exclusivo e provar porta 55432, teto 24, reservas,
   TLS e ausência de listener público;
6. produzir backup completo nos dois repositórios e restaurar o cluster-base em
   destino isolado; publicar evidência válida conforme
   `saferwpp.backup-preflight/v2`;
7. somente após o restore-base, instalar exporter, coletor textfile, regras de
   alerta e timers de backup;
8. aplicar a nova quota de `saferwpp-lab` e criar vazios
   `saferdock-identity`/`saferdock-platform` com seus controles exclusivos;
9. confirmar zero Pod, Service e Secret novo nesses três namespaces;
10. repetir as provas de saúde e imutabilidade do Blindou e do APIWPP.

Criar `saferwpp_lab`, papéis de aplicação, Keycloak, Control Plane ou qualquer
workload não pertence a esta etapa. A porta 5432, o unit
`postgresql@18-main.service`, os dados e o backup existentes não são tocados.

Na futura fase `rollout`, a evidência pós-migration somente é válida quando o
restore isolado comprovar o conjunto de migrations e declarar
`rolesVerified`, `grantsVerified` e `rlsVerified` como verdadeiros. A fase
`foundation` deve manter `postMigrationRestore` nulo; ela não pode antecipar
uma prova de banco ainda inexistente.

## Verificação

- `postgresql@18-saferwpp_lab.service` ativo dentro de
  `saferwpp-postgresql.slice`;
- somente 192.168.100.59/127.0.0.1 na porta 55432, sem exposição pela LAN;
- `max_connections=24`, reservas 3+2 e memória/CPU iguais ao contrato;
- HBA aceita apenas identidades SaferWPP por TLS, SCRAM e certificado;
- `pgbackrest check`, backup e restore passam nos repositórios 1 e 2;
- a evidência `foundation` recusa restore pós-migration e a evidência `rollout`
  recusa ausência ou valor falso em `rolesVerified`, `grantsVerified` e
  `rlsVerified`;
- exporter responde apenas em `127.0.0.1:9188` e usa uma conexão;
- Prometheus coleta exporter e métricas textfile, avalia as regras sintéticas e
  as deixa disponíveis ao pipeline interno sem depender do WhatsApp; entrega a
  receptor externo continua um gate separado;
- quotas e NetworkPolicies coincidem com os manifests e os namespaces seguem
  vazios;
- APIWPP e Blindou mantêm releases, recursos, listeners e saúde do baseline.

## Rollback

Falha antes de iniciar o novo cluster remove somente arquivos e diretórios
novos cuja ausência constava no baseline. Falha depois da inicialização para o
unit exclusivo, timers, exporter e coleta, preserva o diretório de dados e os
backups para diagnóstico e restaura a quota anterior pelo manifesto capturado.

Rollback nunca apaga o cluster, stanza, backup, evidência ou certificado sem
autorização destrutiva própria. Ele desabilita apenas units SaferWPP, remove
listeners 55432/9188, restaura a configuração Prometheus anterior de seu backup
e reaplica o estado Kubernetes capturado. Depois, repete todas as provas de
APIWPP e Blindou. Estado parcial ou divergente permanece bloqueado para deploy e
gera alerta operacional.
