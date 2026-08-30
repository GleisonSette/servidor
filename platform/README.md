# Base declarativa da plataforma local

Este diretório contém somente controles compartilhados. Workloads e segredos de
`apiwpp`, Pixel/CIA, SaferWPP e Blindou permanecem em seus próprios
repositórios.

## Conteúdo

- `base/`: espaços de projeto, cotas, limites, políticas de rede e admissão.
- `blindou/`: namespaces exclusivos que nascem vazios, em quarentena e com o
  gate de deploy bloqueado.
- `blindou-data/`: quarentena independente do futuro PostgreSQL dedicado do
  Blindou; nenhum PVC, Secret ou workload é criado pelo pacote base.
- `saferwpp/`: contrato ainda não aplicado do PostgreSQL, backup,
  observabilidade, quota e dependências exclusivas do laboratório SaferWPP.
- `secondary-slot/`: fonte de verdade, admissão e alertas da exclusão mútua
  entre APIWPP e SaferWPP; sua aplicação exige janela própria.
- `k3s/`: política de auditoria e fragmento de configuração do K3s.
- `security/`: contrato da contenção temporária UFW/Kubernetes e de sua
  expiração no cutover Vultr. Ele não contém segredos.

## Aplicação

Antes de aplicar, executar a validação descrita em
`runbooks/aplicar-base-plataforma.md`. A ordem é:

1. validar os manifests no servidor;
2. aplicar `platform/base` para os espaços compartilhados;
3. confirmar que os namespaces continuam sem workloads e sem serviços;
4. instalar a política de auditoria e o fragmento K3s;
5. reiniciar o K3s em janela controlada e validar o nó e o `apiwpp`.

Os namespaces `blindou-production` e `blindou-edge` não pertencem mais ao
`platform/base`: o controlador restrito os aplica por `platform/blindou`,
sempre vazios, com quota zero e gate `blocked`. O procedimento e o rollback
estão em `runbooks/blindou-plataforma.md`. Nenhum workload pode ser implantado
enquanto os gates externos não forem comprovados e promovidos separadamente.

A fundação SaferWPP possui procedimento próprio em
`runbooks/saferwpp-foundation.md`. Ela não integra o `platform/base` e não pode
ser aplicada por implicação: exige uma janela operacional autorizada e provas
de que APIWPP e Blindou não foram alterados.

O destino PostgreSQL dedicado do Blindou possui procedimento próprio em
`runbooks/blindou-plataforma.md`. O bootstrap instala somente o controlador e
a quarentena vazia; a prova direta do GHCR não altera objetos Kubernetes.
Durante a exceção D031/D064, o host pode executar somente a derivação OCI e o
scan dessa imagem em workspace não privilegiado e limitado. A publicação
continua pertencendo à estação; nenhuma credencial de escrita entra no host.

O slot alternável possui procedimento próprio em `runbooks/secondary-slot.md`.
O bootstrap instala seu controlador, mas somente a operação fechada de
inicialização aplica a admissão e publica o primeiro atestado.

Não há credenciais, kubeconfig ou material privado neste diretório.
