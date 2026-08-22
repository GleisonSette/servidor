# Contenção temporária do Blindou no servidor físico

## Decisão e limite

O usuário decidiu não comprar firewall neste momento. Até o cutover para a
Vultr, o host físico usa contenção local e Cloudflare Tunnel como única entrada.
Essa decisão substitui temporariamente a topologia HOME/EDGE/BLINDOU-DMZ.

O controle reduz o impacto de comprometimento de aplicação ou container. Ele
**não contém um invasor com `root` no host**, porque `root` pode alterar UFW,
sysctl, K3s e o conector. A migração Vultr é a solução definitiva.

O serviço `apiwpp` já existente permanece intacto. Nenhum workload Pixel/CIA
ou SaferWPP será implantado; toda a capacidade restante é reservada ao Blindou.
O Blindou usa UAZAPI e não reativa o provider APIWPP.

## Estado observado após a ativação em 2026-08-19

- ONT/gateway: Huawei HG8145V5, perfil `OI2`, `192.168.100.1`;
- switch: KNUP KP-SW105 não gerenciável, sem VLAN/ACL;
- servidor: `apiwpp`, `enp2s0` em `192.168.100.59/24`;
- IPv6 público observado em um `/64` compartilhado na `enp2s0`;
- estação administrativa: `192.168.100.57`;
- K3s, UFW, AppArmor, PostgreSQL e `apiwpp` ativos;
- `cloudflared` ausente;
- somente TCP 22 e 6443 respondem pela LAN entre as portas verificadas;
- `blindou-hostctl` corrigido instalado e contenção de host ativa;
- IPv6 da `enp2s0` desabilitado, DNS/HTTPS pública preservados e ONT bloqueada;
- nenhum namespace, Secret, Tunnel ou workload Blindou aplicado.

## Topologia temporária

```text
Internet -> Huawei, sem DMZ host/UPnP/port forward
                    |
              KNUP KP-SW105
                    |
          Ubuntu + UFW + K3s
            |             |
        apiwpp atual    Blindou
                          +-- blindou-edge: cloudflared
                          +-- blindou-production: aplicação
```

O conector usa um Tunnel remotamente gerenciado e inicia somente TCP/7844 para
o Cloudflare em HTTP/2. Não há listener público no host. `blindou-edge` acessa
somente os Services `ClusterIP` da API e do redirector. O token fica em Secret
exclusivo desse namespace.

## Controles locais

O controlador root-owned `blindou-hostctl` possui interface fechada e:

1. confirma hostname, endereço, gateway, UFW, K3s e gateway `apiwpp`;
2. cria backup root-only de `/etc/ufw` antes da primeira mudança;
3. preserva DNS/DHCP para a ONT e 22/6443 para o PC administrativo;
4. nega pela `enp2s0` a LAN, RFC1918, CGNAT e link-local tanto para processos
   do host quanto para tráfego encaminhado dos Pods;
5. nega entrada da LAN e recoloca acima dela somente 22/6443 da estação
   administrativa conhecida;
6. desabilita IPv6 somente na interface física para fechar o `/64` local;
7. valida DNS, HTTPS pública, bloqueio da ONT, K3s e `apiwpp`;
8. remove somente as regras marcadas pelo Blindou no rollback e restaura os
   valores IPv6 capturados antes da aplicação.

No boot, `systemd-networkd` configura a interface depois do primeiro
`systemd-sysctl`. A unidade root-owned
`blindou-temporary-containment.service` reaplica somente o arquivo sysctl do
Blindou depois de `network-online.target` e antes de K3s e do gateway privado.
O controlador também restaura esse valor em uma reaplicação idempotente. Isso
fecha a janela observada após reboot sem alterar as regras do `apiwpp`.

As exceções DNS do Blindou incluem a origem fixa `192.168.100.59`, para não
serem deduplicadas pelas regras históricas mais amplas do `apiwpp`. Cada
inserção confirma imediatamente seu marcador. Falha durante a instalação ou no
gate final aciona rollback automático; a senha humana continua necessária para
um rollback iniciado fora desse fluxo.

Saída pública permanece disponível para Cloudflare, UAZAPI, e-mail,
marketplaces e atualizações. UFW não é uma allowlist FQDN confiável; o K3s
exclui redes privadas e a aplicação valida SSRF. Essa é uma limitação aceita da
fase temporária.

## Bootstrap humano obrigatório

O bootstrap corrigido já foi executado. O procedimento abaixo permanece como
caminho controlado para reinstalação ou atualização futura do controlador.

O Codex não lê senha nem usa `sudo` genérico. Uma única sessão humana root deve
instalar o controlador versionado:

