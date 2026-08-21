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
- Credenciais externas preparadas antes do runtime ficam em diretórios
  root-only por provider e finalidade. Sua transferência usa `stdin` fechado;
  o controlador valida o provider antes de instalar e nunca aceita o segredo em
  argumento. O Secret Kubernetes só nasce em uma fase de release autorizada.
- A credencial GHCR do servidor é exclusiva para download e deve apresentar
  exatamente o escopo `read:packages`. Token de publicação, `repo`, workflow ou
  administração nunca entra no host.

## Guias obrigatórios por projeto

- apiwpp: `C:\github\cintia\apiwpp\README-SERVIDOR-LOCAL.md`;
- Pixel/CIA: `C:\github\cia\README-SERVIDOR-LOCAL.md`;
- SaferWPP: `C:\github\saferdock\saferwpp\README-SERVIDOR-LOCAL.md`.

O Codex de aplicação usa somente o controlador root-owned do próprio projeto.
Se ele não existir ou não oferecer a operação, a ação permanece bloqueada e
deve ser encaminhada ao repositório `servidor`. Não usar senha administrativa,
`sudo` genérico, kubeconfig root ou controlador de outro projeto como atalho.
