-- Executar apenas no EntregaCondo após implantar a função e seus segredos.
-- Cadastre pelo Vault da interface o segredo entregacondo_push_worker,
-- com o mesmo valor privado de PUSH_WORKER_SECRET da Edge Function.
-- Nunca salvar o valor real no Git ou no aplicativo.
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_cron;
-- Não cole credenciais no editor SQL: consultas podem ser salvas no histórico.
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM cron.job WHERE jobname='entregacondo-push-retry') THEN
  PERFORM cron.schedule('entregacondo-push-retry','* * * * *','SELECT public.fn_acordar_push_worker();');
 END IF;
END $$;
