# Alertas externos

O receptor aprovado é `gleisonsette@gmail.com`. O controlador da plataforma
instala o Alertmanager no host, escutando somente em `127.0.0.1:9093`, e o liga
ao Prometheus local. O envio usa Resend SMTP em `smtp.resend.com:587`, STARTTLS,
usuário fixo `resend` e API key recebida somente pelo canal protegido.

A configuração sensível fica em `/etc/prometheus/alertmanager.yml`, legível
somente por `root` e pelo grupo do Prometheus. Ela nunca entra no Git, em
argumento de processo, log ou resposta do controlador. O arquivo anterior do
Prometheus e, quando existir, do Alertmanager recebe backup root-only antes da
mudança.

O gate exige:

- configuração validada por `amtool` e `promtool`;
- Alertmanager ativo e Ready apenas em loopback;
- alerta sintético `BlindouSyntheticReceiverTest` aceito pelo Alertmanager;
- confirmação humana de recebimento antes de registrar o recibo `confirmed`;
- métricas e regras de falha/ausência da plataforma carregadas pelo Prometheus.

Para rotacionar a API key, executar novamente o orquestrador fechado de
provisionamento com a nova chave e repetir o alerta sintético. Nunca editar o
arquivo sensível manualmente. Para revogar, remover a chave no Resend depois de
outra chave ter sido validada e confirmada.

Se o alerta não chegar, não confirmar o recibo. Verificar o estado do serviço,
a validade do remetente no Resend e os logs do Alertmanager sem imprimir a
configuração. Enquanto não houver confirmação, `activate-release-gates` deve
falhar fechado.
