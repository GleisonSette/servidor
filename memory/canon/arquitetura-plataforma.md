# Arquitetura da plataforma compartilhada

metadata:
  canon_id: canon-arquitetura-plataforma
  source_path: memory/canon/arquitetura-plataforma.md
  generated_from: decisão do usuário, auditoria e requisitos de apiwpp/Blindou
  updated_at: 2026-08-20
  status: canonical

## Objetivo e limite

O servidor preserva somente o serviço `apiwpp` existente e reserva a capacidade
restante ao Blindou. Pixel/CIA e SaferWPP não recebem workloads. Não há acesso
de clientes ao host ou ao Kubernetes. O cluster fornece isolamento lógico, não
isolamento forte contra comprometimento do kernel/root.

## Identidades

- Uma identidade SSH administrativa por pessoa/dispositivo.
- Uma chave de assinatura de release por projeto.
- Um controlador de deploy restrito por projeto; nenhuma automação recebe shell
  administrativo genérico.
- Uma ServiceAccount por workload, com token desabilitado quando não necessário.
- Secrets, credenciais de banco e certificados separados por finalidade.

SSH identifica o operador. O isolamento entre projetos é feito por assinatura
de artefato, namespaces, RBAC, ServiceAccounts, NetworkPolicy, dados e limites.

Estado dos controladores em 2026-08-20:

- `apiwpp-deployctl` e `apiwpp-backupctl` estão instalados, root-owned e são os
  únicos caminhos sem senha do apiwpp;
- `pixel-deployctl` e `saferwpp-deployctl` ainda não existem;
- `blindou-deployctl` está instalado e governa a fundação, dados, backup,
  conector Cloudflare e releases assinadas do Blindou;
- até a instalação de cada controlador, o respectivo Codex de aplicação pode
  preparar artefatos e confirmar o acesso, mas não alterar o servidor;
- a capacidade administrativa com senha do usuário humano não é uma interface
  de automação e não pode ser usada para contornar um controlador ausente.

Cada repositório de aplicação possui `README-SERVIDOR-LOCAL.md` e uma referência
obrigatória em `AGENTS.md`. O guia define ownership, comandos permitidos,
proibições, verificação e escalonamento para a plataforma.

## Topologia temporária de contenção

```text
Internet -> Huawei HG8145V5, sem porta publicada
                    |
              KNUP KP-SW105
                    |
          Ubuntu + UFW + K3s
             |             |
          apiwpp        Blindou
                         +-- blindou-edge/cloudflared
                         +-- blindou-production
```

UFW nega LAN, RFC1918, CGNAT e link-local pela interface física tanto para
processos do host quanto para tráfego encaminhado dos Pods. Entrada da LAN é
negada, com exceção de 22/6443 a partir do PC administrativo; DNS/DHCP são
preservados. IPv6 é desabilitado na interface para fechar o `/64`
compartilhado. `blindou-edge` inicia TCP/7844 para Cloudflare e acessa somente
API/redirector por ClusterIP. Saída HTTPS pública da aplicação permanece
temporariamente disponível.

Esses controles não são prova de contenção se o host for comprometido por
`root`. A decisão expira no cutover Vultr.

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

`blindou-production` e `blindou-edge` nascem vazios, com gate `blocked`, quota
zero para objetos operacionais, Pod Security `restricted`, default deny e
admissão adicional. Após autorização explícita, somente `blindou-edge` pode
avançar para `connector-only`: quota de um Pod e um Secret, nenhum Service/PVC e
admissão limitada ao `blindou-cloudflared` imutável. `blindou-production`
permanece bloqueado até a primeira release passar todos os gates. Quotas e
políticas de quarentena pertencem à plataforma; contas, PVCs e políticas dos
workloads continuam pertencendo ao repositório Blindou e só entram depois do
gate completo.

## Dados no host

O mesmo processo PostgreSQL 18 do host pode atender `apiwpp` e Blindou, mas
cada produto usa banco, owner, papéis de runtime/migration, certificados e
regras de acesso independentes. O Blindou nunca acessa o banco `clone_wpp` do
`apiwpp` e começa vazio pelas migrations próprias.

A fundação Blindou prepara quatro logins sem privilégio administrativo. As
conexões vindas do CIDR dos Pods exigem senha SCRAM e certificado assinado pela
CA cliente exclusiva do Blindou. O backup físico pgBackRest continua abrangendo
o cluster compartilhado; adicionalmente o database Blindou recebe dump lógico
isolado, validado e criptografado para uma chave de recuperação mantida fora do
servidor.

NATS e Redis do Blindou pertencem somente ao produto e rodam no seu namespace.
Os namespaces históricos Pixel/CIA e SaferWPP permanecem vazios e não recebem
banco, mensageria, identidade ou armazenamento neste servidor.

## Entrada HTTP

O primeiro acesso usa ClusterIP e port-forward administrativo. Um ingress
interno poderá ser adicionado depois, limitado ao PC administrativo e sem abrir
80/443 para a rede residencial.

O Blindou usa Pages e Tunnel; durante a exceção o conector fica em
`blindou-edge` e alcança API/redirector por ClusterIP. Access/mTLS protege
administração e integrações máquina-a-máquina no edge Cloudflare; o Tunnel
autentica o conector pelo token próprio. A ONT residencial não recebe DMZ host,
UPnP ou redirecionamento de porta para o servidor.

## Deploy e rollback

- Build reproduzível e verificado antes do servidor.
- Imagem OCI imutável por digest, SBOM e scan de vulnerabilidade/segredo.
- Imagens próprias privadas no GHCR; o servidor recebe um PAT classic com
  exatamente `read:packages`, sem `repo`, escrita, exclusão ou workflow.
- Manifesto de release assinado por chave exclusiva do projeto.
- Controlador root-owned valida assinatura, digest, escopo e lock.
- O controlador aceita uma interface fechada; não recebe comando shell,
  caminho arbitrário, kubeconfig root ou manifesto fora do contrato.
- Migration é bloqueante e usa papel separado.
- Rollout, smoke test e rollback preservam a versão anterior.
- A credencial GHCR permanece root-only fora do Kubernetes enquanto o runtime
  está bloqueado. O controlador materializa `blindou-ghcr-pull` apenas durante
  release autorizada e somente `blindou-runtime` pode referenciá-lo.
- Alteração manual no cluster deve ser evitada e posteriormente reconciliada no
  repositório quando uma resposta emergencial for necessária.

O K3s mantém audit log somente de metadados com rotação limitada. Antes de
mudanças de configuração do cluster de nó único, o serviço é parado brevemente
para criar backup consistente e root-only do datastore SQLite e da configuração.

## Capacidade

O nó único permite uma réplica por workload e baixo tráfego. Quotas iniciais
protegem o host, mas não substituem medição conjunta. HDD, quatro núcleos,
Fast Ethernet e um único domínio de falha impedem afirmar alta disponibilidade.
