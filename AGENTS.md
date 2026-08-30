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
- Por decisões D018, D025 e D027, somente os helpers versionados
  `operations/Blindou.SudoBootstrap.psm1` e
  `operations/SecondarySlot.SudoBootstrap.psm1` podem carregar
  `KEY_SERVIDOR` do arquivo local ignorado `.env`. O primeiro continua restrito
  aos bootstraps fechados `blindou-hostctl`, `blindou-deployctl` e
  `blindou-datactl`; este último exige o conjunto `DataController`, staging e
  commit fixos e instala somente o controlador e a quarentena vazia. O segundo
  aceita exclusivamente a
  materialização autenticada de `secondary-slotctl`, no host, staging, commit e
  SHA-256 fixados pelo orquestrador versionado. O valor nunca pode ser aberto
  manualmente, impresso, registrado, indexado, persistido, colocado em argumento
  ou variável de ambiente; ele passa apenas pela memória do processo e por
  `stdin`. A permissão não alcança `sudo` genérico, rollback destrutivo,
  fundação ou controladores SaferWPP, outro host, projeto ou comando. O arquivo
  será retido até a entrada do primeiro cliente; nesse marco, ou diante de
  suspeita de exposição, lembrar o usuário de removê-lo e rotacionar a
  credencial.
- Preservar alterações do usuário nos repositórios irmãos. Mudança em outro
  repositório exige escopo explícito e commit separado.
- Por D026, a ativação da Shopee usa operação fechada posterior ao deploy da
  release compatível. O controlador gera somente a chave interna de cifra no
  cofre root-only; AppID e App Secret pertencem ao tenant e entram diretamente
  pelo painel Blindou. Pagar.me permanece ativo, e Mercado Livre, UAZAPI,
  Resend e 2FA não são ativados por essa operação.
- Exceção temporária D031, alinhada à D064 do Blindou: enquanto o usuário não
  solicitar o retorno ao GitHub Actions, somente a imagem PostgreSQL dedicada
  pode usar o host como executor efêmero sem privilégio. A derivação OCI e o
  scan rodam em workspace descartável de `apiadmin`, sob cgroup de 1 CPU/4 GiB,
  prioridade baixa e recusa de concorrência com Cargo/Rust; não instalam
  Docker/BuildKit, não usam `sudo`, K3s, banco, serviço ou segredo operacional.
  A credencial GHCR com escrita permanece exclusivamente na estação e publica
  os blobs por streaming; o host continua recebendo somente a credencial
  root-only de leitura nos controladores aprovados. A exceção termina quando o
  usuário pedir a volta ao GitHub Actions e não abrange outra imagem ou projeto.

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
- O Blindou permanece sempre ativo e seus recursos, releases, dados, segredos,
  quotas, borda e controladores não podem ser alterados para admitir outro
  projeto. APIWPP e SaferWPP compartilharão um slot alternável: somente um
  deles poderá manter workloads ativos por vez. A suspensão do APIWPP deve ser
  reversível e preservar namespace, objetos declarativos, Service, PVC, banco,
  migrations, backups, releases e gateway privado. Até que os controladores,
  gates de exclusão mútua e a capacidade medida estejam implementados e
  verificados, o estado atual permanece: APIWPP ativo e SaferWPP sem workloads.
  Pixel/CIA continua sem novos workloads. A contenção temporária do Blindou não
  contém `root` e termina obrigatoriamente na migração para Vultr.
- Um único nó, HDD, Fast Ethernet e energia residencial permanecem pontos
  únicos de falha. Isolamento externo reduz movimento lateral, mas não cria
  alta disponibilidade nem torna impossível explorar uma vulnerabilidade.
