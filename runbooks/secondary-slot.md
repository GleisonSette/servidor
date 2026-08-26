# Slot alternável APIWPP/SaferWPP

## Estado desta implementação

O contrato está implementado declarativamente neste repositório. Ele ainda não
foi instalado nem inicializado no servidor. O APIWPP continua ativo, o
SaferWPP continua sem workloads e nenhum recurso do Blindou foi alterado.

O escritor exclusivo é `/usr/local/sbin/secondary-slotctl`. Ele mantém o
atestado `root:root` `0600` em
`/var/lib/servidor-local/secondary-slot/state`, usa o mesmo lock global dos
controladores de aplicação e nunca recebe comando, path ou manifesto
arbitrário. Os controladores APIWPP e SaferWPP apenas leem o atestado.

## Barreiras de exclusão mútua

Três barreiras precisam concordar:

1. o atestado root-only reserva `apiwpp`, `saferwpp` ou `none`;
2. o runtime observado confirma as contagens e a saúde do ocupante;
3. a admissão Kubernetes nega criação ou ativação de workloads em todo
   namespace membro que não esteja marcado como `active`.

Estado ausente, arquivo inseguro, admissão divergente, label divergente,
transição pendente, runtime ambíguo ou APIWPP e SaferWPP simultâneos falham
fechados. Jobs concluídos não mantêm o slot ocupado; Jobs e CronJobs incompletos
contam como workload quando não estão suspensos. A conclusão da ativação
SaferWPP também exige ao menos um workload de longa duração Ready em cada
namespace obrigatório. O PostgreSQL exclusivo, seus backups e exporter
pertencem à fundação persistente do SaferWPP e não entram nessa contagem.

## Instalação futura

Uma janela separada e explicitamente autorizada deve:

1. validar o bundle offline com
   `operations/remote/verify-secondary-slot-artifacts.py`;
2. transportar o commit aprovado e comparar seu hash;
3. executar `bootstrap-secondary-slotctl.sh` como root;
4. gerar um `operation_id` no formato
   `YYYYMMDDTHHMMSSZ-<12 caracteres hexadecimais>`;
5. inicializar somente após confirmar APIWPP exatamente ativo, SaferWPP vazio e
   Blindou Ready e íntegro:

   ```text
   sudo -n /usr/local/sbin/secondary-slotctl \
     initialize-apiwpp-active OPERATION_ID \
     secondary-slot-initialize-apiwpp-active
   ```

6. executar `secondary-slotctl verify` e validar as métricas e as cinco regras
   de alerta.

O bootstrap apenas instala os artefatos, preserva versões anteriores e habilita
o timer. O `tmpfiles.d` cria o lock global como arquivo regular `root:root`
`0600` em todo boot, antes que uma identidade sem privilégio possa ocupar esse
caminho. O bootstrap não cria o atestado, não reduz réplicas e não aplica
workloads SaferWPP.

## Ordem APIWPP para SaferWPP

Os comandos do slot e do APIWPP usam o mesmo `operation_id`. O controlador
SaferWPP não aceita esse ID como argumento: ele lê a reserva pendente no
atestado root-only e vincula a ativação à release e ao hash de um plano ainda
válido.

1. `secondary-slotctl begin-suspend apiwpp OPERATION_ID secondary-slot-begin-suspend`;
2. `apiwpp-deployctl suspend OPERATION_ID` e `verify-suspended`;
3. `secondary-slotctl complete-suspend apiwpp OPERATION_ID secondary-slot-complete-suspend`;
4. `secondary-slotctl reserve saferwpp OPERATION_ID secondary-slot-reserve`;
5. executar o plano somente leitura e guardar o `planSha256` retornado:

   ```text
   sudo -n /usr/local/sbin/saferwpp-deployctl \
     plan --release RELEASE_ID --output json
   ```

6. executar o deploy com a mesma release e o hash exato do plano e, depois,
   verificar a release:

   ```text
   sudo -n /usr/local/sbin/saferwpp-deployctl \
     deploy --release RELEASE_ID --plan-sha256 PLAN_SHA256 \
     --reason "secondary slot activation OPERATION_ID" --output json
   sudo -n /usr/local/sbin/saferwpp-deployctl \
     verify --release RELEASE_ID --output json
   ```

7. `secondary-slotctl complete-activation saferwpp OPERATION_ID secondary-slot-complete-activation`;
8. `secondary-slotctl verify`.

A volta usa a mesma sequência, trocando os membros. O APIWPP somente retoma
depois de `reserve apiwpp`, quando o atestado informa APIWPP reservado e zero
workload nos dois lados.

## Falha, reconciliação e alerta

Falha antes de qualquer workload mudar usa `abort-transition`. Se o runtime já
mudou, o aborto simples é recusado e a operação deve usar `reconcile`. Essa
operação também reaplica o manifesto fixo pertencente a root quando a admissão
estiver ausente ou divergente. A reconciliação lê o runtime e aceita somente
três observações inequívocas: APIWPP ativo sozinho, SaferWPP ativo e Ready
sozinho ou ambos suspensos. Ela nunca escolhe um lado quando ambos estão ativos
ou quando um rollout está parcial.

Toda falha de transição executada sob o lock grava auditoria JSONL e um evento
append-only em `alerts.jsonl`. A resolução adiciona outro evento, sem apagar o
histórico. Esse outbox é o contrato de integração para a futura ferramenta administrativa;
enquanto ela não existe, Prometheus alerta por estado divergente, split-brain,
transição parada, coleta desatualizada e alerta operacional não resolvido.
Auditoria e outbox mantêm o arquivo atual e até cinco rotações de 16 MiB,
preservando uma janela local limitada sem permitir crescimento indefinido. O
histórico root-only mantém no máximo 256 atestados anteriores. A métrica lê um
estado compacto que guarda somente os IDs ainda não resolvidos; assim a coleta
não precisa reprocessar o histórico a cada minuto.

Se o Blindou mudar entre o começo e o fim, a conclusão normal é recusada. A
reconciliação pode recuperar apenas o estado do slot quando o Blindou continuar
saudável, preservando um alerta crítico sobre a divergência. O controlador não
aplica, remove, escala, rotula nem anota nenhum recurso Blindou.

## Revisão de coesão

Os dois arquivos operacionais escritos manualmente que ultrapassam 600 linhas
foram revisados por responsabilidade. `secondary-slotctl` mantém no mesmo
processo a CLI fechada, a máquina de estados, auditoria e métricas porque todas
essas operações precisam compartilhar o mesmo lock e a mesma fronteira
root-only. `secondary_slot.py` concentra somente os contratos e as primitivas
explícitas de arquivo seguro, observação Kubernetes, gates e fingerprint usadas
pelo controlador e pelos testes. Nenhum deles contém lógica das
aplicações APIWPP, SaferWPP ou Blindou.

## Rollback

O bootstrap salva todos os alvos preexistentes e o `prometheus.yml` em
`/var/backups/servidor-local/secondary-slot-bootstrap/<timestamp>`. O rollback
da instalação exige autorização própria e restaura exatamente esse conjunto,
valida `visudo`, `promtool` e systemd e repete as provas do slot e do Blindou.

O atestado, histórico, auditoria e outbox de alertas nunca são apagados pelo
rollback. Se a admissão precisar ser retirada, os dois membros devem estar em
estado inequívoco, a versão anterior precisa ser restaurada primeiro e os
controladores de aplicação continuam falhando fechados enquanto o atestado não
for novamente verificável.
