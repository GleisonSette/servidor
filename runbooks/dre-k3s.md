# DRE familiar no K3s local

## Estado e limite

O controlador fechado e a fundação Kubernetes vazia do DRE estão instalados no
servidor desde 2026-08-29. A release assinada
`dre-20260830T010200Z-29aeeb82d5bc` foi importada no cache fechado em
2026-08-30, mas não é a release corrente. Secrets, PVC, banco, imagens locais e
workloads continuam ausentes. Criação de segredo, migration persistente,
backup/restore de dados e deploy exigem janelas e autorizações operacionais
próprias.

O DRE é um projeto sempre ativo e independente. Ele não integra nem altera o
slot APIWPP/SaferWPP e não compartilha namespace, ServiceAccount, Secret, PVC,
banco, release ou chave de assinatura com Blindou. A primeira implantação é
recusada quando houver menos de 5 GiB de memória disponível, menos de 45 GiB no
filesystem do K3s, menos de quatro CPUs lógicas, nó não Ready ou qualquer
divergência dos controladores Blindou, APIWPP e slot secundário.
Se o futuro namespace `blindou-data` existir, seu controlador, lock e recursos
também entram obrigatoriamente na proteção.

## Fronteiras administrativas

- `/usr/local/sbin/dre-deployctl` é o único caminho automatizado de mutação.
- A identidade Kubernetes tem CN `dre-deployctl`, grupo `dre-deployers`, não
  pertence a `system:masters` e usa kubeconfig root-only próprio.
- A admissão `dre-controller-only` falha fechada para os recursos do DRE. O
  acesso `system:admin` continua sendo break-glass do administrador root e não
  é interface de automação cotidiana.
- O sudoers permite somente ações enumeradas do controlador; não concede shell,
  `kubectl`, caminho de manifesto, kubeconfig ou variável de ambiente livre.
- A chave privada de assinatura nunca entra neste repositório nem no servidor.
  O host recebe apenas a chave pública Ed25519.
- Por D030, `Dre.SudoBootstrap.psm1` pode ler exatamente uma ocorrência de
  `KEY_SERVIDOR` do arquivo ignorado canônico `C:\github\servidor\.env` e
  entregá-la somente por `stdin` ao bootstrap DRE fechado. O helper fixa host,
  padrão do staging, hashes,
  inventário, cache root-owned e instalador; não aceita comando livre. O valor
  não pode ser impresso, persistido, colocado em argumento ou variável de
  ambiente. Os helpers do Blindou/slot continuam capacidades separadas.

## Contrato da release

No repositório `C:\github\dre`, a release é renderizada por digest e empacotada
por `ops/k8s/package-release.py`. O archive assinado contém exatamente:

- os quatro estágios `00-platform`, `10-migrations`, `20-database-access` e
  `30-runtime`;
- `release.json` com checksums dos quatro estágios;
- `supply-chain.json` ligado ao SHA Git e ao release ID;
- SBOM SPDX e recibo de scan sem vulnerabilidade alta/crítica para as imagens
  Rust e PostgreSQL `linux/amd64`;
- regras de alerta K3s do DRE.

O release ID usa `dre-YYYYMMDDTHHMMSSZ-<12 primeiros caracteres do SHA Git>`.
O empacotador gera `release.tar.gz`, `release.tar.gz.sig` e
`release-envelope.json`. O controlador confere SHA-256, assinatura Ed25519,
conteúdo do archive, escopo Kubernetes, imagens, SBOM, scan e alertas antes de
copiar a release para cache root-only.

## Instalação do controlador

Estado vivo: bundle root-owned
`6b8e0e81190b4cda040abd8806c32ccd104fd291cb9dc325790595f77953ced1`,
chave pública
`4902604dad96d9b07f4010308d30e3815cb4e76446855d925079be0e3b922ce9`
e backup transacional `20260829T235150Z`. Reexecução usa bundle novo, hashes
novos e o mesmo contrato fechado; nunca altera o cache já atestado.

