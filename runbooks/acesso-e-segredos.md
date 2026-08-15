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
