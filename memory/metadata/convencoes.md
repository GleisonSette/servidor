# Convenções da memória

## Identificadores

- `canon_id`: `canon-<assunto>`;
- `source_id`: letras minúsculas, números e hífens;
- `chunk_id`: `<source-id>-canon-NNN`;
- decisão: `DNNN`, estável e nunca reutilizada.

## Metadata mínima

Cada canon contém `canon_id`, `source_path`, `generated_from`, `updated_at` e
`status`.

## Precedência

Decisão atual do usuário > runtime para descrever o presente > canon para
orientar o alvo > pesquisa externa > índice derivado.

## Formato

Markdown e JSON usam UTF-8 sem BOM e LF. Histórico é append-only. Segredos e
dados pessoais não são fontes indexáveis.