Somente em janela autorizada:

1. gerar e guardar a chave privada Ed25519 fora do servidor e do Git;
2. transportar este repositório, a chave pública e seus hashes para staging
   autenticado;
3. executar como root o comando fixo:

   ```text
   bootstrap-dre-deployctl.sh PUBLIC_KEY PUBLIC_KEY_SHA256
   ```

O bootstrap valida todos os artefatos, sintaxe sudoers/systemd, K3s
`v1.36.2+k3s1`, `x86_64` e integridade de APIWPP, Blindou e slot. Ele cria os
dois namespaces vazios, StorageClasses `Retain`/`Delete`, RBAC, admissão,
identidade renovável, métricas e alertas. Um dry-run com identidade não
autorizada precisa ser recusado. Falha restaura arquivos e Prometheus; se a
fundação era nova e ainda vazia, ela também é removida.

O backup transacional da instalação fica em
`/var/backups/servidor-local/dre-controller-bootstrap/<timestamp>`. Rollback
humano restaura somente os alvos registrados em `targets.txt`, repete
`visudo`, `systemd-analyze verify`, `promtool check config`, os três
controladores protegidos e a prova negativa da admissão.

O audit log técnico `/var/lib/dre-deployctl/audit.jsonl` usa rotação diária,
30 arquivos e teto de 16 MiB por arquivo. Planos de deploy já inúteis são
removidos depois de sete dias; recibos de release, backup e restore permanecem
root-only para rastreabilidade.

## Importação e plano

O operador copia apenas archive e assinatura para:

```text
/home/apiadmin/dre-deploy-inbox/RELEASE_ID/release.tar.gz
/home/apiadmin/dre-deploy-inbox/RELEASE_ID/release.tar.gz.sig
```

O diretório deve ser `apiadmin:apiadmin` `0700`; arquivos, `0400` ou `0600`.
Hashes vêm do envelope local conferido. A importação aceita somente:

```text
sudo -n /usr/local/sbin/dre-deployctl import-release RELEASE_ID ARCHIVE_SHA256 SIGNATURE_SHA256
```

Antes da primeira release, `initialize-secrets RELEASE_ID` recebe por `stdin`
um único JSON protegido com os campos exatos `schema`,
`registry_dockerconfigjson`, `web_bridge_token`, `r2` e
`fcm_service_account`. O dockerconfig fica restrito aos registries das duas
imagens; FCM deve ser `null` quando a release não o habilita. O token da ponte
usa somente alfabeto portátil, possui ao menos 64 caracteres e é o mesmo valor
protegido no Secret `DRE_BRIDGE_TOKEN` do Cloudflare Pages.

O orquestrador local gera o token da ponte somente em memória. Primeiro o envia
por `stdin` à operação autenticada que grava o Secret do Pages e confirma apenas
a presença do nome, nunca o valor. Somente depois monta o JSON em memória e o
envia por `stdin` ao controlador. Se a gravação no Cloudflare falhar, a
inicialização Kubernetes não começa. Se a inicialização falhar, o controlador
remove todos os Secrets DRE criados naquela tentativa e o Pages pode receber um
novo token antes da repetição. Não ler Secret Kubernetes para recuperar token,
não colocar valor em argumento e não persistir o JSON em disco ou histórico.
`DRE_API_ORIGIN` permanece ausente até a futura rota HTTPS ser autorizada.

O controlador gera senhas independentes para admin/API/worker/backup, URLs
codificadas e cifra de backup em `/run`, cria Secrets por arquivo e apaga o
material temporário. Se qualquer Secret DRE já existir, a inicialização inteira
é recusada; rotação futura é outra operação, nunca efeito colateral de deploy.

Não colocar o JSON protegido em argumento, histórico, arquivo do repositório ou
saída capturada. Usar entrada oculta/controlada do orquestrador da janela.

