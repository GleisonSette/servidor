# Plataforma local compartilhada

## Escopo

- Este repositório governa o servidor físico `192.168.100.59`, o cluster K3s
  local, a contenção temporária do Blindou e a infraestrutura compartilhada.
- Código e manifests exclusivos de `apiwpp`, Pixel/CIA, SaferWPP e Blindou
  permanecem nos respectivos repositórios. Não duplicar código de aplicação aqui.
- Segredos, kubeconfigs, chaves privadas, certificados privados, senhas e
  conteúdo de arquivos `.env` nunca entram neste repositório, memória, índice,
  log ou resposta.

## Autorização e segurança

- Diagnóstico, revisão, arquitetura e plano são somente leitura.
- Alterar host, cluster, rede, banco, backup, repositório de aplicação ou
  serviço externo exige pedido explícito do usuário.
- Antes de mudança no host: validar identidade do servidor, estado atual,
  backup aplicável, impacto, rollback e forma de verificar o resultado.
- Não expor SSH, Kubernetes API, PostgreSQL, métricas ou NodePort à internet.
- Não enfraquecer UFW, SSH, Pod Security, NetworkPolicy ou criptografia de
  Secrets para contornar falha.
- Por decisão D018 de 2026-08-22, somente o helper versionado
  `operations/Blindou.SudoBootstrap.psm1` pode carregar `KEY_SERVIDOR` do
  arquivo local ignorado `.env`. O valor nunca pode ser aberto manualmente,
  impresso, registrado, indexado, persistido, colocado em argumento ou variável
  de ambiente; ele passa apenas pela memória do processo e por `stdin` para os
  bootstraps fechados do `blindou-hostctl` e do `blindou-deployctl` no host
  aprovado. A permissão não alcança `sudo` genérico, rollback destrutivo, outro
  host, projeto ou comando. Depois do trabalho, lembrar o usuário de apagar o
  arquivo temporário.
- Preservar alterações do usuário nos repositórios irmãos. Mudança em outro
  repositório exige escopo explícito e commit separado.

## Memória RAG obrigatória

Antes de planejar, diagnosticar ou implementar:

1. ler `memory/canon/index.md`;
2. ler `memory/metadata/politica-composicao-contexto.md`;
3. executar `memory/tools/search-index.ps1` com a pergunta da tarefa;
4. abrir somente os canons apontados pela busca e os documentos obrigatórios
   indicados pelo índice;
5. conferir o runtime quando a pergunta envolver estado atual;
6. nunca usar o índice derivado como fonte de verdade independente.

Depois de qualquer mudança operacional ou decisão:

1. atualizar o canon afetado;
2. acrescentar uma entrada em `memory/canon/historico-execucao.md`;
3. atualizar o status em `memory/canon/plano-implementacao.md`;
4. executar `memory/tools/rebuild-index.ps1`;
5. executar `memory/tools/verify-index.ps1`;
6. executar `memory/tools/test-retrieval.ps1`;
7. revisar o diff completo.

## Padrão operacional

- Mudanças devem ser declarativas, reproduzíveis, idempotentes e possuir
  verificação e rollback.
- Imagens são imutáveis e identificadas por digest. Deploy de aplicação usa
  identidade própria, assinatura de release e privilégio mínimo.
- Cada projeto possui namespace, ServiceAccounts, Secrets, políticas de rede,
  quotas, banco/papéis e ciclo de deploy próprios.
- SSH identifica o administrador; não é o mecanismo de isolamento entre
  projetos.
- O host preserva somente o serviço `apiwpp` existente e reserva toda a
  capacidade restante ao Blindou. Pixel/CIA e SaferWPP não recebem novos
  workloads. O Blindou só pode se tornar operacional depois de passar o gate
  temporário de UFW/IPv6/Kubernetes/Cloudflare. Esse gate não contém `root` e
  termina obrigatoriamente na migração para Vultr.
- Um único nó, HDD, Fast Ethernet e energia residencial permanecem pontos
  únicos de falha. Isolamento externo reduz movimento lateral, mas não cria
  alta disponibilidade nem torna impossível explorar uma vulnerabilidade.
