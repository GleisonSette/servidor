# Aplicar a base da plataforma

## Pré-condições

- confirmar hostname `apiwpp` e endereço `192.168.100.59`;
- confirmar nó `Ready` e `apiwpp` com uma réplica disponível;
- confirmar backup PostgreSQL saudável e backup consistente recente do K3s;
- revisar o diff deste repositório e validar que não contém segredos.

## Procedimento

1. Enviar somente `platform/base` para um diretório temporário do servidor.
2. Validar `namespaces.yaml` com `--dry-run=server` e todo o kustomization com
   `--dry-run=client`.
3. Aplicar somente `namespaces.yaml`; são espaços vazios e privados.
4. Validar `project-spaces.yaml` e `service-exposure-policy.yaml` com
   `--dry-run=server`, agora que os namespaces existem.
5. Aplicar `k3s kubectl apply -k`.
6. Verificar labels, ResourceQuota, LimitRange, ServiceAccount e
   NetworkPolicies nos dois namespaces.
7. Confirmar que os namespaces não têm pods, Services ou Ingress.
8. Validar que um Service `NodePort` de teste é recusado pela admissão, usando
   apenas `--dry-run=server`.

## Rollback

Enquanto não houver workloads, remover os recursos pelo mesmo kustomization é
seguro, mas exige autorização explícita. Depois de receber workloads, remover
namespace deixa de ser um rollback aceitável; cada aplicação passa a ter seu
próprio procedimento.

## Critério de aceite

- dry-run e aplicação sem erros;
- namespaces vazios e privados;
- controles declarados iguais ao estado do cluster;
- `apiwpp` não alterado.
