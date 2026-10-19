# Correção da conclusão de tarefa

A RPC `registrar_conclusao_entrega` usa `clientes_enderecos.tempo_medio_minutos`.
A captura do aplicativo informa SQLSTATE 42703 para essa coluna. O schema
canônico já define a coluna, mas a instalação remota está divergente.

A migração `align_delivery_completion_statistics` adiciona somente os campos
ausentes requeridos no endereço. Se os campos de média ou contagem forem novos,
os inicializa a partir de `historico_atendimentos`; valores existentes são
preservados. A RPC mantém sua autorização e seu contrato, exige motivo em
tentativas sem sucesso, rejeita horários invertidos e trata reenvios de um
mesmo resultado como sucesso sem inserir histórico ou recalcular média outra vez.
Tentar trocar o resultado de uma tarefa finalizada exige processo separado.

## Validação local executada

Foi usado PostgreSQL embarcado PGlite, em banco descartável e sem conexão externa.
O script `scripts/test_delivery_completion.mjs` passou nos cenários: colunas
ausentes, reconstrução do histórico, reaplicação sem sobrescrita, conclusão,
reenvio idempotente, resultado conflitante, motivo obrigatório, falha com motivo
persistido e negativa de autorização. Os helpers de autenticação/autorização
são stubs somente no banco de teste; isso não valida RLS ou Auth reais.

Para reproduzir, instalar `@electric-sql/pglite@0.5.10` em diretório temporário e
executar o script com `PGLITE_MODULE` apontando para `dist/index.js` desse pacote.
Nenhuma dependência do aplicativo foi alterada para essa verificação.

## Aplicação e validação remota pendentes

Aplicar no projeto novo `vblwuvhdqgzdjnoscyqo`, após revisar seu estado e histórico
de migrações. Esse projeto não consta na conexão Supabase disponível nesta sessão.
Não foi feita migração, consulta de dados, deploy ou alteração do V10 antigo.

Após aplicar, conferir as três colunas de endereço, permissões de execução da
RPC e os dois fluxos reais com uma tarefa de teste: sucesso e tentativa sem
sucesso. Reenviar a mesma conclusão deve manter apenas um registro de histórico
para aquela tarefa. Conferir também um usuário sem autorização operacional.
Não declarar a correção concluída em produção antes dessa validação.
