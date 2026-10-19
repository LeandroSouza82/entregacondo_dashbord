# Correção da conclusão e procedência das métricas

Validação em 19/10/2026 na branch `fix/conclusao-falha-metricas-20261019`. PR 1 permanece sem merge. Nenhum deploy do dashboard foi feito.

## Banco existente

Confirmado o projeto novo EntregaCondo `vblwuvhdqgzdjnoscyqo` pelas configurações locais do app e dashboard e pelo SQL Editor autenticado. O conector Supabase disponível não tinha acesso a esse projeto; a aplicação ocorreu pelo SQL Editor do projeto confirmado. Não foi executado o schema completo nem alterado NewV10.

O schema remoto tinha `tempo_medio_atendimento_min`, mas não `tempo_medio_minutos` nem `updated_at` em clientes_enderecos. A migração `20261019175229_align_delivery_completion_statistics.sql` adiciona campos ausentes, inicializa somente média/contagem novas a partir do histórico e aproveita a média legada quando não há histórico. Preserva valores existentes.

A RPC mantém a autorização operacional, exige motivo em falhas, rejeita horários invertidos, bloqueia resultados conflitantes e trata o reenvio do mesmo resultado sem inserir histórico nem recalcular estatísticas. A atualização de entrega, histórico e média é atômica.

Aplicadas em transação as migrações `20261019175229` e `20261019182920`. O remoto não tinha `supabase_migrations.schema_migrations`; foi criado o registro privado padrão com RLS habilitado e somente essas duas versões e seus SQLs. Não foram inventadas entradas para migrações antigas. Em futuras reconciliações com a CLI, revisar o histórico legado antes de aplicar migrações anteriores.

## Planejamento e reordenação

O dashboard consulta Mapbox Directions para distância e duração das sequências original e escolhida. A heurística antiga permanece apenas para sugerir a ordem; seus quilômetros e tempos aproximados não são apresentados nem despachados como estimativas verificadas. Sem resposta viária válida, o despacho é bloqueado e o rascunho permanece.

A migração `20261019182920_route_road_metrics_provenance.sql` adiciona origem e horário das métricas. No despacho, a origem é `mapbox_directions_planejamento`. Na reordenação pelo app, os totais viários da posição atual pelas paradas pendentes são gravados atomicamente com a ordem, como `mapbox_directions_restante`. Reordenação sem novos totais invalida a procedência anterior. Valores antigos são preservados no banco, mas o app não os apresenta como estimativas confiáveis. O resumo do dashboard não mistura estimativas restantes com totais planejados.

As estimativas cobrem deslocamento pelas ruas, sem atendimento nas paradas nem trânsito em tempo real. Não são recalculadas continuamente. Nenhuma chave local foi incluída no código ou na documentação.

## Verificações executadas

- `npm run verify:sql`: equivalência estática e seis contraprovas passaram; 32 funções consistentes.
- `npm run test:db`: 70 regressões em instalação nova e 70 em atualização; catálogo de 32 funções, 18 políticas e seis constraints; cinco cenários concorrentes em cada instalação; três testes de preservação de migração.
- `scripts/test_delivery_completion.mjs` com PGlite temporário: passou para campos ausentes, histórico, reaplicação, conclusão, idempotência, conflito, motivo e autorização simulada. Dependências do produto não foram alteradas.
- `node --test scripts/test_road_metrics.mjs`: quatro testes passaram, incluindo agregação de trechos, duração ausente, erro/cancelamento e falta de token/pontos.
- Consulta real Directions entre dois pontos da rota: 4,408287 km, 10,660883 minutos e geometria com 233 pontos; sem expor a chave.
- `npm run build`: passou. Aviso de tamanho do bundle permanece.
- `supabase/tests/remote_completion_validation.sql`: PASS no projeto novo, usando papel authenticated e helpers reais para conclusão, falha com motivo, reenvio idempotente e usuário sem autorização; execução anônima bloqueada. Todas as fixtures e alterações de estatística desse teste foram revertidas por ROLLBACK.

A validação SQL remota não equivale ao percurso completo via APK e sessão JWT real. Ainda validar no aparelho e na UI autenticada do dashboard: tarefa de teste, atualização dos indicadores, nova rota com métricas e reordenação. O app `0.1.14+15` foi instalado como atualização no celular autorizado, preservando a sessão. Conferidos a abertura da rota e os dois botões fixos acima da navegação; nenhuma tarefa real foi finalizada. A validação end-to-end de conclusão/falha pelo APK ainda está pendente. A documentação do repositório mobile contém caminho e hash do APK. Foto/recebedor da referência 05 e fila offline de conclusões continuam pendentes.


## Fluxo explícito de atendimento — candidata mobile 0.1.15+16

Aplicada com autorização explícita a migração 20261019190203_delivery_receipt_workflow. Cria chegada explícita, comprovante imutável e bucket privado, com funções autorizadas que gravam segundos reais e acionam o histórico estatístico atomicamente. O teste remoto remote_receipt_validation.sql passou com rollback: chegada não reinicia, 95 segundos chegam ao histórico, recebedor obrigatório, reenvio idempotente e acesso restrito. Os testes locais passaram: 77 regressões em cada instalação, equivalência de schema, concorrência e duas verificações de estimativa por motorista/endereço. O dashboard compila e calcula atendimento com comprovantes reais; valores legados fictícios não entram nessa estimativa. Em locais sem histórico do motorista, usa amostras reais do local e informa a cobertura incompleta.

Security Advisor consultado pelo navegador: zero erros e 60 avisos na instalação remota, incluindo políticas RLS legadas permissivas em clientes_enderecos, empresa_membros, empresas, entregas, perfis_usuarios e rotas_planejadas, além de funções antigas expostas. As políticas novas são restritas, mas esses avisos precisam de correção específica antes de considerar o projeto inteiro seguro. Não foi feita uma substituição cega das permissões antigas neste trabalho.

A candidata APK foi instalada por atualização sem limpar dados; 60 testes Flutter e analyze passaram. Foto/assinatura reais ainda requerem validação com tarefa de teste no aparelho. A próxima rodada visual usa os oito HTMLs/PNGs enviados e preserva o cronômetro.
