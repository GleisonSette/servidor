# Decisões da plataforma local

metadata:
  canon_id: canon-decisoes
  source_path: memory/canon/decisoes.md
  generated_from: decisões do usuário e limites observados do laboratório
  updated_at: 2026-08-21
  status: canonical

## Resolvida D001 - Projetos admitidos pela plataforma

O servidor preserva o `apiwpp` existente e reserva toda a capacidade restante
ao Blindou. Os namespaces vazios Pixel/CIA e SaferWPP podem permanecer como
histórico declarativo, mas não recebem workload. Namespace no mesmo nó não
protege um projeto se o host inteiro for comprometido.

## Resolvida D002 - Identidade administrativa

Não haverá chave SSH por projeto. A chave SSH existente identifica o
administrador. Cada projeto terá assinatura de release, controlador de deploy,
ServiceAccounts, Secrets, banco e permissões próprios.

## Resolvida D003 - Ordem de implantação

Memória/base declarativa e estabilização foram concluídas. A preparação do
SaferWPP foi interrompida por decisão posterior do usuário para priorizar o
Blindou. Nenhum projeto pode usar essa prioridade para contornar seu próprio
controlador, isolamento ou gate de segurança.

## Resolvida D004 - Classificação por projeto

`apiwpp` conserva a classificação atual. Pixel/CIA e SaferWPP ficam sem novos
workloads. O Blindou poderá ser o primeiro uso operacional limitado do host,
sem alegação de alta disponibilidade, somente depois que os gates temporários
de D013 passarem.

## Resolvida parcialmente D005 - Destino externo de alertas

O usuário escolheu `gleisonsette@gmail.com` como receptor externo, independente
do servidor e do WhatsApp monitorado. A decisão do endereço está concluída. O
gate operacional continua pendente até existir canal autenticado, credencial
restrita, teste real de entrega e runbook de falha. A integração prevista é por
e-mail; não inventar webhook, WhatsApp ou destino alternativo.

## Resolvida parcialmente D006 - Borda pública

Para o Blindou, Cloudflare Pages e Cloudflare Tunnel foram escolhidos. Durante
a exceção D013, o conector fica no namespace `blindou-edge` e alcança apenas
Services ClusterIP. Nenhum projeto abre portas na ONT residencial.

Em 2026-08-20 o usuário autorizou a criação do Zero Trust, do Tunnel
`blindou-physical` e a vinculação do servidor. O conector foi ativado e
verificado sob gate `connector-only`: exatamente um Pod, um Secret, nenhuma
porta pública/Service/PVC e sem liberar `blindou-production`. As rotas técnicas
do Tunnel apontam para Services ClusterIP ainda ausentes e, portanto,
permanecem fechadas até as origens da aplicação existirem.

## Resolvida D007 - Baseline privado dos novos namespaces

Os espaços Pixel e SaferWPP iniciam vazios, com Pod Security `restricted`,
default deny, somente DNS liberado, cotas conservadoras e conta padrão sem
token. Uma política de admissão impede Service público. As cotas serão
recalibradas com medições, sem remover os limites de segurança.

## Resolvida D008 - Backup do K3s antes de mudanças

O K3s usa SQLite em nó único. A cópia consistente inicial foi feita com parada
breve e checksum. Ela fica root-only no mesmo HDD e serve para rollback lógico;
uma cópia externa do cluster continua sendo melhoria futura, distinta do R2 do
PostgreSQL.

## Resolvida D009 - Restart de serviços dependentes

PostgreSQL Exporter e gateway privado usam `PartOf` para acompanhar restart do
PostgreSQL e K3s. A manutenção também os inicia explicitamente e valida os
listeners. Isso evita que `Requires` derrube o dependente sem trazê-lo de volta.

## Resolvida D010 - Publicação e licença

O repositório de infraestrutura compartilhada é público em
`https://github.com/GleisonSette/servidor` e usa licença MIT, copyright 2026
Gleison Sette. Os repositórios `apiwpp`, Pixel/CIA, SaferWPP e Blindou
permanecem fora desse commit e conservam seus próprios históricos e licenças.

## Resolvida D011 - Operação segregada por repositório

Cada Codex de aplicação deve ler o guia do servidor do próprio repositório antes
de acessar o host. O apiwpp opera somente pelos controladores restritos já
instalados. Pixel, SaferWPP e Blindou permanecem sem permissão de alteração até
receberem controladores root-owned próprios, com releases assinadas e escopo
fechado nos respectivos namespaces e dados. A senha administrativa, `sudo`
genérico, kubeconfig root e o controlador de outro projeto não são atalhos
válidos.

## Resolvida D012 - Contenção externa obrigatória do Blindou

