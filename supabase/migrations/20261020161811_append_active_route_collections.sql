-- Atomic dispatch: collections join the active route; deliveries/other tasks form a new route.
CREATE TABLE IF NOT EXISTS public.operacoes_envio_motorista (
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 chave varchar(80) NOT NULL,
 payload_hash text NOT NULL,
 resultado jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(empresa_id,chave)
);
ALTER TABLE public.operacoes_envio_motorista ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.operacoes_envio_motorista FROM PUBLIC,anon,authenticated;
-- Results are accessed through the authenticated management RPC, never by direct writes.
CREATE INDEX IF NOT EXISTS idx_rotas_motorista_ativas ON public.rotas_planejadas(empresa_id,motorista_id) WHERE status='em_execucao';
CREATE OR REPLACE FUNCTION public.enviar_servicos_motorista(p_dados jsonb,p_plano_coletas jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $function$
DECLARE
 company uuid := (p_dados->>'empresa_id')::uuid;
 driver uuid := (p_dados->>'motorista_id')::uuid;
 request_key text := btrim(p_dados->>'idempotency_key');
 request_hash text;
 previous public.operacoes_envio_motorista%ROWTYPE;
 active_route public.rotas_planejadas%ROWTYPE;
 driver_row public.motoristas%ROWTYPE;
 collections jsonb; regular jsonb; new_payload jsonb;
 result jsonb; new_result jsonb; route_count integer; count_new integer:=0;
 expected_keys text[]; requested_keys text[]; pinned uuid[]; new_ids jsonb:='{}';
 item record; key_item record; delivery_id uuid; slot integer:=0; gps jsonb; metric jsonb;
BEGIN
 IF auth.uid() IS NULL OR public.fn_usuario_e_gestor_empresa(company,auth.uid()) IS NOT TRUE THEN
  RETURN jsonb_build_object('sucesso',false,'codigo','ACESSO_NEGADO','mensagem','Apenas a gestão da empresa pode enviar serviços.');
 END IF;
 IF company IS NULL OR driver IS NULL OR request_key IS NULL OR length(request_key) NOT BETWEEN 1 AND 80
 OR jsonb_typeof(p_dados->'paradas') IS DISTINCT FROM 'array' OR jsonb_array_length(p_dados->'paradas') NOT BETWEEN 1 AND 500 THEN
  RETURN jsonb_build_object('sucesso',false,'codigo','DADOS_INVALIDOS','mensagem','Informe motorista, chave de envio e de 1 a 500 paradas.');
 END IF;
 -- Same request is serialized before checking its journal. Hash excludes volatile route/GPS metrics.
 PERFORM pg_advisory_xact_lock(hashtextextended(company::text||':envio:'||request_key,0));
 PERFORM pg_advisory_xact_lock(hashtextextended(company::text||':'||driver::text,0));
 request_hash:=encode(sha256(convert_to(jsonb_build_object('motorista_id',driver,'paradas',p_dados->'paradas')::text,'UTF8')),'hex');
 SELECT * INTO previous FROM public.operacoes_envio_motorista WHERE empresa_id=company AND chave=request_key;
 IF FOUND THEN
  IF previous.payload_hash<>request_hash THEN RETURN jsonb_build_object('sucesso',false,'codigo','CONFLITO_IDEMPOTENCIA','mensagem','Este envio já foi processado com outros serviços. Atualize o painel.'); END IF;
  RETURN previous.resultado||jsonb_build_object('idempotente',true);
 END IF;
 SELECT * INTO driver_row FROM public.motoristas WHERE id=driver AND empresa_id=company AND ativo;
 IF NOT FOUND THEN RAISE EXCEPTION 'Motorista não encontrado ou inativo na empresa.'; END IF;
 SELECT COALESCE(jsonb_agg(value ORDER BY ord) FILTER(WHERE value->>'tipo_tarefa'='coleta'),'[]'),
        COALESCE(jsonb_agg(value ORDER BY ord) FILTER(WHERE COALESCE(value->>'tipo_tarefa','entrega')<>'coleta'),'[]')
 INTO collections,regular FROM jsonb_array_elements(p_dados->'paradas') WITH ORDINALITY p(value,ord);
 IF jsonb_array_length(collections)>0 THEN
  SELECT count(*) INTO route_count FROM public.rotas_planejadas WHERE empresa_id=company AND motorista_id=driver AND status='em_execucao';
  IF route_count>1 THEN RAISE EXCEPTION 'O motorista possui mais de uma rota em andamento. Regularize a rota ativa antes de inserir coletas.'; END IF;
  SELECT * INTO active_route FROM public.rotas_planejadas WHERE empresa_id=company AND motorista_id=driver AND status='em_execucao' FOR UPDATE;
 END IF;
 IF active_route.id IS NULL AND p_plano_coletas IS NOT NULL THEN
  RETURN jsonb_build_object('sucesso',false,'codigo','PLANO_DESATUALIZADO','mensagem','A rota em andamento mudou. Recalcule o envio.');
 END IF;
 IF active_route.id IS NOT NULL THEN
  IF p_plano_coletas IS NULL THEN RETURN jsonb_build_object('sucesso',false,'codigo','PLANO_COLETAS_NECESSARIO','mensagem','Calcule a inserção das coletas na rota em andamento.'); END IF;
  IF (p_plano_coletas->>'rota_id')::uuid<>active_route.id OR public.fn_usuario_pode_operar_motorista(company,driver) IS NOT TRUE THEN RAISE EXCEPTION 'Rota ativa indisponível para receber coletas.'; END IF;
  gps:=p_plano_coletas->'origem';metric:=p_plano_coletas->'metricas';
  IF driver_row.localizacao_atualizada_em IS NULL OR driver_row.localizacao_atualizada_em<now()-interval '5 minutes'
    OR driver_row.latitude_atual IS NULL OR driver_row.longitude_atual IS NULL THEN RAISE EXCEPTION 'Sem GPS recente do motorista. Ative o compartilhamento de localização durante a rota e tente novamente.'; END IF;
  IF jsonb_typeof(gps->'lat') IS DISTINCT FROM 'number' OR jsonb_typeof(gps->'lng') IS DISTINCT FROM 'number'
   OR abs((gps->>'lat')::numeric-driver_row.latitude_atual)>0.0015 OR abs((gps->>'lng')::numeric-driver_row.longitude_atual)>0.0015 THEN
   RETURN jsonb_build_object('sucesso',false,'codigo','PLANO_DESATUALIZADO','mensagem','O motorista mudou de posição. Recalcule o envio.'); END IF;
  IF metric->>'fonte' IS DISTINCT FROM 'mapbox_directions_restante' OR (metric->>'distancia_km') IS NULL OR (metric->>'tempo_minutos') IS NULL
   OR NOT ((metric->>'distancia_km')::numeric BETWEEN 0 AND 999999) OR NOT ((metric->>'tempo_minutos')::numeric BETWEEN 0 AND 999999) THEN RAISE EXCEPTION 'O cálculo viário da rota ativa está indisponível.'; END IF;
  -- Match the route/stop lock order of reordering; an arrival or completion invalidates the planning snapshot.
  PERFORM id FROM public.entregas WHERE rota_id=active_route.id ORDER BY id FOR UPDATE;
  IF jsonb_typeof(p_plano_coletas->'snapshot') IS DISTINCT FROM 'array' OR EXISTS(
    SELECT 1 FROM (SELECT id,status,ordem_na_rota,chegada_em FROM public.entregas WHERE rota_id=active_route.id AND empresa_id=company) e
    FULL JOIN jsonb_to_recordset(p_plano_coletas->'snapshot') s(id uuid,status text,ordem_na_rota int,chegada_em timestamptz)
      ON e.id=s.id WHERE e.id IS NULL OR s.id IS NULL OR e.status IS DISTINCT FROM s.status OR e.ordem_na_rota IS DISTINCT FROM s.ordem_na_rota OR e.chegada_em IS DISTINCT FROM s.chegada_em
  ) OR (SELECT count(*) FROM jsonb_array_elements(p_plano_coletas->'snapshot'))<>(SELECT count(DISTINCT value->>'id') FROM jsonb_array_elements(p_plano_coletas->'snapshot')) THEN
   RETURN jsonb_build_object('sucesso',false,'codigo','PLANO_DESATUALIZADO','mensagem','Uma parada mudou enquanto o envio era calculado. Recalcule sem perder os serviços.');
  END IF;
  SELECT COALESCE(array_agg(id ORDER BY ordem_na_rota,id),'{}'::uuid[]) INTO pinned FROM public.entregas WHERE rota_id=active_route.id AND status NOT IN ('entregue','tentativa_falha','cancelada') AND chegada_em IS NOT NULL;
  IF cardinality(pinned)>1 THEN RAISE EXCEPTION 'Há mais de um atendimento aberto nesta rota. Finalize o atendimento pendente.'; END IF;
  SELECT array_agg(k ORDER BY k) INTO expected_keys FROM (
   SELECT id::text k FROM public.entregas WHERE rota_id=active_route.id AND status NOT IN ('entregue','tentativa_falha','cancelada')
   UNION ALL SELECT 'nova:'||(ord-1)::text FROM jsonb_array_elements(p_dados->'paradas') WITH ORDINALITY p(value,ord) WHERE value->>'tipo_tarefa'='coleta'
  ) t;
  IF jsonb_typeof(p_plano_coletas->'ordem') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Informe a ordem calculada das paradas.'; END IF;
  SELECT array_agg(value ORDER BY value) INTO requested_keys FROM jsonb_array_elements_text(p_plano_coletas->'ordem');
  IF requested_keys IS DISTINCT FROM expected_keys OR cardinality(requested_keys)>500 THEN RAISE EXCEPTION 'A ordem deve conter todas as paradas pendentes e coletas novas uma única vez.'; END IF;
  IF cardinality(pinned)=1 AND p_plano_coletas->'ordem'->>0 IS DISTINCT FROM pinned[1]::text THEN RAISE EXCEPTION 'O atendimento atual deve permanecer na primeira posição pendente.'; END IF;
  -- Insert only collections, directly into the existing route; no transient route or phantom notification.
  FOR item IN SELECT value,ord-1 AS idx FROM jsonb_array_elements(p_dados->'paradas') WITH ORDINALITY p(value,ord) WHERE value->>'tipo_tarefa'='coleta' LOOP
   IF NOT EXISTS(SELECT 1 FROM public.clientes_enderecos WHERE id=(item.value->>'cliente_endereco_id')::uuid AND empresa_id=company) THEN RAISE EXCEPTION 'Endereço da coleta não pertence à empresa.'; END IF;
   delivery_id:=gen_random_uuid();
   INSERT INTO public.entregas(id,empresa_id,rota_id,motorista_id,cliente_endereco_id,codigo_rastreio,destinatario_nome,destinatario_telefone,unidade_apartamento,status,prioridade,tipo_tarefa,descricao_outro,peso_kg,volumes_qtd,observacoes_gestor)
   VALUES(delivery_id,company,active_route.id,driver,(item.value->>'cliente_endereco_id')::uuid,COALESCE(NULLIF(btrim(item.value->>'codigo_rastreio'),''),'EC-'||substr(delivery_id::text,1,8)),COALESCE(NULLIF(btrim(item.value->>'destinatario_nome'),''),'Responsável pela coleta'),item.value->>'destinatario_telefone',item.value->>'unidade_apartamento','atribuida',COALESCE(item.value->>'prioridade','normal'),'coleta',item.value->>'descricao_outro',(item.value->>'peso_kg')::numeric,COALESCE((item.value->>'volumes_qtd')::int,1),item.value->>'observacoes_gestor');
   new_ids:=new_ids||jsonb_build_object('nova:'||item.idx::text,delivery_id);count_new:=count_new+1;
  END LOOP;
  FOR key_item IN SELECT value FROM jsonb_array_elements_text(p_plano_coletas->'ordem') LOOP
   LOOP
    slot:=slot+1;
    EXIT WHEN NOT EXISTS(SELECT 1 FROM public.entregas WHERE rota_id=active_route.id AND status IN ('entregue','tentativa_falha','cancelada') AND ordem_na_rota=slot);
   END LOOP;
   delivery_id:=CASE WHEN key_item.value LIKE 'nova:%' THEN (new_ids->>key_item.value)::uuid ELSE key_item.value::uuid END;
   UPDATE public.entregas SET ordem_na_rota=slot,updated_at=now() WHERE id=delivery_id AND rota_id=active_route.id;
  END LOOP;
  UPDATE public.rotas_planejadas SET metricas_fonte='mapbox_directions_restante',metricas_atualizadas_em=now(),distancia_otimizada_km=(metric->>'distancia_km')::numeric,tempo_otimizado_minutos=(metric->>'tempo_minutos')::numeric,
    configuracao_navegacao=configuracao_navegacao||jsonb_build_object('origem_atual',gps,'origem_atual_em',now(),'metricas',metric),
    ordem_paradas_json=(SELECT jsonb_agg(to_jsonb(e)||jsonb_build_object('sequencia',e.ordem_na_rota,'destinatario',e.destinatario_nome,'nome_local',c.nome_identificador,'endereco_formatado',c.endereco_completo,'coordenadas',jsonb_build_object('lat',c.latitude,'lng',c.longitude)) ORDER BY e.ordem_na_rota,e.id) FROM public.entregas e JOIN public.clientes_enderecos c ON c.id=e.cliente_endereco_id AND c.empresa_id=e.empresa_id WHERE e.rota_id=active_route.id)
   WHERE id=active_route.id;
 END IF;
 IF active_route.id IS NULL OR jsonb_array_length(regular)>0 THEN
  new_payload:=p_dados;
  IF active_route.id IS NOT NULL THEN
   SELECT jsonb_agg(value||jsonb_build_object('ordem_na_rota',ord) ORDER BY ord) INTO regular FROM jsonb_array_elements(regular) WITH ORDINALITY p(value,ord);
   new_payload:=p_dados||jsonb_build_object('paradas',regular,'idempotency_key',request_key||':nova','ordem_paradas_json',(SELECT COALESCE(jsonb_agg(value ORDER BY ord),'[]') FROM jsonb_array_elements(COALESCE(p_dados->'ordem_paradas_json','[]')) WITH ORDINALITY p(value,ord) WHERE COALESCE(value->>'tipo_tarefa','entrega')<>'coleta'));
   IF p_plano_coletas->'metricas_nova_rota' IS NULL THEN RAISE EXCEPTION 'Calcule a nova rota das entregas separadamente das coletas.'; END IF;
   new_payload:=new_payload||(p_plano_coletas->'metricas_nova_rota');
  END IF;
  IF new_payload->>'metricas_fonte' IS DISTINCT FROM 'mapbox_directions_planejamento' OR COALESCE((new_payload->>'distancia_otimizada_km')::numeric,0)<=0 OR COALESCE((new_payload->>'tempo_otimizado_minutos')::numeric,0)<=0 THEN RAISE EXCEPTION 'Tempo e distância da nova rota indisponíveis. Aguarde o cálculo viário; os serviços foram preservados.'; END IF;
  new_result:=public.despachar_rota_transacional(new_payload);
  IF new_result->>'sucesso' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION '%',COALESCE(new_result->>'mensagem','A nova rota não foi confirmada.'); END IF;
 END IF;
 result:=jsonb_build_object('sucesso',true,'codigo','SERVICOS_ENVIADOS','idempotente',false,'rota_ativa_id',active_route.id,'nova_rota_id',new_result->>'rota_id','coletas_adicionadas',count_new,'mensagem',CASE WHEN count_new>0 THEN count_new||' coleta(s) inserida(s) na rota em andamento.'||CASE WHEN new_result IS NOT NULL THEN ' Entregas e outros serviços enviados em uma nova rota.' ELSE '' END ELSE 'Serviços enviados em uma nova rota.' END);
 INSERT INTO public.operacoes_envio_motorista(empresa_id,chave,payload_hash,resultado) VALUES(company,request_key,request_hash,result);
 RETURN result;
EXCEPTION WHEN OTHERS THEN
 -- Subtransaction rolls back every insertion/reorder/new route before exposing a safe failure.
 RETURN jsonb_build_object('sucesso',false,'codigo','ENVIO_NAO_CONFIRMADO','mensagem',SQLERRM);
END $function$;
REVOKE ALL ON FUNCTION public.enviar_servicos_motorista(jsonb,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.enviar_servicos_motorista(jsonb,jsonb) TO authenticated;