Exceção histórica encerrada: em 2026-08-21, depois de confronto explícito da
regra, o usuário autorizou uma única execução automatizada dos dois bootstraps
versionados com a senha temporária recebida por `stdin`. A exceção foi consumida
na mesma manutenção, não se aplica a trabalhos futuros e não autoriza guardar,
registrar ou reutilizar a senha. O arquivo temporário local usado nessa sessão
deve ser removido pelo operador.

```bash
cd /home/apiadmin/<inbox-validado>/operations/remote
sudo ./bootstrap-blindou-hostctl.sh
```

Antes do comando, o operador confere que o diretório é o inbox informado pelo
Codex e que contém somente `blindou-hostctl`, `blindou-hostctl.sudoers`, o
bootstrap e o verificador versionados. Depois:

```bash
sudo -n /usr/local/sbin/blindou-hostctl status
sudo -n /usr/local/sbin/blindou-hostctl \
  apply-firewall blindou-temporary-host-containment
sudo -n /usr/local/sbin/blindou-hostctl verify
```

O bootstrap não instala workload, Cloudflare, Secret, banco ou migration.

## Gate antes do primeiro deploy

- `blindou-hostctl verify` retorna sucesso;
- `apiwpp-deployctl verify` continua aprovado;
- do PC administrativo, somente 22/6443 e portas explicitamente já aprovadas
  respondem; 80/443/5432/NodePort permanecem fechadas;
- ONT não possui DMZ host, UPnP nem port forward para o servidor;
- namespaces `blindou-edge` e `blindou-production` possuem Pod Security,
  default deny, quota e gate `passed` atestado pelo controlador da plataforma;
- imagem `cloudflared` usa digest, token está somente no Secret da EDGE e
  NetworkPolicy permite apenas DNS, TCP/7844 e origem ClusterIP;
- rotas públicas, WAF e Access/mTLS foram validados fora do host;
- backup, receptor de alerta, domínios, Secrets e imagens da release existem.

Sem todos os itens, o primeiro deploy continua bloqueado.

### Janela fechada da primeira release

`operations/Invoke-BlindouFirstRelease.ps1` conduz a janela sem aceitar segredo
em argumento. UAZAPI, Resend e a senha inicial são solicitados em uma janela
protegida e seguem por `stdin` para operações fixas do `blindou-deployctl`.

A sequência obrigatória é:

1. validar UAZAPI e Resend, gerar chaves internas e materializar ConfigMap e
   Secrets com a aplicação ainda em `secrets-only`;
2. instalar Alertmanager somente em loopback, enviar alerta sintético e exigir
   confirmação humana em `gleisonsette@gmail.com`;
3. criar o dump lógico criptografado anterior às migrations, exportá-lo para a
   estação administrativa e conferir SHA-256 e tamanho;
4. registrar o recibo offsite com RPO de 15 minutos, RTO de 4 horas e retenção
   de 30 dias;
5. liberar `passed` somente para a release assinada cuja prova GHCR corresponde
   ao mesmo SHA, executar migrations e aplicar os workloads;
6. receber a senha inicial por `stdin`, criar `gleisonsette@gmail.com` como
   `super_admin` e validar um login real pela borda pública;
7. repetir os gates do host e do `apiwpp`.

O sender WhatsApp do 2FA permanece ausente enquanto `AUTH_REQUIRE_2FA=false`.
Pagar.me também permanece ausente. A imagem privada do `cloudflared` recebe o
pull secret GHCR somente leitura na EDGE, sem montar a credencial no container.
Falha da primeira release remove workloads, volta a aplicação para
`secrets-only` e restaura o conector isolado.

## mTLS

- cliente ou integração para Cloudflare: Access/mTLS pode autenticar endpoints
  administrativos e máquina-a-máquina;
- público final: login, assinatura da aplicação, WAF e rate limit; não exigir
  certificado de cliente de compradores;
- Cloudflare para origem: o Tunnel autentica o conector pelo token. Authenticated
  Origin Pulls não se aplica a Tunnel;
- dependências internas PostgreSQL/NATS conservam TLS/mTLS próprios.

## Rollback

Se a rede ou o `apiwpp` degradar, usar console local ou a sessão SSH preservada:

```bash
sudo /usr/local/sbin/blindou-hostctl \
  rollback-firewall blindou-temporary-host-containment
```

O rollback remove somente regras com comentários `blindou-*`, remove o sysctl
temporário e restaura os valores IPv6 capturados antes da aplicação. Ele não
é liberado sem senha para automação e não restaura banco, workloads, K3s ou
configuração Cloudflare.

Para incidente da aplicação, primeiro desabilitar as rotas/Tunnel no
Cloudflare e escalar `blindou-cloudflared` a zero pelo controlador autorizado.
Preservar logs e evidências. Nunca abrir porta na ONT como atalho.
