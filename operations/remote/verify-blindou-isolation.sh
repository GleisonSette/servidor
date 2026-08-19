#!/usr/bin/env bash
set -Eeuo pipefail

readonly PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export PATH

fail() {
  printf '[blindou-isolation] FALHA: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf '[blindou-isolation] OK: %s\n' "$*"
}

usage() {
  cat >&2 <<'EOF'
uso: verify-blindou-isolation.sh \
  --expected-hostname NOME --server-interface IFACE \
  --server-cidr IPV4/CIDR --default-gateway IPV4 \
  --home-cidr IPV4/CIDR --ont-ip IPV4 --admin-ip IPV4 \
  --firewall-dns IPV4 --allow-host HOST [--allow-host HOST ...] \
  [--blocked-public-ip IPV4]

Executa somente verificações. Deve rodar como root depois que a barreira
externa estiver instalada e antes de qualquer workload Blindou.
EOF
}

expected_hostname=''
server_interface=''
server_cidr=''
default_gateway=''
home_cidr=''
ont_ip=''
admin_ip=''
firewall_dns=''
blocked_public_ip='1.1.1.1'
declare -a allowed_hosts=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-hostname) expected_hostname="${2:-}"; shift 2 ;;
    --server-interface) server_interface="${2:-}"; shift 2 ;;
    --server-cidr) server_cidr="${2:-}"; shift 2 ;;
    --default-gateway) default_gateway="${2:-}"; shift 2 ;;
    --home-cidr) home_cidr="${2:-}"; shift 2 ;;
    --ont-ip) ont_ip="${2:-}"; shift 2 ;;
    --admin-ip) admin_ip="${2:-}"; shift 2 ;;
    --firewall-dns) firewall_dns="${2:-}"; shift 2 ;;
    --allow-host) allowed_hosts+=("${2:-}"); shift 2 ;;
    --blocked-public-ip) blocked_public_ip="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; fail "argumento desconhecido: $1" ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || fail 'execute como root'
for command_name in ip python3 curl timeout getent ss k3s jq pgrep; do
  command -v "$command_name" >/dev/null 2>&1 \
    || fail "comando obrigatório ausente: $command_name"
done

[[ -n "$expected_hostname" && "$expected_hostname" =~ ^[a-zA-Z0-9.-]+$ ]] \
  || fail 'expected-hostname inválido'
[[ -n "$server_interface" && "$server_interface" =~ ^[a-zA-Z0-9_.:-]+$ ]] \
  || fail 'server-interface inválida'
