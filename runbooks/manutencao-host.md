# Manutenção controlada do host

## Sequência

1. Registrar pacotes e versões antes da mudança.
2. Confirmar pgBackRest local/R2, arquivamento WAL e espaço livre.
3. Criar backup consistente do K3s.
4. Simular a atualização e abortar se houver remoções inesperadas.
5. Aplicar atualizações com saída registrada sem segredos.
6. Reiniciar somente serviços afetados; reiniciar o host apenas quando exigido.
7. Reiniciar explicitamente serviços dependentes que tenham parado com
   PostgreSQL ou K3s e validar UFW, SSH, WireGuard, PostgreSQL, K3s, `apiwpp`,
   exporters, gateway privado, timers e portas expostas.
8. Atualizar a memória canônica com versões e evidências.

## Rollback

- Pacotes: identificar a versão anterior disponível antes de downgrade; não
  executar downgrade automático de PostgreSQL.
- PostgreSQL: restauração por pgBackRest somente após diagnóstico e autorização.
- K3s: restaurar backup consistente somente em recuperação autorizada.
- Configuração: preservar uma cópia root-only de cada arquivo substituído.
