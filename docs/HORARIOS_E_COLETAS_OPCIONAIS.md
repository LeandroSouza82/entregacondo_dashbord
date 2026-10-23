> Atualização posterior: Supabase e dashboard ativados em 23/10/2026, com autorização do usuário. Este documento preserva o relato da preparação; consulte [ATIVACAO_2026_10_23.md](ATIVACAO_2026_10_23.md) para o estado remoto, domínio, APK e pendências atuais.

# Horários e coleta vinculada — opcionais

Implementação local em 22/10/2026, após a confirmação do usuário de que as duas opções devem ser opcionais. Branch preservada nos dois repositórios: `fix/conclusao-falha-metricas-20261019`. Nenhum commit, push, merge, publicação, migração remota ou instalação desta versão no celular.

## Comportamento

- No dashboard, “Horários e coleta vinculada (opcional)” começa recolhido. Não preencher mantém o fluxo sem condições. Pedidos e rascunhos antigos continuam aceitos; apartamentos, WhatsApp, observações e demais trabalhos existentes foram preservados.
- Quando necessário, o gestor informa dia, horário inicial/final e atendimento previsto no local (0–240 minutos). Os horários do planejamento usam Brasília, independentemente do fuso do computador. A faixa deve terminar depois de começar, no mesmo dia, e comportar o atendimento previsto.
- Uma entrega pode depender de uma coleta do mesmo rascunho, empresa e motorista. O gestor adiciona a coleta primeiro e depois a escolhe na lista da entrega. Excluir a coleta exige remover o vínculo das entregas primeiro. Cada pedido tem “Editar condições”, com opção de limpar.
- Com condições, o dashboard pede tempos pelas ruas, considera deslocamento, atendimento previsto e espera e confere a sequência antes de enviar. A saída pode ser atual ou futura. Sem solução encontrada, falha viária ou alteração ainda em cálculo, o envio é impedido e o rascunho continua disponível. Não se afirma que a busca prova inviabilidade ou encontra o ótimo global.
- O envio conserva os UUIDs das paradas e vincula a agenda à mesma sequência. O dashboard consulta a versão de capacidades antes de enviar condições; um servidor antigo não recebe esses pedidos silenciosamente sem as regras. O endpoint legado de despacho imediato recusa pedidos com essas condições.
- No aplicativo, horários e vínculos aparecem somente quando configurados. Uma entrega vinculada aguarda a coleta ser concluída **e confirmada no servidor**. Uma coleta falhada, cancelada, ainda ofertada ou concluída somente na fila offline não libera a entrega. Permanecem disponíveis os detalhes e o registro de falha.
- Aceite parcial: aceitar a entrega antes da coleta não a libera para atendimento. Aceitar a coleta depois a coloca antes da entrega ao juntar os pedidos na rota ativa. Um atendimento já iniciado permanece na frente. Não há aceite, retirada, chegada ou conclusão automáticos.
- Organização automática e salvamento manual conferem condições, deslocamentos, retorno configurado e atendimento em andamento. A sugestão só substitui a lista local após um cálculo válido; conflitos no servidor pedem atualização. Não salva uma ordem inválida nem inventa ETA em falha viária.
- Atrasos reais mostram aviso. A faixa de horário orienta o planejamento; não impede registrar uma conclusão ou falha real fora dela. A dependência, por sua vez, também é conferida no banco para chegada e sucesso. O acompanhamento público não libera uma entrega bloqueada e encerra após conclusão.
- O cache offline preserva as condições e o último estado confirmado da coleta. Quando a coleta necessária nem está entre as paradas liberadas, o restante não exibe uma estimativa que omita esse trabalho.

## Organização e banco

Dashboard: `src/components/routing/RouteRuleFields.tsx`, `src/features/routes/services/routeRules.ts`, `routeSchedule.ts`; integração pontual em `NewRouteView.tsx` e `dispatchDriverServices.ts`.

Mobile: `apps/mobile/lib/route_schedule.dart` e `stop_rules.dart`; campos no modelo/cache e integrações nas telas já existentes, nos cartões, na atualização de pedidos e no estimador restante.

SQL canônico: `supabase/modules-sql/03b_route_rules.sql`, despacho, aceite, reordenação e condição de acompanhamento. Migração preparada: `supabase/migrations/20261022195415_optional_route_windows_and_collections.sql`. `scripts/build_schema.js` inclui o módulo e gera `schema.sql`.

Campos: data da janela, coleta de origem, atendimento previsto e timestamps gerados em Brasília. Colunas antigas de horários permanecem intactas. A chave estrangeira composta/deferida exige empresa e coleta válidas; o índice da referência e a validação de tipo/motorista impedem vínculos cruzados. Somente gestão autorizada define condições; helpers privados não foram expostos à API. Condições de um atendimento iniciado/finalizado não podem ser alteradas.

## Verificação

