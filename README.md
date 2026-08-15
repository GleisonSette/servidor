# Servidor local compartilhado

Infraestrutura declarativa e memória operacional do laboratório K3s usado por
três projetos controlados pelo mesmo administrador:

1. `apiwpp`;
2. Pixel/CIA;
3. SaferWPP.

O repositório não contém segredos nem código das aplicações. O ponto de entrada
para continuidade entre sessões é `memory/canon/index.md`.

## Estrutura

- `memory/`: memória canônica, histórico e índice BM25;
- `platform/`: namespaces e controles compartilhados do K3s;
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
