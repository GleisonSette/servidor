# Base declarativa do laboratório

Este diretório contém somente controles compartilhados. Workloads e segredos de
`apiwpp`, Pixel/CIA e SaferWPP permanecem em seus próprios repositórios.

## Conteúdo

- `base/`: espaços de projeto, cotas, limites, políticas de rede e admissão.
- `k3s/`: política de auditoria e fragmento de configuração do K3s.

## Aplicação

Antes de aplicar, executar a validação descrita em
`runbooks/aplicar-base-plataforma.md`. A ordem é:

1. validar os manifests no servidor;
2. aplicar `platform/base`;
3. confirmar que os namespaces continuam sem workloads e sem serviços;
4. instalar a política de auditoria e o fragmento K3s;
5. reiniciar o K3s em janela controlada e validar o nó e o `apiwpp`.

Não há credenciais, kubeconfig ou material privado neste diretório.