O gateway observado é uma ONT Huawei HG8145V5 com perfil Oi `OI2`. Ela não é a
fronteira de segurança do Blindou e sua função residencial “DMZ host” é
proibida. Um firewall dedicado, fisicamente externo ao servidor, deve separar
HOME, EDGE e BLINDOU-DMZ, negar DMZ para HOME/gerência da ONT/Internet por
padrão e registrar as exceções.

O `cloudflared` fica na EDGE externa. O servidor não pode atuar como seu próprio
firewall nem manter um conector que permita criar saída arbitrária por túnel.
Publicação permanece bloqueada até testes negativos, allowlist de providers,
alerta externo e kill switch independente do host passarem. Esse desenho reduz
movimento lateral e saída, mas não promete impedir toda exploração ou
exfiltração após comprometimento total: o produto possui integrações externas
necessárias e todos os projetos/dados do mesmo host compartilham o risco de root.

Esta decisão foi substituída temporariamente por D013 em 2026-08-19. Ela
permanece como referência da proteção que seria obtida com equipamento externo.

## Resolvida D013 - Contenção local temporária e host reservado ao Blindou

O usuário decidiu não comprar firewall neste momento e autorizou UFW, sysctl,
Pod Security, NetworkPolicy e Cloudflare Tunnel no próprio servidor até a
migração para a Vultr. O conector roda somente em `blindou-edge`, com Secret
separado; ONT continua sem DMZ host, UPnP ou port forward.

A interface `enp2s0` nega destinos privados para processos do host e tráfego
encaminhado dos Pods, nega entrada da LAN exceto administração 22/6443 de
`192.168.100.57`, preserva DNS/DHCP e tem IPv6 desabilitado para fechar o `/64`
compartilhado. Saída pública permanece disponível. Esses controles reduzem
comprometimento de aplicação/container, mas **não contêm root no host**. Vultr
encerra a exceção.

O serviço `apiwpp` existente é preservado; toda a capacidade restante fica
reservada ao Blindou. Pixel/CIA e SaferWPP não recebem workloads. O Blindou
continua usando UAZAPI e não reativa seu código `api-wpp`.

## Resolvida D014 - Fundação isolada do Blindou no host compartilhado

O Blindou usa o PostgreSQL 18 já operado no host, sem criar um segundo processo,
mas recebe database vazio, quatro logins, grupos, regras HBA e CA cliente
exclusivos. As conexões dos Pods exigem certificado e SCRAM; nenhum login possui
superuser, criação de database/role ou replicação.

O backup físico pgBackRest continua protegendo o cluster inteiro. O Blindou
também produz dump lógico separado, valida o catálogo antes de criptografar e
exporta somente o envelope CMS AES-256-GCM. A chave privada de recuperação e a
chave de assinatura de release permanecem fora do servidor. Frequência,
retenção, RPO/RTO e destino offsite continuam pendentes em D005.

## Resolvida D015 - Build efêmero e servidor somente leitura no GHCR

Em 2026-08-20 o usuário autorizou que compilação, testes e publicação das
imagens Blindou usem runner efêmero hospedado pelo GitHub. O workflow é manual,
restrito a `main`, SHA completo e confirmação fechada; testes usam PostgreSQL
descartável e precedem qualquer publicação.

O job publicador usa `GITHUB_TOKEN` temporário com `packages: write`. O servidor
físico nunca recebe essa autoridade: conserva somente PAT classic com exatamente
`read:packages`, root-only, e materializa o pull secret apenas durante release
autorizada. Build, publicação de candidato e deploy são efeitos separados.
`push`, disparo do workflow e promoção dos digests continuam exigindo
autorizações próprias.

## Resolvida D016 - Cloudflare Pages permanece automático no primeiro push

Em 2026-08-21 o usuário decidiu manter ativa a integração automática da branch
`main` com o Cloudflare Pages. O primeiro `push` autorizado pode publicar o
painel antes que a API compatível esteja Ready; a indisponibilidade temporária
dos fluxos integrados foi aceita.

O build e o deployment do painel devem ser acompanhados, mas sucesso do Pages
não libera o gate do servidor, migrations ou deploy. A release só é
considerada operacional depois que API e frontend compatíveis passam na
validação integrada.

## Resolvida D017 - Exceção pontual para o bootstrap de 2026-08-21

Depois de o protocolo de conflito expor a regra que proíbe o Codex de ler senha
administrativa ou usar `sudo` genérico, o usuário autorizou explicitamente uma
exceção única: ler `KEY_SERVIDOR` do arquivo temporário local somente para
executar os dois scripts versionados de bootstrap do `blindou-hostctl` e do
`blindou-deployctl`.

A senha foi enviada apenas por `stdin`, não entrou em argumento, log, resposta,
commit ou memória. A exceção foi consumida com a instalação bem-sucedida e não
altera D011 nem o runbook normal: operações futuras voltam a usar somente os
controladores root-owned ou bootstrap humano. O arquivo temporário deve ser
apagado pelo operador após esta entrega.