Depois:

```text
sudo -n /usr/local/sbin/dre-deployctl plan RELEASE_ID
```

O plano dura 30 minutos e vincula release, archive, release corrente, inventário
de Secrets, recursos protegidos e capacidade viva. A saída contém apenas o
`plan_sha256` não secreto. Mudança em qualquer prova exige plano novo.

## Deploy e verificação

Com autorização explícita para migration persistente e deploy:

```text
sudo -n /usr/local/sbin/dre-deployctl deploy RELEASE_ID PLAN_SHA256 OPERATION_ID
sudo -n /usr/local/sbin/dre-deployctl verify RELEASE_ID
```

`OPERATION_ID` usa `YYYYMMDDTHHMMSSZ-<12 hex>`. O controlador:

1. reverifica assinatura e conteúdo no cache;
2. valida capacidade, Secrets, identidade e os três projetos protegidos;
3. adquire locks DRE, Blindou e slot antes da mutação;
4. impede troca implícita da imagem PostgreSQL;
5. aplica plataforma e aguarda o PostgreSQL;
6. cria a stanza pgBackRest e executa `check`;
7. recria somente o Job fixo de migration e exige sete migrations bem-sucedidas;
8. recria o Job fixo de papéis e acessos;
9. aplica API/worker e aguarda os rollouts;
10. instala regras Prometheus assinadas, valida configuração e executa smoke
    pela proxy privada do API Server;
11. confirma exatamente `api`, `worker` e `postgres`, Services ClusterIP, PVC
    Bound e fingerprint inalterado de APIWPP/Blindou;
12. só então publica o ponteiro root-only da release.

Falha restaura a plataforma e o runtime anteriores; na primeira release remove
somente os dois Deployments, Services e PDBs de aplicação. PVC, PostgreSQL,
migration aditiva e Secrets são preservados para diagnóstico. Falha na própria
compensação fecha o gate como `rollback-failed`. Cada `operation_id` é de uso
único e possui recibo root-only `started`, `passed` ou `failed`, evitando repetir
silenciosamente uma operação interrompida. Migration destrutiva não pertence ao
contrato.

## Backup e restauração

Operações autorizadas:

```text
sudo -n /usr/local/sbin/dre-deployctl backup diff OPERATION_ID
sudo -n /usr/local/sbin/dre-deployctl backup full OPERATION_ID
sudo -n /usr/local/sbin/dre-deployctl restore-drill RELEASE_ID OPERATION_ID latest
```

`full` executa pgBackRest e a exportação lógica cifrada; `diff` executa somente
pgBackRest. Ambos exigem runtime saudável e gravam recibo root-only sem valor,
descrição ou credencial.

O restore drill copia em memória somente os Secrets necessários para
`dre-restore-drill`, cria um PVC de 20 GiB na StorageClass exclusiva `Delete`,
restaura da mesma release e desliga `archive_mode` no banco restaurado para não
enviar WAL ao prefixo de produção. A prova exige sete migrations e zero índice
inválido. Ao passar, remove StatefulSet, Service, ConfigMaps, Secrets e PVC e
aguarda o PV ser apagado. Falha preserva o PVC para diagnóstico e exige
reconciliação explícita; nunca apaga ou restaura sobre `dre-postgres-data`.

PITR aceita somente timestamp UTC `YYYY-MM-DDTHH:MM:SSZ`. O recibo do restore
fica em `/var/lib/dre-deployctl/receipts`.

## Exposição e dados reais

Este controlador não cria Ingress, NodePort, LoadBalancer, `hostPort`, regra
UFW, Tunnel ou rota Cloudflare. Após deploy, backup e restore aprovados, a API
continua ClusterIP. Rota HTTPS, contas, dispositivos Android e saldo inicial
são operações posteriores e separadamente autorizadas. PostgreSQL e métricas
nunca recebem exposição pública.
