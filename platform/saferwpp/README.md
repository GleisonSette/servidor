# Fundação declarativa do SaferWPP

Este diretório descreve a fundação exclusiva do SaferWPP sem aplicá-la ao
servidor. O estado vivo continua com APIWPP ativo e `saferwpp-lab` vazio.

- `foundation.yaml` é o contrato autoritativo de identidade, capacidade,
  PostgreSQL, backup, monitoramento e ownership.
- `00-platform-namespaces.yaml` e `10-platform-budgets.yaml` reservam fronteiras
  separadas para Keycloak e Control Plane; não contêm workloads ou Secrets.
- `postgresql/` contém fragmentos reproduzíveis para o segundo cluster
  PostgreSQL 18, seus limites, pgBackRest, exporter, métricas e alertas.
- `backup-preflight.schema.json` define a evidência obrigatória de backup e
  restore que deve existir antes do banco e antes de qualquer rollout. Na fase
  `foundation`, `postMigrationRestore` é nulo. Na fase `rollout`, a restauração
  isolada precisa comprovar papéis, grants e RLS por `rolesVerified`,
  `grantsVerified` e `rlsVerified` verdadeiros.

Os arquivos não incluem certificados, senhas, chaves R2 ou DSNs. O procedimento
e o rollback estão em `runbooks/saferwpp-foundation.md`. Nenhum arquivo deste
diretório autoriza acesso ao host, suspensão do APIWPP ou mudança no Blindou.
Os três namespaces são membros inativos do slot alternável e somente podem
receber workloads após reserva root-only conforme `runbooks/secondary-slot.md`.
