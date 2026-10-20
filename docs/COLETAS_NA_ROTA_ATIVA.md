# Coletas durante a rota

- Envios com coletas procuram a rota `em_execucao` do motorista na própria empresa.
- Com rota ativa, somente as coletas são inseridas. Entregas e outros serviços do mesmo envio formam uma nova rota; a operação inteira é transacional.
- Sem rota ativa, todos os serviços enviados formam uma nova rota.
- A inserção usa custos direcionais pelas ruas (Mapbox Matrix) e confirma geometria/distância/duração com Directions. Mantém a ordem relativa das paradas existentes e o atendimento já iniciado na primeira posição pendente. Não altera tarefas concluídas nem seus comprovantes e tempos.
- O ponto inicial do cálculo é o GPS recente do motorista (até 5 minutos). Circuitos mantêm o ponto original de retorno. Sem GPS recente, trajeto acessível ou resposta consistente, o rascunho é preservado.
- A API exige gestor da própria empresa, valida o snapshot de status/ordem/chegada sob bloqueio e usa registro privado de idempotência. Duas solicitações simultâneas nunca inserem a mesma coleta duas vezes. Planos vencidos são recalculados uma vez no cliente.
- O aplicativo aberto atualiza a rota a cada 15 segundos e avisa sobre coletas novas. Se estiver em uma tela de atendimento, a atualização ocorre ao retornar. Este aviso não é uma notificação push em segundo plano.

## Validação de 20/10/2026

- PostgreSQL local: 99 verificações em instalação nova e atualização; 7 cenários com conexões independentes por instalação; 3 verificações de preservação de migrações.
- Dashboard: build TypeScript/Vite e 15 testes de inserção, envio, métricas viárias e tempos de atendimento.
- Aplicativo: análise estática sem problemas e 64 testes, incluindo recebimento periódico na mesma rota.
- Migração `20261020161811` aplicada com autorização ao projeto `vblwuvhdqgzdjnoscyqo`. Verificação reversível no banco confirmou incorporação, preservação da chegada e das tarefas concluídas, idempotência e privilégios restritos. Todos os registros de teste foram revertidos.
- APK debug 0.1.17+18 em Downloads; SHA-256 `F913F00692D4D6F00D210EA31F1FC7F3064E0472D44E04239FDFBE257A5AB5A6`.
