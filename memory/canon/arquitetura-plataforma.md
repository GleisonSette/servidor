# Arquitetura da plataforma compartilhada

metadata:
  canon_id: canon-arquitetura-plataforma
  source_path: memory/canon/arquitetura-plataforma.md
  generated_from: decisão do usuário, auditoria e requisitos dos três projetos
  updated_at: 2026-08-15
  status: canonical

## Objetivo e limite

O servidor hospeda somente três projetos do mesmo administrador: `apiwpp`,
Pixel/CIA e SaferWPP. Não há acesso de clientes ao host ou ao Kubernetes. O
cluster fornece isolamento lógico para laboratório, não isolamento forte entre
partes mutuamente hostis.

## Identidades

- Uma identidade SSH administrativa por pessoa/dispositivo.
- Uma chave de assinatura de release por projeto.
- Um controlador de deploy restrito por projeto; nenhuma automação recebe shell
  administrativo genérico.
- Uma ServiceAccount por workload, com token desabilitado quando não necessário.
- Secrets, credenciais de banco e certificados separados por finalidade.

SSH identifica o operador. O isolamento entre projetos é feito por assinatura
de artefato, namespaces, RBAC, ServiceAccounts, NetworkPolicy, dados e limites.

Estado dos controladores em 2026-08-15:

- `apiwpp-deployctl` e `apiwpp-backupctl` estão instalados, root-owned e são os
  únicos caminhos sem senha do apiwpp;
- `pixel-deployctl` e `saferwpp-deployctl` ainda não existem;
- até a instalação de cada controlador, o respectivo Codex de aplicação pode
  preparar artefatos e confirmar o acesso, mas não alterar o servidor;
- a capacidade administrativa com senha do usuário humano não é uma interface
  de automação e não pode ser usada para contornar um controlador ausente.

Cada repositório de aplicação possui `README-SERVIDOR-LOCAL.md` e uma referência
obrigatória em `AGENTS.md`. O guia define ownership, comandos permitidos,
proibições, verificação e escalonamento para a plataforma.

## Topologia lógica

```text
PC administrativo 192.168.100.57
             |
             +-- SSH 22
             +-- Kubernetes API 6443
                         |
                 Ubuntu + K3s
                         |
        +----------------+----------------+
        |                |                |
     apiwpp        cia-pixel-lab     saferwpp-lab
        |                |                |
        +------ infraestrutura compartilhada ------+
```

Namespaces de infraestrutura não contam como novos projetos. Eles só serão
criados quando uma dependência compartilhada realmente for implantada.

## Baseline de cada espaço

- Pod Security `restricted`, fixado à versão Kubernetes validada.
- NetworkPolicy com negação padrão de entrada e saída.
- Liberação inicial somente para DNS; cada dependência recebe regra explícita.
- ResourceQuota e LimitRange conservadores.
- Service ClusterIP; NodePort, LoadBalancer, externalIPs, hostPort e hostNetwork
  são negados por padrão.
- Containers sem root, sem privilege escalation, capabilities removidas,
  seccomp RuntimeDefault e filesystem raiz somente leitura quando possível.
- Requests, limits, probes, shutdown gracioso e logs estruturados obrigatórios.

Baseline aplicado em 2026-08-15:

- `cia-pixel-lab`: até 12 pods, quatro PVCs, 30 GiB de requests de storage,
  500m/768Mi de requests agregados e 1500m/2Gi de limits agregados;
- `saferwpp-lab`: até 24 pods, oito PVCs, 60 GiB de requests de storage,
  750m/1536Mi de requests agregados e 2500m/4Gi de limits agregados;
- ambos começam vazios, negam todo tráfego de entrada/saída exceto DNS e
  recusam Services que exponham NodePort, LoadBalancer ou externalIPs.

As cotas são orçamento inicial, não promessa de capacidade. Serão revistas com
métricas durante a implantação real.

## Dados compartilhados no laboratório

Para reduzir I/O e operação no host atual, um único processo PostgreSQL pode
atender o laboratório, desde que cada projeto tenha banco, owner, papéis de
runtime/migration e regras de acesso independentes. Nenhum projeto acessa o
banco `clone_wpp` do `apiwpp`.

Esse arranjo é exclusivo do laboratório. Não satisfaz a exigência de
PostgreSQL externo/HA do SaferWPP ou do Pixel em staging/produção. A política de
backup deve ser reclassificada de `apiwpp` para o conjunto do laboratório antes
de receber bancos adicionais.

NATS pode ser compartilhado no laboratório somente com TLS, accounts,
credenciais, subjects, streams e quotas separados. Keycloak pode ser uma
dependência da plataforma. MinIO e ClamAV permanecem dependências do SaferWPP.

## Entrada HTTP

O primeiro acesso usa ClusterIP e port-forward administrativo. Um ingress
interno poderá ser adicionado depois, limitado ao PC administrativo e sem abrir
80/443 para a rede residencial.

Webhook UAZAPI ou collector Pixel público exigem borda externa separada com
TLS, WAF/rate limit e túnel WireGuard ou mTLS. O roteador residencial não recebe
redirecionamento de porta para o servidor.

## Deploy e rollback

- Build reproduzível e verificado antes do servidor.
- Imagem OCI imutável por digest, SBOM e scan de vulnerabilidade/segredo.
- Manifesto de release assinado por chave exclusiva do projeto.
- Controlador root-owned valida assinatura, digest, escopo e lock.
- O controlador aceita uma interface fechada; não recebe comando shell,
  caminho arbitrário, kubeconfig root ou manifesto fora do contrato.
- Migration é bloqueante e usa papel separado.
- Rollout, smoke test e rollback preservam a versão anterior.
- Alteração manual no cluster deve ser evitada e posteriormente reconciliada no
  repositório quando uma resposta emergencial for necessária.

O K3s mantém audit log somente de metadados com rotação limitada. Antes de
mudanças de configuração do cluster de nó único, o serviço é parado brevemente
para criar backup consistente e root-only do datastore SQLite e da configuração.

## Capacidade

O nó único permite uma réplica por workload e baixo tráfego. Quotas iniciais
protegem o host, mas não substituem medição conjunta. HDD, quatro núcleos,
Fast Ethernet e um único domínio de falha impedem afirmar alta disponibilidade.
