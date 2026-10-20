# Notificações de rotas e coletas

Ativado em 20/10/2026 exclusivamente no Supabase `vblwuvhdqgzdjnoscyqo` e Firebase `entregacondo-push-2026`.

O envio transacional de serviços grava uma fila privada por dispositivo no mesmo commit da operação. Rotas novas usam “Nova rota chegou”; coletas inseridas na rota ativa usam “Nova coleta chegou”. O APK contém três bipes rápidos seguidos de voz em português. A ativação é individual em Perfil → Avisos de rota.

## Servidor

- Migração aplicada: `20261020164412_route_push_notifications`.
- Função `push-servicos`, com `verify_jwt=false` e autenticação obrigatória pelo cabeçalho `x-push-worker-secret`; sem segredo válido responde 401.
- Segredos da função: `FIREBASE_SERVICE_ACCOUNT` e `PUSH_WORKER_SECRET`. Nunca registrar os valores em SQL, logs, APK ou Git.
- Vault: `entregacondo_push_worker`, cadastrado pela interface do cofre, com o mesmo valor de `PUSH_WORKER_SECRET`.
- `pg_net` e `pg_cron` ativados; job `entregacondo-push-retry` executa a cada minuto. O gatilho também acorda o worker após gravar a fila.
- O script `supabase/tests/configure_push_worker.example.sql` contém apenas configuração, sem credenciais. Não executar os fixtures de teste em produção.
- Conta Firebase `entregacondo-fcm-sender@entregacondo-push-2026.iam.gserviceaccount.com`: papel personalizado `entregacondoFcmSender`, somente `cloudmessaging.messages.create`. Nenhum papel de administrador foi concedido.
- A primeira chave gerada foi revogada. O certificado público substituto foi enviado ao Google; a chave privada ficou apenas no segredo do servidor. Certificado atual vence em **20/10/2027**: substituir antes dessa data, atualizar o segredo e revogar o anterior após validar.

A fila usa leases, SKIP LOCKED, idempotência e novas tentativas com backoff. Token inválido desativa somente o dispositivo correspondente. Aprovação, empresa, motorista e rota são revalidados antes do envio. `aceito_fcm` significa aceito pelo provedor, não comprovação de leitura pelo motorista.

## Validação

- Worker remoto: sem segredo 401; com segredo 200.
- Dois avisos de teste para o próprio aparelho conectado, usando a rota já existente, sem criar ou concluir serviços. O Android recebeu os avisos de rota e coleta; tocar no aviso abriu a rota atribuída. O usuário confirmou os bipes e a voz no aviso real de rota.
- PostgreSQL local: 99 regressões + 15 verificações de push em instalação nova e por migrações, com catálogos equivalentes e os testes concorrentes existentes.
- Node: 21 testes de push, coletas, métricas de estrada e tempo de atendimento passaram. O antigo `test_delivery_completion.mjs` não executa neste checkout por faltar `@electric-sql/pglite`; os fluxos SQL de conclusão são cobertos pela suíte PostgreSQL.
- Flutter: análise sem problemas e 66 testes passaram. APK 0.1.18+19 instalado sem apagar dados.

## Limites operacionais

Sem internet, o Firebase mantém o aviso por até 24 horas e tenta entregá-lo após a reconexão. Silencioso, Não Perturbe, bloqueio de notificações e parada forçada pelo Android podem impedir som ou entrega. Não se contornam essas escolhas do motorista. A voz está no áudio do canal, sem depender de TTS nem de conexão no momento de tocar.

Revisão de permissões remota: anon e authenticated não leem tokens, e authenticated não executa a reivindicação da fila. O Security Advisor ainda aponta problemas anteriores fora deste envio, incluindo a view `public.saved_addresses` com SECURITY DEFINER; isso permanece pendente de auditoria própria.
