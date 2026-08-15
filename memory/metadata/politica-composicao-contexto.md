# Política de composição de contexto

## Objetivo

Responder e operar com o menor contexto suficiente, preservando rastreabilidade
e sem carregar toda a memória do laboratório.

## Sequência obrigatória

1. Ler `memory/canon/index.md`.
2. Classificar a pergunta: estado, arquitetura, plano, histórico ou decisão.
3. Executar `memory/tools/search-index.ps1` com a pergunta original.
4. Abrir no máximo três canons diretamente relevantes.
5. Para "qual é o próximo passo", abrir sempre plano e histórico.
6. Para saúde ou versão, conferir o runtime; memória não prova estado atual.
7. Para mudança, confirmar autorização e ler o runbook aplicável.
8. Depois da mudança, atualizar fonte canônica, histórico, plano e índice.

## Regras de recuperação

- Resultado BM25 aponta para a fonte; não é a resposta final.
- `estado-atual.md` registra a última observação, com data, e pode ficar obsoleto.
- `historico-execucao.md` é append-only.
- `plano-implementacao.md` define ordem e gates.
- `decisoes.md` impede resolver escolha material por suposição.
- Código, manifests e runtime atuais vencem a memória ao descrever o presente.

## Consultas frequentes

- "Qual é o próximo passo?": plano + histórico + decisões pendentes.
- "O que já foi feito?": histórico + estado atual.
- "Posso expor uma porta?": arquitetura + decisões + estado da rede.
- "Como implantar SaferWPP?": plano + arquitetura; depois abrir o repositório
  SaferWPP e sua memória obrigatória.
- "Como implantar Pixel?": plano + arquitetura; depois abrir as ADRs e o estado
  atual do repositório CIA.

## Segurança de contexto

Nunca indexar `.env`, chave, kubeconfig, certificado privado, token, senha,
conteúdo de Secret, payload de cliente ou log com PII. A memória guarda apenas
fingerprints, IDs técnicos, estados e caminhos não sensíveis quando necessários.
