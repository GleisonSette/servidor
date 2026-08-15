# Acesso e segredos

- Uma chave SSH identifica o administrador e o dispositivo. Não criar uma chave
  SSH por projeto para simular hospedagem compartilhada.
- O K3s isola projetos por namespace, ServiceAccount, RBAC, rede, cotas e dados.
- Chaves de assinatura de release são independentes por projeto e não concedem
  shell no host.
- SSH e API Kubernetes permanecem limitados ao PC administrativo; banco,
  métricas e workloads não são publicados na LAN.
- Segredos vivem no gerenciador operacional adequado e nunca neste repositório,
  RAG, commit, log ou comando exibido.

## Guias obrigatórios por projeto

- apiwpp: `C:\github\cintia\apiwpp\README-SERVIDOR-LOCAL.md`;
- Pixel/CIA: `C:\github\cia\README-SERVIDOR-LOCAL.md`;
- SaferWPP: `C:\github\saferdock\saferwpp\README-SERVIDOR-LOCAL.md`.

O Codex de aplicação usa somente o controlador root-owned do próprio projeto.
Se ele não existir ou não oferecer a operação, a ação permanece bloqueada e
deve ser encaminhada ao repositório `servidor`. Não usar senha administrativa,
`sudo` genérico, kubeconfig root ou controlador de outro projeto como atalho.
