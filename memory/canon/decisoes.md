# Decisões da plataforma local

metadata:
  canon_id: canon-decisoes
  source_path: memory/canon/decisoes.md
  generated_from: decisões do usuário e limites observados do laboratório
  updated_at: 2026-08-15
  status: canonical

## Resolvida D001 - Três projetos no mesmo K3s

O servidor será limitado a `apiwpp`, Pixel/CIA e SaferWPP. Como o único operador
é o usuário e não haverá clientes com acesso, um cluster K3s compartilhado com
isolamento por namespace é adequado ao laboratório.

## Resolvida D002 - Identidade administrativa

Não haverá chave SSH por projeto. A chave SSH existente identifica o
administrador. Cada projeto terá assinatura de release, controlador de deploy,
ServiceAccounts, Secrets, banco e permissões próprios.

## Resolvida D003 - Ordem de implantação

Primeiro vêm memória/base declarativa e estabilização. Depois será implantado o
SaferWPP, porque já possui Dockerfiles e chart Helm. Pixel vem em seguida porque
o runtime atual é orientado a systemd/VM e ainda exige KMS, banco, NATS e
Control Plane reais.

## Resolvida D004 - Classificação do ambiente

O servidor é `lab`/`development`. Namespace separado no mesmo nó não será
chamado de staging e não satisfaz as exigências de produção dos projetos.

## Pendente D005 - Destino externo de alertas

É necessário escolher um receptor autenticado independente do servidor e do
WhatsApp monitorado. A escolha afeta credencial, custo, privacidade, entrega e
runbook. Até a decisão, Alertmanager pode ser preparado e validado localmente,
mas a Fase 2 registra o gate como pendente.

## Pendente D006 - Borda pública futura

Webhook UAZAPI e collector Pixel poderão exigir entrada pública. A decisão entre
Cloudflare e VM pública com WireGuard/mTLS será tomada somente na Fase 5. Não
abrir portas no roteador residencial.

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
Gleison Sette. Os repositórios `apiwpp`, Pixel/CIA e SaferWPP permanecem fora
desse commit e conservam seus próprios históricos e licenças.

## Resolvida D011 - Operação segregada por repositório

Cada Codex de aplicação deve ler o `README-SERVIDOR-LOCAL.md` do próprio
repositório antes de acessar o host. O apiwpp opera somente pelos controladores
restritos já instalados. Pixel e SaferWPP permanecem sem permissão de alteração
até receberem controladores root-owned próprios, com releases assinadas e
escopo fechado nos respectivos namespaces e dados. A senha administrativa,
`sudo` genérico, kubeconfig root e o controlador de outro projeto não são
atalhos válidos.
