# Controladores fechados do SaferWPP

## Estado desta implementação

A plataforma possui o verificador independente, o bootstrap root fechado, a
renovação das identidades Kubernetes e os alertas necessários para instalar as
releases assinadas dos três controladores SaferWPP. Esses artefatos ainda não
foram executados no host.

A instalação não suspende o APIWPP, não reserva o slot, não cria banco, não lê
Secret, não inicia workload SaferWPP e não executa deploy. Ela recusa começar
se APIWPP, Blindou ou o controlador do slot não estiverem íntegros.

## Conteúdo materializado

- `saferwpp-deployctl`, `saferwpp-backupctl` e `saferwpp-secretsctl` vêm
  exclusivamente do bundle assinado `saferwpp.controller-release/v1`;
- Node e Cosign ficam isolados em
  `/usr/local/lib/saferwpp-deployctl/tools`, sem instalação global;
- configuração, validadores, RBAC, admission, sudoers, tmpfiles, trust root,
  SBOM, scan e proveniência ficam root-owned em caminhos fixos;
- `saferwpp-deployctl` e `saferwpp-secretsctl` recebem certificados e
  kubeconfigs próprios, sem grupo administrativo Kubernetes;
- os certificados duram 365 dias e são renovados 45 dias antes da expiração
  por `saferwpp-kube-identities.timer`;
- a reconciliação diária confirma a identidade devolvida pelo API Server e
  publica expiração e último sucesso no textfile collector do Node Exporter;
- Prometheus alerta com 30 dias de antecedência ou após 26 horas sem uma
  reconciliação válida.

O kubeconfig contém a chave privada embutida, é `root:root` `0600` e é trocado
atomicamente. A emissão usa somente a CA cliente local do K3s e CNs exatos
`saferwpp-deployctl` e `saferwpp-secretsctl`. A Role e a admission continuam
sendo a fronteira efetiva de autorização.

## Pré-condições

Antes da janela root, comprovar:

1. host `apiwpp` e K3s `v1.36.2+k3s1`;
2. `apiwpp-deployctl verify`, `blindou-deployctl verify` e
   `secondary-slotctl verify` aprovados;
3. slot inicializado com APIWPP como ocupante ativo;
4. namespaces `saferwpp-lab`, `saferdock-identity` e `saferdock-platform`
   materializados pela fundação, com labels canônicos e sem workload SaferWPP;
5. bundle, chave pública, release ID, commit e SHA-256 obtidos da mesma release
   assinada;
6. repositório `servidor` transportado a partir do commit aprovado e copiado
   para diretório root-owned antes da execução.

O bootstrap falha antes de instalar qualquer arquivo se uma pré-condição ou a
assinatura divergir. A chave administrativa SSH não deve fornecer senha por
pipeline, `sudo -S`, shell root ou kubeconfig administrativo.

## Execução fechada

No diretório root-owned do commit aprovado, a única interface é:

```text
operations/remote/bootstrap-saferwpp-controllers.sh \
  ARCHIVE SHA256 PUBLIC_KEY RELEASE_ID GIT_COMMIT
```

Os cinco argumentos são valores, não comandos nem destinos. O verificador
independente exige a trust root SaferWPP fixa, inventário e modos exatos,
manifesto canônico, assinatura ECDSA, hash, release/commit, alvo Linux/amd64,
builders imutáveis, SBOM SPDX, scan Trivy sem finding e proveniência exata.
Somente depois ele extrai o conteúdo em diretório temporário root-only.

O bootstrap salva arquivos, kubeconfigs, objetos RBAC/admission e
`prometheus.yml` em
`/var/backups/servidor-local/saferwpp-controller-bootstrap/<timestamp>`. Em
seguida instala, emite ou renova as identidades, aplica somente os manifests
fixos, valida `visudo`, systemd e Prometheus e consulta os três contratos pelo
sudo restrito de `apiadmin`. Ao final repete as verificações de APIWPP, Blindou
e slot.

## Verificação após a instalação

Executar somente pelas superfícies permitidas:

```text
sudo -n /usr/local/sbin/saferwpp-deployctl contract --output json
sudo -n /usr/local/sbin/saferwpp-backupctl contract --output json
sudo -n /usr/local/sbin/saferwpp-secretsctl contract --output json
```

Também validar:

- timer ativo e último resultado do service igual a `success`;
- dois kubeconfigs `root:root` `0600` e identidade retornada pelo API Server
  igual ao CN correspondente;
- RoleBindings e admission idênticos aos arquivos root-owned;
- `apiwpp-deployctl verify`, `blindou-deployctl verify` e
  `secondary-slotctl verify` ainda aprovados;
- ausência de workload e de release SaferWPP.

`status`, `attest`, backup real, plano e deploy continuarão falhando enquanto
fundação, pgBackRest, Secrets e evidências não existirem. Isso é esperado e não
deve ser contornado.

## Acesso de navegador

O bundle instala somente o forced command
`/usr/local/sbin/saferwpp-access-session`. Usuário, chave e bloco SSH restrito
de `saferwpp-access` pertencem a uma janela posterior, porque exigem a chave
pública da estação e testes positivos e negativos de forwarding. A identidade
administrativa atual permanece com forwarding proibido.

## Rollback

Falha durante o bootstrap remove os objetos RBAC/admission recém-aplicados,
restaura os objetos anteriores, arquivos, kubeconfigs e `prometheus.yml`,
retorna o estado anterior do timer e recarrega systemd/Prometheus. O diretório
de backup é preservado para auditoria.

Rollback posterior exige autorização própria e usa o backup exato informado
na saída do bootstrap. Ele não remove audit log, release, evidência, banco,
Secret ou dado SaferWPP. Depois da restauração, repetir as três provas de
imutabilidade de APIWPP, Blindou e slot.