- `flutter analyze --no-pub`: sem problemas após a revisão final de estilo.
- `flutter test --no-pub --reporter expanded`: **161 testes passaram**. Inclui 14 novos cenários do planejador, cache, consulta da coleta por empresa, estado desconhecido/falha, detalhes bloqueados, cartão e cálculo restante. Log local em `apps/mobile/build/optional-route-rules-tests.log`.
- Dashboard `npm run build`: passou. Permanece o aviso de tamanho dos bundles dos mapas. Lint dos módulos novos e do serviço de envio: sem avisos. O lint global mantém avisos anteriores do projeto, incluindo falsos positivos de pureza em callbacks de `NewRouteView`.
- `node --experimental-strip-types --test scripts/test_route_schedule.mjs`: **10 testes passaram**: precedência, janela completa, espera, atendimento, retorno, direção dos trajetos, inviabilidade, dados inválidos, máscara com mais de 64 paradas, fuso de Brasília e bloqueio de servidor antigo.
- `node scripts/test_route_rules_ui.mjs`: formulário React real em Chrome local, transportes/API de mapa simulados. Verifica rascunho antigo/apartamento, campo opcional recolhido, edição, validação, exclusão de coleta vinculada, gate de capacidade, envio com IDs/agenda/UTC, saída alterada invalidando plano e preservação em inviabilidade. Sem exceções no navegador. A abertura do WhatsApp não faz parte desta etapa.
- `node scripts/test_database.js --planning-only`: PostgreSQL 17 temporário somente em 127.0.0.1; **43 verificações novas e 7 regressões existentes com conexões independentes**, tanto em instalação nova quanto por todas as migrações. Inclui rollback integral de envio inválido, aceite parcial, coleta recebida depois, atendimento em andamento, janela/duração, privilégios, referência entre empresas, falha/sucesso, isolamento e acompanhamento. Os cenários anteriores de acompanhamento/privacidade também passaram nos dois bancos.
- A suíte geral anterior `node scripts/test_database.js` executou acompanhamento, aceite/retirada, **99 regressões e 15 verificações de push por banco**, mas falha na comparação global de políticas. Divergência **preexistente**, mantida: `comprovante_publico_download`, criada por `20261021210000_public_receipt_rpc.sql`, permite SELECT público no bucket `entregas-comprovantes` e não consta no schema novo. Não foi alterada nem aplicada remotamente. Portanto a suíte geral não deve ser descrita como totalmente aprovada.

## Limites e ativação pendente

- Não ativado em produção. Para usar as opções será necessário autorizar a migração, disponibilizar o dashboard atualizado e validar o APK no aparelho. Nesta etapa o banco remoto e a versão instalada no celular não foram alterados.
- A migração de acompanhamento `20261022153822_customer_arrival_tracking.sql` e a configuração/publicação HTTPS do acompanhamento continuam com suas pendências anteriores. Gerar este APK não ativa os links públicos.
- Faixa por dia, sem atravessar meia-noite; não há calendário recorrente, pausas obrigatórias ou múltiplas coletas para uma mesma entrega nesta versão.
- Busca limitada a 100 paradas quando há condições; usa tempos viários estimados e atendimento previsto. Trânsito e duração real podem mudar. A otimização considera tempo de término/espera e não promete a menor quilometragem global.
- Reorganizar com horários exige rede e GPS recente. Offline continua usando a última sequência e os estados confirmados em cache. Não cria roteamento offline ou confirmação de coleta sem servidor.
- Próximo item funcional da lista: definir a composição do **resumo do dia**, aproveitando o Histórico existente.
- O usuário confirmou teste físico dos **motivos de falha** da etapa anterior. Isso não substitui a validação física das novas condições.

## APK desta etapa

Arquivo local: `C:\Users\leand\Downloads\EntregaCondo-horarios-coletas-opcionais-2026-10-22-1731.apk`.
SHA-256: `AE417A2EA3DC5DE22300F55C5D955A3C2DD5C80516725A44EC640E3FAC6B84B3`.
Gerado e copiado para Downloads; esta versão não foi instalada. Build debug concluído com o aviso preexistente de compatibilidade futura do firebase_core/Kotlin Gradle.

Os snapshots anteriores à etapa foram preservados em `C:\Src\NewV10\route-rules-backup`.

## Instalação pelo cabo — 22/10/2026

Após solicitação explícita do usuário, o APK desta etapa foi instalado com adb install -r, preservando os dados. Android confirmou Success; versão 0.1.22 (código 23), atualização registrada às 17:33:05. MainActivity abriu com Status: ok e o processo permaneceu em execução. A migração remota e a disponibilização do dashboard continuam pendentes.

## Atualização de 23/10/2026 — permissões e preparação

A divergência local de políticas dos comprovantes foi corrigida e a suíte geral do banco passou por completo em instalação nova e por migrações. Preparados compartilhamento restrito por token e correção incremental da view de endereços. Supabase remoto foi apenas consultado; alterações e publicação continuam pendentes. A Vercel conectada contém o site de apresentação; a proposta é hospedar o dashboard em projeto separado. Consulte COMPROVANTES_E_PREPARACAO_DA_ATIVACAO.md para testes, limites e sequência de ativação.
