# Decisões da plataforma local

metadata:
  canon_id: canon-decisoes
  source_path: memory/canon/decisoes.md
  generated_from: decisões do usuário e limites observados do laboratório
  updated_at: 2026-08-19
  status: canonical

## Resolvida D001 - Quatro projetos sob a mesma plataforma

O servidor é limitado a `apiwpp`, Pixel/CIA, SaferWPP e Blindou. Como o único
operador do host é o usuário, um cluster K3s compartilhado com isolamento por
namespace é adequado aos laboratórios. O Blindou possui uso operacional
condicionado à barreira externa descrita em D012; namespace no mesmo nó não
protege os demais projetos se o host inteiro for comprometido.

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

`apiwpp`, Pixel/CIA e SaferWPP conservam a classificação `lab`/`development`
registrada. O Blindou poderá ser o primeiro uso operacional limitado do host,
sem alegação de alta disponibilidade, somente depois que um firewall externo o
retirar da LAN residencial e todos os gates de D012 passarem. Antes disso, o
servidor inteiro continua inadequado para a publicação do Blindou.

## Pendente D005 - Destino externo de alertas

É necessário escolher um receptor autenticado independente do servidor e do
WhatsApp monitorado. A escolha afeta credencial, custo, privacidade, entrega e
runbook. Até a decisão, Alertmanager pode ser preparado e validado localmente,
mas a Fase 2 registra o gate como pendente.

## Resolvida parcialmente D006 - Borda pública

Para o Blindou, Cloudflare Pages e Cloudflare Tunnel foram escolhidos. O
conector do túnel deve ficar em uma zona EDGE externa ao servidor físico, e a
origem deve ser privada e autenticada. Webhook/collector dos demais projetos
continuam sem borda decidida. Nenhum projeto abre portas na ONT residencial.

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
