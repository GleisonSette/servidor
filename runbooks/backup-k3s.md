# Backup e restauração do K3s de nó único

O datastore atual é SQLite. Uma cópia consistente é feita com o serviço K3s
parado por uma janela curta. O arquivo contém credenciais do cluster e deve ser
root-only.

## Backup

1. Confirmar nó e aplicação saudáveis.
2. Criar diretório root-only em `/var/backups/shared-lab/<UTC>`.
3. Parar `k3s`.
4. Arquivar `/var/lib/rancher/k3s/server` e `/etc/rancher/k3s`.
5. Gerar SHA-256 do arquivo e sincronizar os dados em disco.
6. Iniciar `k3s` imediatamente.
7. Verificar nó `Ready`, Deployment `apiwpp`, smoke test e checksum.

O backup não deve ser copiado para este repositório. Uma cópia somente no mesmo
HDD protege contra erro lógico, não contra falha física; o destino externo do
backup do cluster é uma decisão futura.

## Restauração

Restauração é uma operação destrutiva e exige autorização própria. Ela deve ser
ensaiada em host isolado: validar checksum, parar K3s, preservar o estado atual,
restaurar os diretórios com donos e modos originais, iniciar e conferir nó,
Secrets, PVCs e workloads.
