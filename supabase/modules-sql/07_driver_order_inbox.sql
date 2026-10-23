-- New dispatches are offers. Existing deliveries remain available without backfill.
CREATE TABLE public.pedidos_fluxo (
 entrega_id uuid PRIMARY KEY REFERENCES public.entregas(id),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 motorista_id uuid NOT NULL REFERENCES public.motoristas(id),
 lote_id uuid NOT NULL REFERENCES public.rotas_planejadas(id),
 etapa text NOT NULL DEFAULT 'ofertado' CHECK(etapa IN ('ofertado','aguardando_retirada','liberado')),
 aceito_em timestamptz,
 retirado_em timestamptz
);
ALTER TABLE public.pedidos_fluxo ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pedidos_fluxo FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.pedidos_fluxo TO authenticated;
CREATE POLICY pedidos_fluxo_leitura ON public.pedidos_fluxo FOR SELECT TO authenticated
USING(public.fn_usuario_pode_operar_motorista(empresa_id,motorista_id) OR public.fn_usuario_e_gestor_empresa(empresa_id,auth.uid()));

CREATE FUNCTION public.enviar_pedidos_motorista(p_dados jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE r jsonb; rid uuid; company uuid := (p_dados->>'empresa_id')::uuid; driver uuid := (p_dados->>'motorista_id')::uuid; k text:=p_dados->>'idempotency_key'; h text;
BEGIN
 IF auth.uid() IS NULL OR public.fn_usuario_e_gestor_empresa(company,auth.uid()) IS NOT TRUE THEN RAISE EXCEPTION 'Acesso negado'; END IF;
 IF k IS NULL OR length(k) NOT BETWEEN 1 AND 80 THEN RAISE EXCEPTION 'Chave de envio inválida'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(company::text||':envio:'||k,0));
 h:=encode(sha256(convert_to(jsonb_build_object('motorista_id',driver,'paradas',p_dados->'paradas')::text,'UTF8')),'hex');
 SELECT resultado INTO r FROM public.operacoes_envio_motorista WHERE empresa_id=company AND chave=k AND payload_hash=h;
 IF FOUND THEN RETURN r||jsonb_build_object('idempotente',true); END IF;
 IF EXISTS(SELECT 1 FROM public.operacoes_envio_motorista WHERE empresa_id=company AND chave=k) THEN RAISE EXCEPTION 'Envio já utilizado com outros pedidos'; END IF;
 r:=public.despachar_rota_transacional(p_dados);
 IF r->>'sucesso' IS DISTINCT FROM 'true' THEN RETURN r; END IF;
 rid:=(r->>'rota_id')::uuid;
 INSERT INTO public.pedidos_fluxo(entrega_id,empresa_id,motorista_id,lote_id)
 SELECT id,empresa_id,motorista_id,rota_id FROM public.entregas WHERE rota_id=rid ON CONFLICT DO NOTHING;
 r:=r||jsonb_build_object('nova_rota_id',rid,'codigo','PEDIDOS_OFERTADOS','mensagem','Pedidos enviados para aceite do motorista.');
 INSERT INTO public.operacoes_envio_motorista VALUES(company,k,h,r,now());
 RETURN r;
END $$;

