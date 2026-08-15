# Alertas externos

Prometheus já avalia regras localmente. Falta escolher um receptor externo para
que falhas sejam percebidas sem consultar o painel.

A ativação exige uma decisão explícita sobre o destino (por exemplo, e-mail,
Telegram ou outro webhook controlado) e sua credencial. Até essa escolha, não
há receptor fictício: a pendência permanece visível no plano e nas decisões.

Ao implementar:

- instalar Alertmanager ligado somente a loopback ou rede interna necessária;
- armazenar a credencial fora do Git e com permissão mínima;
- agrupar alertas, definir intervalos de repetição e inibição;
- enviar um alerta sintético e comprovar recebimento;
- documentar rotação e remoção da credencial.
