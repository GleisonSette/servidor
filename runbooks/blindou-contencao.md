# Contenção externa do Blindou

## Objetivo

Impedir que o comprometimento do servidor físico permita movimento lateral
para a residência, administração da ONT ou outros projetos. O controle decisivo
fica em equipamento externo ao servidor; UFW, AppArmor, Pod Security e
NetworkPolicy continuam como defesa em profundidade.

Não existe promessa séria de proteção absoluta contra qualquer zero-day. O
Blindou precisa acessar UAZAPI, e-mail e marketplaces; um invasor que controle
o host pode tentar abusar dessas rotas permitidas. Por isso, a borda usa negação
por padrão, allowlist, limites e logs independentes, e o servidor nunca atua
como seu próprio firewall.

## Estado observado em 2026-08-19

- ONT/gateway: Huawei HG8145V5, perfil `OI2`, `192.168.100.1`;
- servidor: `apiwpp`, `enp2s0` em `192.168.100.59/24`;
- estação administrativa: `192.168.100.57`;
- `eno1` existe e está inativa;
- a rota padrão do servidor aponta diretamente para a ONT;
- portanto, a contenção externa ainda não existe e o deploy comercial do
  Blindou está bloqueado.

A função “DMZ host” da ONT residencial não cria uma zona de segurança: ela
encaminha portas para um host. Não ativá-la. Não criar port forwarding, UPnP ou
exposição direta do servidor.

## Topologia-alvo

```text
Internet
   |
Huawei HG8145V5 (somente ONT/acesso)
   |
firewall dedicado e externo
   +-- HOME: Wi-Fi, computadores e administração
   +-- EDGE: conector Cloudflare e proxy de integrações
   +-- BLINDOU-DMZ: servidor físico, sem acesso direto à HOME/Internet
```

O conector Cloudflare roda na zona EDGE, não no K3s e não no host físico. Ele
alcança um gateway de origem privado e autenticado; o contrato exato desse
gateway será fechado junto com o equipamento escolhido. Até isso existir, os
manifests da aplicação não podem ser aplicados.

## Política obrigatória

1. `WAN -> servidor`: negar tudo; não existe redirecionamento de porta.
2. `BLINDOU-DMZ -> HOME/gerência da ONT/outros projetos`: negar e registrar.
3. `BLINDOU-DMZ -> Internet`: negar por padrão.
4. DNS e NTP do servidor usam serviços controlados do firewall.
5. HTTPS externo passa por gateway/proxy com hostnames permitidos, limite de
   requisições e log remoto. Um `0.0.0.0/0:443` direto não é aceitável.
6. `HOME -> BLINDOU-DMZ`: somente a estação administrativa, SSH 22 e API K3s
   6443, com autenticação atual preservada e rate limit.
7. `EDGE -> origem Blindou`: somente a porta privada definida, com mTLS e fonte
   restrita. O edge não recebe SSH, banco ou Kubernetes.
8. O kill switch desabilita a regra EDGE/origem e a saída do Blindou no
   firewall, sem depender do servidor comprometido.

O contrato versionado está em
`platform/security/blindou-edge-policy.yaml`.

## Sequência de implantação futura

1. Escolher um firewall que suporte ao menos três zonas independentes, regras
   stateful, deny log, DNS controlado, backup de configuração e restauração.
2. Exportar e guardar a configuração atual da ONT; desativar UPnP e confirmar
   que não há port forwards para o servidor.
3. Criar HOME, EDGE e BLINDOU-DMZ em sub-redes diferentes. Não reutilizar
   `192.168.100.0/24` na DMZ.
4. Mover fisicamente o servidor para a BLINDOU-DMZ e reservar seu endereço.
5. Aplicar primeiro as negações, depois somente os fluxos permitidos.
6. Instalar o conector Cloudflare na EDGE com identidade própria e sem acesso à
   HOME. Não copiar o token para o servidor.
7. Configurar o gateway/proxy de saída com os domínios realmente habilitados no
   arquivo de produção do Blindou.
8. Aplicar somente o namespace vazio e os controles de admissão. A label
   `platform.servidor.local/deployment-gate` nasce ausente, o que faz a
   admissão negar qualquer Pod.
9. Executar o verificador abaixo. Só o controlador restrito da plataforma pode
   mudar a label para `passed`; depois disso ainda é necessária autorização
   específica para o primeiro deploy.

## Gate de aceite

Como root no servidor, depois de substituir os valores de rede e informar os
providers ativados:

```bash
/opt/servidor/operations/remote/verify-blindou-isolation.sh \
  --expected-hostname apiwpp \
  --server-interface <interface-da-dmz> \
  --server-cidr <ipv4/cidr-da-dmz> \
  --default-gateway <ipv4-do-firewall-na-dmz> \
  --home-cidr 192.168.100.0/24 \
  --ont-ip 192.168.100.1 \
  --admin-ip 192.168.100.57 \
  --firewall-dns <ipv4-do-firewall-na-dmz> \
  --allow-host api.resend.com \
  --allow-host <hostname-real-da-uazapi>
```

O resultado precisa ser `passed`. Além dele, de uma máquina na HOME deve ser
comprovado que apenas 22/6443 autorizados alcançam o servidor; de uma máquina
de teste na BLINDOU-DMZ devem falhar acesso à HOME, ONT e HTTPS arbitrário. Os
logs de negação precisam chegar a um destino fora do servidor.

## Rollback

- Antes da mudança, exportar configuração do firewall/ONT e registrar cabeamento
  e endereços.
- Se o acesso administrativo for perdido, desconectar a DMZ da Internet, ligar
  localmente por console e restaurar apenas a configuração externa anterior.
- Não contornar a falha ligando novamente o servidor à LAN residencial com os
  workloads Blindou ativos.
- Reabilitar tráfego somente depois de repetir integralmente o gate.