CREATE FUNCTION public.aceitar_pedidos_motorista(p_ids uuid[]) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE f public.pedidos_fluxo%ROWTYPE; target public.rotas_planejadas%ROWTYPE; item record; n integer; snapshot jsonb;
BEGIN
 IF auth.uid() IS NULL OR cardinality(p_ids) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Pedidos inválidos'; END IF;
 SELECT * INTO f FROM public.pedidos_fluxo WHERE entrega_id=p_ids[1];
 IF NOT FOUND OR public.fn_usuario_pode_operar_motorista(f.empresa_id,f.motorista_id) IS NOT TRUE OR NOT EXISTS(SELECT 1 FROM public.motoristas WHERE id=f.motorista_id AND empresa_id=f.empresa_id AND user_id=auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(f.empresa_id::text||':'||f.motorista_id::text,0));
 IF EXISTS(SELECT 1 FROM unnest(p_ids) requested(id) WHERE NOT EXISTS(SELECT 1 FROM public.pedidos_fluxo x JOIN public.entregas e ON e.id=x.entrega_id JOIN public.rotas_planejadas r ON r.id=e.rota_id WHERE x.entrega_id=requested.id AND x.empresa_id=f.empresa_id AND x.motorista_id=f.motorista_id AND e.motorista_id=f.motorista_id AND e.empresa_id=f.empresa_id AND r.status IN ('planejada','em_execucao'))) THEN RAISE EXCEPTION 'Pedidos alterados; atualize'; END IF;
 SELECT r.* INTO target FROM public.rotas_planejadas r WHERE r.empresa_id=f.empresa_id AND r.motorista_id=f.motorista_id AND r.status IN ('planejada','em_execucao') AND EXISTS(SELECT 1 FROM public.entregas e LEFT JOIN public.pedidos_fluxo x ON x.entrega_id=e.id WHERE e.rota_id=r.id AND (x.entrega_id IS NULL OR x.etapa<>'ofertado')) ORDER BY (r.status='em_execucao') DESC,r.created_at,r.id LIMIT 1 FOR UPDATE;
 IF NOT FOUND THEN SELECT r.* INTO target FROM public.rotas_planejadas r JOIN public.entregas e ON e.rota_id=r.id WHERE e.id=p_ids[1] FOR UPDATE OF r; END IF;
 SELECT COALESCE(max(ordem_na_rota),0) INTO n FROM public.entregas WHERE rota_id=target.id;
 FOR item IN SELECT e.*,r.ordem_paradas_json FROM public.entregas e JOIN public.rotas_planejadas r ON r.id=e.rota_id JOIN public.pedidos_fluxo x ON x.entrega_id=e.id WHERE e.id=ANY(p_ids) AND x.etapa='ofertado' ORDER BY e.ordem_na_rota,e.id FOR UPDATE OF e LOOP
  IF item.rota_id<>target.id THEN
   SELECT value INTO snapshot FROM jsonb_array_elements(COALESCE(item.ordem_paradas_json,'[]')) WHERE value->>'id'=item.id::text OR value->>'cliente_endereco_id'=item.cliente_endereco_id::text LIMIT 1;
   n:=n+1;
   UPDATE public.entregas SET rota_id=target.id,ordem_na_rota=n WHERE id=item.id;
   IF snapshot IS NOT NULL THEN UPDATE public.rotas_planejadas SET ordem_paradas_json=COALESCE(ordem_paradas_json,'[]')||jsonb_build_array(snapshot||jsonb_build_object('id',item.id,'sequencia',n)) WHERE id=target.id; END IF;
  END IF;
  UPDATE public.pedidos_fluxo SET etapa=CASE WHEN item.tipo_tarefa='entrega' AND item.coleta_origem_id IS NULL THEN 'aguardando_retirada' ELSE 'liberado' END,aceito_em=now() WHERE entrega_id=item.id;
 END LOOP;
 -- Preserve linked pickups before their deliveries, even on partial batch acceptance.
 IF EXISTS(SELECT 1 FROM public.entregas WHERE rota_id=target.id AND (coleta_origem_id IS NOT NULL OR janela_data IS NOT NULL)) THEN
  PERFORM ec_private.encaixar_coletas_vinculadas(target.id);
  UPDATE public.rotas_planejadas SET metricas_fonte=NULL,metricas_atualizadas_em=NULL,ordem_paradas_json=(
   SELECT COALESCE(jsonb_agg(to_jsonb(e)||jsonb_build_object('sequencia',e.ordem_na_rota,'destinatario',e.destinatario_nome,
    'nome_local',c.nome_identificador,'endereco_formatado',c.endereco_completo,
    'coordenadas',jsonb_build_object('lat',c.latitude,'lng',c.longitude)) ORDER BY e.ordem_na_rota,e.id),'[]'::jsonb)
   FROM public.entregas e JOIN public.clientes_enderecos c ON c.id=e.cliente_endereco_id AND c.empresa_id=e.empresa_id WHERE e.rota_id=target.id
  ) WHERE id=target.id;
 END IF;
 -- Empty send containers are not another driver route.
 UPDATE public.rotas_planejadas r SET status='concluida' WHERE r.empresa_id=f.empresa_id AND r.motorista_id=f.motorista_id AND r.id<>target.id AND r.status='planejada' AND EXISTS(SELECT 1 FROM public.pedidos_fluxo x WHERE x.lote_id=r.id) AND NOT EXISTS(SELECT 1 FROM public.entregas e WHERE e.rota_id=r.id);
 RETURN jsonb_build_object('sucesso',true,'rota_id',target.id);
END $$;

-- Test phase: explicit manual confirmation. No GPS/geofence requirement is claimed.
CREATE FUNCTION public.confirmar_retirada_pedidos(p_ids uuid[]) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE f public.pedidos_fluxo%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR cardinality(p_ids) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Pedidos inválidos'; END IF;
 SELECT * INTO f FROM public.pedidos_fluxo WHERE entrega_id=p_ids[1];
 IF NOT FOUND OR public.fn_usuario_pode_operar_motorista(f.empresa_id,f.motorista_id) IS NOT TRUE OR NOT EXISTS(SELECT 1 FROM public.motoristas WHERE id=f.motorista_id AND empresa_id=f.empresa_id AND user_id=auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(f.empresa_id::text||':'||f.motorista_id::text,0));
 IF EXISTS(SELECT 1 FROM unnest(p_ids) requested(id) WHERE NOT EXISTS(SELECT 1 FROM public.pedidos_fluxo x JOIN public.entregas e ON e.id=x.entrega_id WHERE x.entrega_id=requested.id AND x.empresa_id=f.empresa_id AND x.motorista_id=f.motorista_id AND e.empresa_id=f.empresa_id AND e.motorista_id=f.motorista_id AND x.etapa IN ('aguardando_retirada','liberado'))) THEN RAISE EXCEPTION 'Pedido não aceito ou acesso negado'; END IF;
 UPDATE public.pedidos_fluxo SET etapa='liberado',retirado_em=now() WHERE entrega_id=ANY(p_ids) AND etapa='aguardando_retirada';
 RETURN jsonb_build_object('sucesso',true);
END $$;

CREATE FUNCTION public.fn_proteger_pedido_sem_retirada() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF (NEW.chegada_em IS DISTINCT FROM OLD.chegada_em OR (NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('entregue','tentativa_falha'))) AND EXISTS(SELECT 1 FROM public.pedidos_fluxo WHERE entrega_id=NEW.id AND etapa<>'liberado') THEN RAISE EXCEPTION 'Aceite o pedido e confirme a retirada antes de atender'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER proteger_pedido_sem_retirada BEFORE UPDATE ON public.entregas FOR EACH ROW EXECUTE FUNCTION public.fn_proteger_pedido_sem_retirada();
REVOKE ALL ON FUNCTION public.enviar_pedidos_motorista(jsonb),public.aceitar_pedidos_motorista(uuid[]),public.confirmar_retirada_pedidos(uuid[]),public.fn_proteger_pedido_sem_retirada() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.enviar_pedidos_motorista(jsonb),public.aceitar_pedidos_motorista(uuid[]),public.confirmar_retirada_pedidos(uuid[]) TO authenticated;
