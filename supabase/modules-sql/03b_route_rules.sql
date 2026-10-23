-- Optional planning rules. Legacy time columns/data remain untouched.
CREATE SCHEMA IF NOT EXISTS ec_private;
REVOKE ALL ON SCHEMA ec_private FROM PUBLIC,anon,authenticated;
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS janela_inicio time;
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS janela_fim time;
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS janela_data date;
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS coleta_origem_id uuid;
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS tempo_atendimento_previsto_min integer NOT NULL DEFAULT 0;
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS janela_inicio_em timestamptz
 GENERATED ALWAYS AS ((janela_data+janela_inicio) AT TIME ZONE 'America/Sao_Paulo') STORED;
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS janela_fim_em timestamptz
 GENERATED ALWAYS AS ((janela_data+janela_fim) AT TIME ZONE 'America/Sao_Paulo') STORED;
ALTER TABLE public.entregas ADD CONSTRAINT entregas_empresa_id_id_unique UNIQUE(empresa_id,id);
ALTER TABLE public.entregas ADD CONSTRAINT entregas_coleta_origem_fk
 FOREIGN KEY(empresa_id,coleta_origem_id) REFERENCES public.entregas(empresa_id,id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE public.entregas ADD CONSTRAINT entregas_janela_planejada_check
 CHECK(janela_data IS NULL OR (janela_inicio IS NOT NULL AND janela_fim IS NOT NULL AND janela_fim>janela_inicio));
ALTER TABLE public.entregas ADD CONSTRAINT entregas_atendimento_previsto_check CHECK(tempo_atendimento_previsto_min BETWEEN 0 AND 240);
CREATE INDEX entregas_coleta_origem_idx ON public.entregas(empresa_id,coleta_origem_id) WHERE coleta_origem_id IS NOT NULL;

CREATE OR REPLACE FUNCTION ec_private.proteger_regras_rota() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE changed boolean; parent_status text;
BEGIN
 IF TG_OP='INSERT' THEN
  changed:=NEW.janela_data IS NOT NULL OR NEW.coleta_origem_id IS NOT NULL OR NEW.tempo_atendimento_previsto_min<>0;
 ELSE
  changed:=(NEW.janela_data,NEW.janela_inicio,NEW.janela_fim,NEW.coleta_origem_id,NEW.tempo_atendimento_previsto_min)
    IS DISTINCT FROM (OLD.janela_data,OLD.janela_inicio,OLD.janela_fim,OLD.coleta_origem_id,OLD.tempo_atendimento_previsto_min);
  IF changed AND (OLD.chegada_em IS NOT NULL OR OLD.status IN ('entregue','tentativa_falha','cancelada')) THEN
   RAISE EXCEPTION 'Não altere as condições de um atendimento iniciado ou finalizado.';
  END IF;
 END IF;
 IF changed THEN
  IF auth.uid() IS NOT NULL AND public.fn_usuario_e_gestor_empresa(NEW.empresa_id,auth.uid()) IS NOT TRUE THEN
   RAISE EXCEPTION 'Somente a gestão pode definir as condições do pedido.' USING ERRCODE='42501';
  END IF;
  IF NEW.janela_data IS NULL AND (NEW.janela_inicio IS NOT NULL OR NEW.janela_fim IS NOT NULL) THEN
   RAISE EXCEPTION 'Informe a data junto com os dois horários.';
  END IF;
  IF NEW.janela_data IS NOT NULL AND (extract(epoch FROM (NEW.janela_fim-NEW.janela_inicio))/60)<NEW.tempo_atendimento_previsto_min THEN
   RAISE EXCEPTION 'O atendimento previsto não cabe na faixa de horário.';
  END IF;
 END IF;
 IF NEW.coleta_origem_id IS NOT NULL AND NEW.status NOT IN ('tentativa_falha','cancelada') AND
   (TG_OP='INSERT' AND (NEW.chegada_em IS NOT NULL OR NEW.status='entregue') OR
    TG_OP='UPDATE' AND (NEW.chegada_em IS DISTINCT FROM OLD.chegada_em OR NEW.status='entregue' AND OLD.status<>'entregue')) THEN
  SELECT status INTO parent_status FROM public.entregas WHERE id=NEW.coleta_origem_id AND empresa_id=NEW.empresa_id FOR SHARE;
  IF parent_status IS DISTINCT FROM 'entregue' THEN RAISE EXCEPTION 'Conclua a coleta vinculada antes de atender esta entrega.'; END IF;
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION ec_private.proteger_regras_rota() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER entregas_proteger_regras BEFORE INSERT OR UPDATE ON public.entregas FOR EACH ROW EXECUTE FUNCTION ec_private.proteger_regras_rota();

CREATE OR REPLACE FUNCTION ec_private.validar_vinculo_coleta() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE child public.entregas%ROWTYPE; parent public.entregas%ROWTYPE;
BEGIN
 FOR child IN SELECT * FROM public.entregas WHERE empresa_id=NEW.empresa_id AND coleta_origem_id IS NOT NULL AND (id=NEW.id OR coleta_origem_id=NEW.id) ORDER BY id LOOP
  SELECT * INTO parent FROM public.entregas WHERE id=child.coleta_origem_id FOR SHARE;
  IF NOT FOUND OR child.id=parent.id OR child.tipo_tarefa<>'entrega' OR parent.tipo_tarefa<>'coleta'
   OR child.empresa_id<>parent.empresa_id OR child.motorista_id IS DISTINCT FROM parent.motorista_id THEN
   RAISE EXCEPTION 'Vincule a entrega a uma coleta da mesma empresa e do mesmo motorista.';
  END IF;
  IF child.rota_id IS NOT NULL AND child.rota_id=parent.rota_id
   AND child.status NOT IN ('entregue','tentativa_falha','cancelada') AND parent.status NOT IN ('entregue','tentativa_falha','cancelada')
   AND COALESCE(parent.ordem_na_rota,2147483647)>=COALESCE(child.ordem_na_rota,2147483647) THEN
   RAISE EXCEPTION 'A entrega deve ficar depois da coleta vinculada.';
  END IF;
 END LOOP;
 RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION ec_private.validar_vinculo_coleta() FROM PUBLIC,anon,authenticated;
CREATE CONSTRAINT TRIGGER entregas_validar_vinculo AFTER INSERT OR UPDATE ON public.entregas
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ec_private.validar_vinculo_coleta();

CREATE OR REPLACE FUNCTION ec_private.validar_agenda(p_ids uuid[],p_agenda jsonb,p_partida timestamptz,p_atual boolean DEFAULT true)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE item record; visit jsonb; t timestamptz; finish timestamptz; previous timestamptz:=p_partida;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.entregas WHERE id=ANY(p_ids) AND janela_data IS NOT NULL) THEN RETURN; END IF;
 IF p_partida IS NULL OR p_partida<now()-interval '5 minutes' OR (p_atual AND p_partida NOT BETWEEN now()-interval '5 minutes' AND now()+interval '5 minutes')
   OR jsonb_typeof(p_agenda) IS DISTINCT FROM 'array' OR jsonb_array_length(p_agenda)<>cardinality(p_ids) THEN
  RAISE EXCEPTION 'Recalcule os horários antes de salvar ou enviar a rota.';
 END IF;
 FOR item IN SELECT e.*,u.pos FROM unnest(p_ids) WITH ORDINALITY u(id,pos) JOIN public.entregas e ON e.id=u.id ORDER BY u.pos LOOP
  visit:=p_agenda->(item.pos::integer-1);
  IF visit->>'entrega_id' IS DISTINCT FROM item.id::text THEN RAISE EXCEPTION 'A agenda não corresponde à sequência dos pedidos.'; END IF;
  t:=(visit->>'inicio_em')::timestamptz; finish:=(visit->>'fim_em')::timestamptz;
  IF t IS NULL OR finish IS NULL OR t<previous OR finish<t+make_interval(mins=>item.tempo_atendimento_previsto_min)
   OR item.janela_data IS NOT NULL AND (t<item.janela_inicio_em OR finish>item.janela_fim_em) THEN
   RAISE EXCEPTION 'A sequência não cabe nos horários definidos. Recalcule a organização.';
  END IF;
  previous:=finish;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION ec_private.validar_agenda(uuid[],jsonb,timestamptz,boolean) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION ec_private.encaixar_coletas_vinculadas(p_rota uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE ids uuid[]; slots integer[]; item record; i integer; j integer;
BEGIN
 SELECT array_agg(id ORDER BY ordem_na_rota NULLS LAST,id),array_agg(pos ORDER BY ordem_na_rota NULLS LAST,id) INTO ids,slots
 FROM (SELECT id,ordem_na_rota,row_number() OVER(ORDER BY ordem_na_rota NULLS LAST,id)::integer pos,status FROM public.entregas WHERE rota_id=p_rota) e
 WHERE status NOT IN ('entregue','tentativa_falha','cancelada');
 FOR item IN SELECT id,coleta_origem_id FROM public.entregas WHERE rota_id=p_rota AND coleta_origem_id IS NOT NULL ORDER BY ordem_na_rota NULLS LAST,id LOOP
  i:=array_position(ids,item.id); j:=array_position(ids,item.coleta_origem_id);
  IF i IS NOT NULL AND j>i THEN
   ids:=array_remove(ids,item.coleta_origem_id);
   ids:=COALESCE(ids[1:i-1],'{}'::uuid[])||ARRAY[item.coleta_origem_id]||ids[i:cardinality(ids)];
  END IF;
 END LOOP;
 UPDATE public.entregas e SET ordem_na_rota=slots[u.pos::integer] FROM unnest(ids) WITH ORDINALITY u(id,pos) WHERE e.id=u.id;
END $$;
REVOKE ALL ON FUNCTION ec_private.encaixar_coletas_vinculadas(uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.obter_capacidades_rotas() RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre novamente.' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('regras_opcionais',1,'fuso_horarios','America/Sao_Paulo');
END $$;
REVOKE ALL ON FUNCTION public.obter_capacidades_rotas() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.obter_capacidades_rotas() TO authenticated;
