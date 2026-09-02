# Servidor local compartilhado

Infraestrutura declarativa e memória operacional do servidor K3s usado por
cinco projetos controlados pelo mesmo administrador:

1. `apiwpp`;
2. Pixel/CIA;
3. SaferWPP;
4. Blindou, bloqueado para publicação até a instalação e validação da borda
   externa de contenção;
5. DRE familiar, com controlador, Secrets e PostgreSQL/PVC dedicados como
   projeto sempre ativo e independente; a release assinada está no cache e o
   primeiro deploy permanece revertido antes das migrations para diagnóstico
   fechado do pgBackRest.

O repositório não contém segredos nem código das aplicações. O ponto de entrada
para continuidade entre sessões é `memory/canon/index.md`.

## Estrutura

- `memory/`: memória canônica, histórico e índice BM25;
- `platform/`: namespaces e controles compartilhados do K3s;
- `platform/dre/`: fundação, admissão, RBAC e alertas do controlador DRE;
- `platform/security/`: contrato da barreira externa e seus gates;
- `operations/remote/`: rotinas operacionais versionadas e sem credenciais;
- `runbooks/`: manutenção, recuperação e validação;
- `scripts/`: verificações locais sem segredo.

## Consulta rápida da memória

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File memory\tools\search-index.ps1 `
  -Query "qual e o proximo passo" -Top 5
```

O resultado aponta para documentos canônicos. Abra somente os caminhos
retornados antes de agir.

## Licença

Distribuído sob a licença MIT. Consulte `LICENSE`.
