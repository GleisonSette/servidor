# Executor de validação DRE

## Finalidade e fronteira

O servidor físico mantém um executor **rootless** para os gates integrais do
repositório DRE. Apenas as ferramentas de sistema permanecem instaladas; código,
imagens, containers, redes, volumes, caches e dados de cada execução ficam em um
diretório temporário exclusivo e são removidos ao final.

O executor opera sem daemon e sem acesso ao K3s. Ele não usa Docker, socket do
K3s, kubeconfig, `kubectl`, grupo novo, serviço systemd ou credencial de
produção. Os controladores root-owned continuam sendo a única interface para
consultar ou alterar o DRE no cluster.

## Instalação fechada

`operations/Invoke-DreValidationExecutorBootstrap.ps1` empacota somente os cinco
arquivos do contrato, exige `HEAD == origin/main`, transporta o archive por SSH
estrito e chama `Invoke-DreValidationExecutorSudoBootstrap`. Somente esse helper
pode ler `KEY_SERVIDOR` do `.env` canônico, mantê-la em memória e enviá-la por
`stdin` ao bootstrap fixo.

O bootstrap aceita Ubuntu 24.04 amd64 no host `apiwpp` e fixa:

- Podman 4.9.3;
- uidmap 4.13;
- podman-compose 1.0.6;
- slirp4netns 1.2.1;
- fuse-overlayfs 1.13;
- passt 2024-02-20;
- dependências e recomendações resolvidas pelo APT para build, rede e `init`,
  sem remoção nem atualização de pacote preexistente.

Antes e depois da transação são conferidos grupos, `subuid`, `subgid`,
metadados e inacessibilidade do kubeconfig/socket K3s. Units e sockets Podman
devem permanecer inativos e não habilitados. Durante o APT, um `policy-rc.d`
temporário impede partidas; imediatamente depois, o bootstrap desabilita todos
os presets Podman, recusa listener e remove socket sem listener antes de aceitar
a transação. Falha antes do recibo para units/sockets, remove somente pacotes
que não existiam na fotografia inicial e repete a negativa de runtime.

O recibo root-only em
`/var/lib/servidor-local/dre-validation-executor/state.json` registra commit,
hash do archive, versões, pacotes novos e as negativas `persistent_daemon=false`
e `k3s_access_granted=false`; ele não contém segredo.

## Execução descartável

Cada validação cria um diretório por `mktemp` em `/tmp`, configura `--root`,
`--runroot`, `--tmpdir`, XDG e caches dentro desse diretório e adiciona shims
temporários compatíveis com os comandos `docker`, `docker buildx` e
`docker compose` usados pelo Makefile. O shim encaminha apenas ao Podman
rootless e ao podman-compose; nunca abre socket ou serviço de API.

O source é um `git archive` de commit publicado. A execução sobe somente um
PostgreSQL/API/worker sintético na loopback, provisiona duas contas iniciadas
por `synthetic-`, dispositivos sintéticos e saldo inicial sintético, e então
executa literalmente:

```text
make release-check
make e2e
```

No encerramento, inclusive em falha, o runner derruba o Compose com volumes,
executa `podman system reset --force` contra o `--root` temporário e remove
somente o diretório validado daquela execução. Produção, `dre-production`,
Cloudflare, R2 operacional, contas reais e dados financeiros não participam.

## Verificação

Uma execução aprovada demonstra:

1. Podman rootless cria mapeamento subordinado e executa container com `init`;
2. nenhuma unit/socket Podman está ativa ou habilitada;
3. `apiadmin` continua sem ler kubeconfig ou socket containerd do K3s;
4. o ambiente sintético responde apenas em loopback;
5. `make release-check` e `make e2e` retornam zero;
6. nenhum container, volume, rede, processo pause ou diretório da execução
   permanece.

## Rollback

O rollback da transação em andamento é automático e usa a diferença exata de
pacotes instalados. Depois de uma instalação concluída, remoção das ferramentas
é uma mudança de host separada: exige nova autorização, leitura do recibo
root-only pelo mesmo caminho fechado, recusa se algum pacote tiver sido
alterado e `apt-get purge` somente do inventário registrado. O rollback nunca
remove dados, imagens ou serviços de outro projeto e nunca executa `autoremove`
cego.