[[ ${#allowed_hosts[@]} -gt 0 ]] \
  || fail 'informe ao menos um --allow-host exigido pelo runtime'
for host in "${allowed_hosts[@]}"; do
  [[ "$host" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] \
    || fail "hostname permitido inválido: $host"
done

python3 - "$server_cidr" "$default_gateway" "$home_cidr" "$ont_ip" \
  "$admin_ip" "$firewall_dns" "$blocked_public_ip" <<'PY'
import ipaddress
import sys

server = ipaddress.ip_interface(sys.argv[1])
gateway = ipaddress.ip_address(sys.argv[2])
home = ipaddress.ip_network(sys.argv[3], strict=False)
ont = ipaddress.ip_address(sys.argv[4])
admin = ipaddress.ip_address(sys.argv[5])
dns = ipaddress.ip_address(sys.argv[6])
blocked = ipaddress.ip_address(sys.argv[7])

if server.version != 4 or home.version != 4:
    raise SystemExit("somente IPv4 é aceito neste gate")
if server.ip in home:
    raise SystemExit("o servidor ainda pertence à rede residencial")
if gateway not in server.network:
    raise SystemExit("o gateway externo não pertence à DMZ do servidor")
if dns not in server.network:
    raise SystemExit("o DNS deve ser o proxy local da barreira externa")
if ont not in home or admin not in home:
    raise SystemExit("ONT e estação administrativa devem pertencer à rede residencial declarada")
if blocked.is_private or blocked.is_loopback or blocked.is_link_local:
    raise SystemExit("blocked-public-ip deve ser um IPv4 público")
PY
pass 'endereços e separação de sub-redes são coerentes'

[[ "$(hostname)" == "$expected_hostname" ]] \
  || fail "hostname inesperado: $(hostname)"
ip link show dev "$server_interface" >/dev/null 2>&1 \
  || fail "interface ausente: $server_interface"
ip -4 -o addr show dev "$server_interface" \
  | awk '{print $4}' | grep -Fxq "$server_cidr" \
  || fail "a interface não possui exatamente $server_cidr"
pass 'identidade e endereço da interface confirmados'

default_route="$(ip -4 route show default)"
[[ "$(wc -l <<<"$default_route")" -eq 1 ]] \
  || fail 'deve existir exatamente uma rota IPv4 padrão'
grep -Fq "via $default_gateway " <<<"$default_route" \
  || fail 'gateway padrão diverge da barreira externa'
grep -Fq "dev $server_interface" <<<"$default_route" \
  || fail 'rota padrão usa interface inesperada'
pass 'rota padrão aponta para a barreira externa'

for private_target in "$ont_ip" "$admin_ip"; do
  route="$(ip -4 route get "$private_target")"
  grep -Fq "via $default_gateway " <<<"$route" \
    || fail "$private_target ainda está on-link ou desvia da barreira externa"
done
pass 'ONT e estação administrativa não estão diretamente conectados ao servidor'

tcp_reachable() {
  local ip_address="$1"
  local port="$2"
  timeout 3 bash -c "exec 3<>/dev/tcp/${ip_address}/${port}" >/dev/null 2>&1
}

for port in 80 443; do
  if tcp_reachable "$ont_ip" "$port"; then
    fail "a administração da ONT ainda é alcançável em ${ont_ip}:${port}"
  fi
done
pass 'administração da ONT bloqueada a partir da DMZ'

if tcp_reachable "$blocked_public_ip" 443; then
  fail "HTTPS público arbitrário ainda é alcançável em ${blocked_public_ip}:443"
fi
pass 'saída HTTPS arbitrária bloqueada'

if command -v resolvectl >/dev/null 2>&1; then
  resolvectl dns "$server_interface" | grep -Fq "$firewall_dns" \
    || fail 'a interface não usa o proxy DNS declarado'
else
  grep -Eq "^nameserver[[:space:]]+${firewall_dns//./\.}([[:space:]]|$)" /etc/resolv.conf \
    || fail 'o resolv.conf não usa o proxy DNS declarado'
fi
pass 'resolução DNS usa a barreira externa'

for host in "${allowed_hosts[@]}"; do
  getent ahostsv4 "$host" >/dev/null \
    || fail "DNS não resolveu provider permitido: $host"
  http_code="$(curl --silent --show-error --output /dev/null \
    --write-out '%{http_code}' --connect-timeout 5 --max-time 15 \
    "https://${host}/" || true)"
  [[ "$http_code" =~ ^[1-5][0-9][0-9]$ ]] \
    || fail "provider permitido não respondeu por TLS/HTTP: $host"
done
pass 'providers explicitamente permitidos estão alcançáveis'

ufw status | grep -Fq 'Status: active' || fail 'UFW está inativo'
if pgrep -fa '(^|/|[[:space:]])cloudflared([[:space:]]|$)' >/dev/null; then
  fail 'cloudflared não pode executar no servidor físico'
fi

cloudflared_objects="$(k3s kubectl get deployment,statefulset,daemonset -A -o json \
  | jq '[.items[] | select(
      (.metadata.name | ascii_downcase | contains("cloudflared")) or
      any(.spec.template.spec.containers[]?; .image | ascii_downcase | contains("cloudflared"))
    )] | length')"
[[ "$cloudflared_objects" -eq 0 ]] \
  || fail 'há workload cloudflared dentro do servidor'

public_services="$(k3s kubectl -n blindou-production get service -o json \
  | jq '[.items[] | select(
      (.spec.type == "NodePort") or
      (.spec.type == "LoadBalancer") or
      ((.spec.externalIPs // []) | length > 0)
    )] | length')"
[[ "$public_services" -eq 0 ]] \
  || fail 'o namespace Blindou contém Service exposto'
pass 'host e K3s não contêm conector ou Service público do Blindou'

printf '%s\n' '[blindou-isolation] RESULTADO: passed'
