# Plataforma isolada do Blindou

## Estado e limite

Este runbook governa a fundação do Blindou no servidor `apiwpp`. A fundação
cria namespaces vazios e bloqueados, identidade de deploy, database vazio,
logins, TLS cliente, backup lógico criptografado e métricas da plataforma. Ela
não cria Secrets Kubernetes, não executa migrations, não publica imagens e não
inicia `cloudflared`.

O PostgreSQL 18 continua sendo um processo compartilhado com o `apiwpp`, mas o
Blindou possui database, quatro logins, grupos `NOLOGIN`, CA cliente, certificado
e backup lógico próprios. O backup físico pgBackRest continua cobrindo o cluster
PostgreSQL inteiro; ele não substitui a cópia lógica isolada do Blindou.

## Autoridades e arquivos

- `/usr/local/sbin/blindou-hostctl`: contenção temporária do host;
- `/usr/local/sbin/blindou-deployctl`: única interface sem senha da plataforma
  Blindou;
- `/usr/local/lib/blindou-platform/`: manifests e verificador root-owned;
- `/etc/blindou/`: chaves, certificados, URLs e identidades root-only;
- `/var/lib/blindou-platform/`: estado e cache de releases assinadas;
- `/var/backups/blindou/`: backups locais root-only;
- `/home/apiadmin/blindou-deploy-inbox/<sha40>/`: entrada fechada de releases;
- `/home/apiadmin/blindou-backup-outbox/`: somente envelopes criptografados
  exportados para leitura.

A chave privada de assinatura e a chave privada de recuperação nunca entram no
servidor ou neste repositório. Somente a chave pública de assinatura e o
certificado público de recuperação são instalados.

## Instalação do controlador

Antes da instalação, validar no repositório:

```bash
operations/remote/verify-blindou-platform-artifacts.sh
operations/remote/verify-blindou-release-contract.sh /c/github/blindou
```

Transferir o commit limpo para um inbox exclusivo, conferir os hashes no host e
executar como `root`:

```bash
cd /home/apiadmin/<inbox-validado>/operations/remote
sudo ./bootstrap-blindou-deployctl.sh
```

O bootstrap instala arquivos com ownership fixo, valida Python/YAML, certificado,
assinante e sudoers, habilita apenas a coleta de métricas e termina consultando
o status. Ele não aplica namespaces nem dados.

## Fundação Kubernetes bloqueada

```bash
sudo -n /usr/local/sbin/blindou-deployctl \
  apply-foundation blindou-platform-foundation
sudo -n /usr/local/sbin/blindou-deployctl verify-foundation
```

O aceite exige:

- `blindou-production` e `blindou-edge` com gate `blocked`;
- zero Deployment, StatefulSet, DaemonSet, Job, CronJob, Pod, Service, Secret e
  PVC nos dois namespaces;
- quota zero para Pods, Services, Secrets e PVCs;
- ServiceAccount padrão sem token, Pod Security `restricted` e default deny;
- admissão recusando Pod enquanto bloqueado e recusando NodePort;
- nenhum processo ou workload `cloudflared`;
- `blindou-hostctl verify` e `apiwpp-deployctl verify` aprovados.

Rollback humano, somente enquanto os namespaces estiverem vazios:

```bash
sudo /usr/local/sbin/blindou-deployctl \
  rollback-foundation blindou-platform-foundation
```

O rollback restaura as políticas de admissão capturadas antes da aplicação e o
label anterior do nó. Ele recusa remover namespace que possua objeto operacional.

## Fundação de dados

```bash
sudo -n /usr/local/sbin/blindou-deployctl \
  provision-data blindou-data-foundation
sudo -n /usr/local/sbin/blindou-deployctl verify-data
```

O provisionamento é idempotente e cria o database vazio `blindou`, quatro
logins sem privilégio administrativo e os grupos esperados pelas migrations. As
regras HBA exigem simultaneamente TLS, certificado emitido pela CA cliente do
Blindou e senha SCRAM. Nenhuma tabela da aplicação é criada nesta etapa.

Rollback de dados exige senha administrativa e só é aceito quando não existe
tabela de aplicação:

```bash
sudo /usr/local/sbin/blindou-deployctl \
  rollback-data blindou-empty-data-foundation
```

## Backup lógico criptografado

```bash
sudo -n /usr/local/sbin/blindou-deployctl \
  backup-database blindou-database-backup
sudo -n /usr/local/sbin/blindou-deployctl verify-backup
sudo -n /usr/local/sbin/blindou-deployctl export-latest-backup
```

O controlador cria um `pg_dump` custom com Zstandard, valida seu catálogo,
criptografa-o em envelope CMS AES-256-GCM para o certificado de recuperação e
remove o texto claro. O dump nasce em diretório aleatório `0700` sob `/var/tmp`
para que o usuário `postgres` não receba acesso de travessia ao diretório dos
backups criptografados. O trap do controlador remove esse staging também em
falha. A outbox expõe somente o envelope, o manifesto e o certificado público.
A prova de recuperação deve ocorrer fora do servidor com a chave privada
custodiada separadamente.

Periodicidade, retenção, destino offsite, RPO, RTO e ensaio recorrente dependem
de D005/P005. Não apagar ou rotacionar backups por valor inferido.

## Release assinada

O controlador aceita somente um diretório cujo nome seja o SHA Git completo e
que contenha `release.manifest`, `release.manifest.sig` e `rendered.tar.gz`.
Assinatura, SHA-256, estado limpo, paths do archive, namespaces, kinds, nomes,
imagens por digest, exposição e baseline dos Pods são validados antes do cache
root-owned.

`validate-release` pode preparar o cache, mas `apply` continua bloqueado até os
dois gates estarem `passed`, a quarentena ter sido removida e todos os Secrets
obrigatórios existirem. Nesta fase não passar gates nem aplicar release.

## Observabilidade

`blindou-platform-metrics.timer` grava no textfile collector do Node Exporter:

- integridade da fundação Kubernetes;
- integridade da fundação de dados;
- timestamp do backup lógico mais recente;
- estado do gate de cada namespace;
- sucesso da própria coleta.

Falha de coleta produz uma métrica explícita com valor zero. Alertas externos e
scrape dos workloads permanecem bloqueados por P005 e pela ausência de runtime.
Como o controlador usa lock exclusivo, uma auditoria manual concorrente pode
fazer um ciclo do coletor falhar fechado em zero; o ciclo seguinte deve voltar
a um sem intervenção. Persistência em zero exige investigação.

## Verificação final desta etapa

```bash
sudo -n /usr/local/sbin/blindou-deployctl status
sudo -n /usr/local/sbin/blindou-deployctl verify-foundation
sudo -n /usr/local/sbin/blindou-deployctl verify-data
sudo -n /usr/local/sbin/blindou-deployctl verify-backup
sudo -n /usr/local/sbin/apiwpp-deployctl verify
sudo -n /usr/local/sbin/blindou-hostctl verify
```

Também confirmar zero unit systemd falha, nenhuma porta nova e nenhum workload
Blindou. Divergência interrompe a fase; não liberar Tunnel, Secrets ou gate.
