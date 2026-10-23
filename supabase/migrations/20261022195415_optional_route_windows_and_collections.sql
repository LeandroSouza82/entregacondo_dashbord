-- Optional planning rules. Legacy time columns/data remain untouched.
CREATE SCHEMA IF NOT EXISTS ec_private;
REVOKE ALL ON SCHEMA ec_private FROM PUBLIC,anon,authenticated;
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

-- ==============================================================================
-- FUNÇÃO SQL: despachar_rota_transacional.sql
-- Despacho atômico e idempotente de rotas sob alta concorrência.
-- Bloqueio FOR UPDATE, coluna dedicada idempotency_key e detecção de conflitos.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.despachar_rota_transacional(
    p_dados JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_empresa_id UUID;
    v_motorista_id UUID;
    v_idempotency_key VARCHAR(100);
    v_payload_hash VARCHAR(64);
    v_rota_existente RECORD;
    v_motorista RECORD;
    v_rota_id UUID;
    v_parada RECORD;
    v_paradas JSONB;
    v_distancia_orig NUMERIC(8, 2);
    v_tempo_orig NUMERIC(8, 2);
    v_distancia_otim NUMERIC(8, 2);
    v_tempo_otim NUMERIC(8, 2);
    v_economia_dist NUMERIC(5, 2) := 0;
    v_economia_tempo NUMERIC(5, 2) := 0;
    v_ordem_json JSONB;
    v_idx INT := 0;
BEGIN
    -- 1. Extração dos identificadores obrigatórios
    v_empresa_id := (p_dados->>'empresa_id')::UUID;
    v_motorista_id := (p_dados->>'motorista_id')::UUID;
    v_idempotency_key := TRIM(p_dados->>'idempotency_key');
    v_paradas := p_dados->'paradas';

    IF v_empresa_id IS NULL OR v_motorista_id IS NULL THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'DADOS_OBRIGATORIOS_AUSENTES',
            'mensagem', 'empresa_id e motorista_id são obrigatórios.'
        );
    END IF;

    IF v_idempotency_key IS NULL OR v_idempotency_key = '' THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'CHAVE_IDEMPOTENCIA_OBRIGATORIA',
            'mensagem', 'Chave de operação (idempotency_key) não informada.'
        );
    END IF;

    IF v_paradas IS NULL OR jsonb_array_length(v_paradas) = 0 THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'PARADAS_VAZIAS',
            'mensagem', 'A rota deve conter pelo menos uma parada.'
        );
    END IF;

    -- 2. VALIDAÇÃO DE AUTORIZAÇÃO ANTES DE QUALQUER LEITURA OU BLOQUEIO
    IF NOT public.fn_usuario_e_gestor_empresa(v_empresa_id, auth.uid()) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Apenas gestores autorizados desta empresa podem despachar rotas.'
        );
    END IF;

    -- 3. Cálculo de hash do payload para conferência de consistência
    v_payload_hash := encode(sha256(convert_to(p_dados::text, 'UTF8')), 'hex');

    -- 4. Serialização sob concorrência: bloqueia a linha do motorista
    SELECT * INTO v_motorista
    FROM public.motoristas
    WHERE id = v_motorista_id AND empresa_id = v_empresa_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'MOTORISTA_NAO_ENCONTRADO',
            'mensagem', 'Motorista não encontrado na empresa especificada.'
        );
    END IF;

    IF NOT v_motorista.ativo THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'MOTORISTA_INATIVO',
            'mensagem', 'O motorista selecionado está inativo ou suspenso.'
        );
    END IF;

    -- 5. Tratamento de Idempotência: busca rota com a mesma chave na mesma empresa
    SELECT * INTO v_rota_existente
    FROM public.rotas_planejadas
    WHERE empresa_id = v_empresa_id AND idempotency_key = v_idempotency_key;

    IF FOUND THEN
        -- Se o hash coincidir, retorna a rota já existente sem duplicar
        IF v_rota_existente.payload_hash = v_payload_hash OR v_rota_existente.payload_hash IS NULL THEN
            RETURN jsonb_build_object(
                'sucesso', TRUE,
                'codigo', 'ROTA_JA_DESPACHADA',
                'mensagem', 'Rota já processada anteriormente (idempotência atendida).',
                'rota_id', v_rota_existente.id,
                'idempotente', TRUE
            );
        ELSE
            -- Mesma chave com payload divergente: CONFLITO EXPLÍCITO
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'CONFLITO_IDEMPOTENCIA',
                'mensagem', 'A chave de operação fornecida já foi utilizada com dados diferentes.'
            );
        END IF;
    END IF;

    -- 6. Extração e cálculo de métricas
    v_distancia_orig := COALESCE((p_dados->>'distancia_original_km')::NUMERIC, 0);
    v_tempo_orig := COALESCE((p_dados->>'tempo_original_minutos')::NUMERIC, 0);
    v_distancia_otim := COALESCE((p_dados->>'distancia_otimizada_km')::NUMERIC, 0);
    v_tempo_otim := COALESCE((p_dados->>'tempo_otimizado_minutos')::NUMERIC, 0);

    IF v_distancia_orig > 0 THEN
        v_economia_dist := ROUND(((v_distancia_orig - v_distancia_otim) / v_distancia_orig * 100), 2);
    END IF;
    IF v_tempo_orig > 0 THEN
        v_economia_tempo := ROUND(((v_tempo_orig - v_tempo_otim) / v_tempo_orig * 100), 2);
    END IF;

    v_ordem_json := COALESCE(p_dados->'ordem_paradas_json', '[]'::jsonb);

    -- 7. Criação da Rota Planejada (Atômica)
    INSERT INTO public.rotas_planejadas (
        empresa_id,
        motorista_id,
        idempotency_key,
        payload_hash,
        status,
        distancia_original_km,
        tempo_original_minutos,
        distancia_otimizada_km,
        tempo_otimizado_minutos,
        percentual_economia_km,
        percentual_economia_tempo,
        ordem_paradas_json,
        metricas_fonte,
        metricas_atualizadas_em
    ) VALUES (
        v_empresa_id,
        v_motorista_id,
        v_idempotency_key,
        v_payload_hash,
        'planejada',
        v_distancia_orig,
        v_tempo_orig,
        v_distancia_otim,
        v_tempo_otim,
        v_economia_dist,
        v_economia_tempo,
        v_ordem_json,
        CASE WHEN p_dados->>'metricas_fonte'='mapbox_directions_planejamento' AND v_distancia_otim>0 AND v_tempo_otim>0 THEN 'mapbox_directions_planejamento' END,
        CASE WHEN p_dados->>'metricas_fonte'='mapbox_directions_planejamento' AND v_distancia_otim>0 AND v_tempo_otim>0 THEN now() END
    )
    RETURNING id INTO v_rota_id;

    -- 8. Inserção das Entregas/Paradas vinculadas à rota
    FOR v_parada IN SELECT * FROM jsonb_to_recordset(v_paradas) AS x(
        id UUID,
        janela_data DATE, janela_inicio TIME, janela_fim TIME, coleta_origem_id UUID, tempo_atendimento_previsto_min INT,
        cliente_endereco_id UUID,
        destinatario_nome TEXT,
        destinatario_telefone TEXT,
        unidade_apartamento TEXT,
        codigo_rastreio TEXT,
        tipo_tarefa TEXT,
        descricao_outro TEXT,
        peso_kg NUMERIC,
        volumes_qtd INT,
        prioridade TEXT,
        ordem_na_rota INT,
        observacoes_gestor TEXT
    )
    LOOP
        v_idx := v_idx + 1;

        -- Valida se o cliente_endereco pertence à mesma empresa
        IF NOT EXISTS (
            SELECT 1 FROM public.clientes_enderecos
            WHERE id = v_parada.cliente_endereco_id AND empresa_id = v_empresa_id
        ) THEN
            RAISE EXCEPTION 'Endereço de cliente % não pertence à empresa do despacho.', v_parada.cliente_endereco_id;
        END IF;

        INSERT INTO public.entregas (
            id,janela_data,janela_inicio,janela_fim,coleta_origem_id,tempo_atendimento_previsto_min,
            empresa_id,
            rota_id,
            motorista_id,
            cliente_endereco_id,
            codigo_rastreio,
            destinatario_nome,
            destinatario_telefone,
            unidade_apartamento,
            status,
            prioridade,
            tipo_tarefa,
            descricao_outro,
            peso_kg,
            volumes_qtd,
            ordem_na_rota,
            observacoes_gestor
        ) VALUES (
            COALESCE(v_parada.id,gen_random_uuid()),v_parada.janela_data,v_parada.janela_inicio,v_parada.janela_fim,v_parada.coleta_origem_id,COALESCE(v_parada.tempo_atendimento_previsto_min,0),
            v_empresa_id,
            v_rota_id,
            v_motorista_id,
            v_parada.cliente_endereco_id,
            COALESCE(NULLIF(TRIM(v_parada.codigo_rastreio), ''), 'EC-' || SUBSTRING(gen_random_uuid()::text, 1, 8)),
            COALESCE(NULLIF(TRIM(v_parada.destinatario_nome), ''), 'Morador/Recepção'),
            v_parada.destinatario_telefone,
            v_parada.unidade_apartamento,
            'atribuida',
            COALESCE(v_parada.prioridade, 'normal'),
            COALESCE(v_parada.tipo_tarefa, 'entrega'),
            v_parada.descricao_outro,
            v_parada.peso_kg,
            COALESCE(v_parada.volumes_qtd, 1),
            COALESCE(v_parada.ordem_na_rota, v_idx),
            v_parada.observacoes_gestor
        );
    END LOOP;

    PERFORM ec_private.validar_agenda(
      (SELECT array_agg(id ORDER BY ordem_na_rota,id) FROM public.entregas WHERE rota_id=v_rota_id),
      p_dados->'agenda',(p_dados->>'planejamento_saida_em')::timestamptz,false);

    -- 9. Atualiza status do motorista para em_rota
    UPDATE public.motoristas
    SET status = 'em_rota',
        updated_at = timezone('utc'::text, now())
    WHERE id = v_motorista_id;

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'ROTA_DESPACHADA',
        'mensagem', 'Rota e paradas despachadas com sucesso.',
        'rota_id', v_rota_id,
        'total_paradas', v_idx,
        'idempotente', FALSE
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.aceitar_pedidos_motorista(p_ids uuid[]) RETURNS jsonb
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
REVOKE ALL ON FUNCTION public.aceitar_pedidos_motorista(uuid[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.aceitar_pedidos_motorista(uuid[]) TO authenticated;
ALTER TABLE public.rotas_planejadas ADD COLUMN IF NOT EXISTS metricas_fonte text;
ALTER TABLE public.rotas_planejadas ADD COLUMN IF NOT EXISTS metricas_atualizadas_em timestamptz;
ALTER TABLE public.rotas_planejadas ADD COLUMN IF NOT EXISTS configuracao_navegacao jsonb NOT NULL DEFAULT '{}'::jsonb;
-- Reorder only unfinished stops; preserve completed stops and reject stale edits.
CREATE OR REPLACE FUNCTION public.reordenar_paradas_rota(
    p_rota_id uuid, p_entrega_ids uuid[], p_ordem_esperada uuid[], p_configuracao jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_rota public.rotas_planejadas%ROWTYPE;
    v_current uuid[];
    v_slots integer[];
    v_metricas jsonb;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('sucesso',false,'mensagem','Entre novamente na sua conta.');
    END IF;
    SELECT * INTO v_rota FROM public.rotas_planejadas WHERE id=p_rota_id FOR UPDATE;
    IF NOT FOUND OR public.fn_usuario_pode_operar_motorista(v_rota.empresa_id,v_rota.motorista_id) IS NOT TRUE THEN
        RETURN jsonb_build_object('sucesso',false,'mensagem','Acesso negado à rota.');
    END IF;
    IF v_rota.status NOT IN ('planejada','em_execucao') THEN
        RETURN jsonb_build_object('sucesso',false,'mensagem','Esta rota já foi finalizada.');
    END IF;
    IF p_configuracao IS NOT NULL THEN
      IF jsonb_typeof(p_configuracao) <> 'object'
         OR jsonb_typeof(p_configuracao->'latitude') IS DISTINCT FROM 'number'
         OR jsonb_typeof(p_configuracao->'longitude') IS DISTINCT FROM 'number'
         OR jsonb_typeof(p_configuracao->'retornar_ao_inicio') IS DISTINCT FROM 'boolean'
         OR (p_configuracao->>'latitude')::numeric NOT BETWEEN -90 AND 90
         OR (p_configuracao->>'longitude')::numeric NOT BETWEEN -180 AND 180
         OR COALESCE(p_configuracao->>'metodo','') NOT IN ('manual','vizinho_proximo','circuito_2opt') THEN
        RETURN jsonb_build_object('sucesso',false,'mensagem','Origem de navegação inválida. Atualize a posição do motorista.');
      END IF;
    END IF;
    v_metricas := p_configuracao->'metricas';
    IF v_metricas IS NOT NULL AND (
      jsonb_typeof(v_metricas) <> 'object'
      OR jsonb_typeof(v_metricas->'distancia_km') IS DISTINCT FROM 'number'
      OR jsonb_typeof(v_metricas->'tempo_minutos') IS DISTINCT FROM 'number'
      OR (v_metricas->>'distancia_km')::numeric NOT BETWEEN 0.01 AND 999999
      OR (v_metricas->>'tempo_minutos')::numeric NOT BETWEEN 0.01 AND 999999
      OR v_metricas->>'fonte' IS DISTINCT FROM 'mapbox_directions_restante'
    ) THEN
      RETURN jsonb_build_object('sucesso',false,'mensagem','Métricas viárias inválidas. Recalcule a rota.');
    END IF;
    PERFORM id FROM public.entregas WHERE rota_id=p_rota_id ORDER BY id FOR UPDATE;
    SELECT COALESCE(array_agg(id ORDER BY ordem_na_rota NULLS LAST,id),'{}'::uuid[]),
           COALESCE(array_agg(pos ORDER BY ordem_na_rota NULLS LAST,id),'{}'::integer[])
    INTO v_current,v_slots
    FROM (
      SELECT id,status,ordem_na_rota,row_number() OVER (ORDER BY ordem_na_rota NULLS LAST,id)::integer AS pos
      FROM public.entregas WHERE rota_id=p_rota_id AND empresa_id=v_rota.empresa_id
    ) x WHERE status NOT IN ('entregue','tentativa_falha','cancelada')
      AND NOT EXISTS(SELECT 1 FROM public.pedidos_fluxo f WHERE f.entrega_id=x.id AND f.etapa<>'liberado');
    IF p_ordem_esperada IS DISTINCT FROM v_current THEN
        RETURN jsonb_build_object('sucesso',false,'codigo','ORDEM_DESATUALIZADA','mensagem','A rota mudou. Atualize e organize novamente.');
    END IF;
    IF p_entrega_ids IS NULL OR cardinality(p_entrega_ids)>500
       OR (SELECT array_agg(id ORDER BY id) FROM unnest(p_entrega_ids) id)
          IS DISTINCT FROM (SELECT array_agg(id ORDER BY id) FROM unnest(v_current) id) THEN
        RETURN jsonb_build_object('sucesso',false,'mensagem','Informe todas as paradas pendentes, sem duplicar ou adicionar paradas.');
    END IF;
    IF EXISTS(SELECT 1 FROM public.entregas e WHERE e.id=ANY(v_current) AND e.chegada_em IS NOT NULL AND e.id IS DISTINCT FROM p_entrega_ids[1]) THEN
      RETURN jsonb_build_object('sucesso',false,'mensagem','Mantenha o atendimento em andamento na primeira posição.');
    END IF;
    IF EXISTS(SELECT 1 FROM public.entregas child JOIN public.entregas parent ON parent.id=child.coleta_origem_id AND parent.empresa_id=child.empresa_id
      WHERE child.id=ANY(v_current) AND parent.status<>'entregue' AND
      (array_position(p_entrega_ids,parent.id) IS NULL OR array_position(p_entrega_ids,parent.id)>=array_position(p_entrega_ids,child.id))) THEN
      RETURN jsonb_build_object('sucesso',false,'mensagem','Conclua a coleta vinculada ou coloque-a antes da entrega.');
    END IF;
    PERFORM ec_private.validar_agenda(p_entrega_ids,p_configuracao->'agenda',(p_configuracao->>'planejamento_saida_em')::timestamptz,true);
    UPDATE public.entregas e SET ordem_na_rota=v_slots[requested.pos::integer],updated_at=now()
    FROM unnest(p_entrega_ids) WITH ORDINALITY AS requested(id,pos)
    WHERE e.id=requested.id AND e.rota_id=p_rota_id AND e.empresa_id=v_rota.empresa_id;
    UPDATE public.rotas_planejadas SET
        metricas_fonte=CASE WHEN v_metricas IS NOT NULL THEN 'mapbox_directions_restante' END,
        metricas_atualizadas_em=CASE WHEN v_metricas IS NOT NULL THEN now() END,
        distancia_otimizada_km=COALESCE((v_metricas->>'distancia_km')::numeric,distancia_otimizada_km),
        tempo_otimizado_minutos=COALESCE((v_metricas->>'tempo_minutos')::numeric,tempo_otimizado_minutos),
        configuracao_navegacao=COALESCE(p_configuracao,configuracao_navegacao), ordem_paradas_json=(
        SELECT COALESCE(jsonb_agg(to_jsonb(e) || jsonb_build_object(
            'sequencia',e.ordem_na_rota,'destinatario',e.destinatario_nome,
            'nome_local',COALESCE(to_jsonb(c)->>'nome_identificador',e.unidade_apartamento),
            'endereco_formatado',COALESCE(to_jsonb(e)->>'endereco',previous.value->>'endereco_formatado',to_jsonb(c)->>'endereco_completo'),
            'coordenadas',jsonb_build_object('lat',COALESCE(NULLIF(to_jsonb(e)->'latitude','null'::jsonb),NULLIF(to_jsonb(c)->'latitude','null'::jsonb),previous.value->'coordenadas'->'lat'),'lng',COALESCE(NULLIF(to_jsonb(e)->'longitude','null'::jsonb),NULLIF(to_jsonb(c)->'longitude','null'::jsonb),previous.value->'coordenadas'->'lng'))
        ) ORDER BY e.ordem_na_rota,e.id),'[]'::jsonb)
        FROM public.entregas e LEFT JOIN public.clientes_enderecos c ON c.id=e.cliente_endereco_id AND c.empresa_id=e.empresa_id
        LEFT JOIN LATERAL (
          SELECT value FROM jsonb_array_elements(v_rota.ordem_paradas_json) value
          WHERE value->>'id'=e.id::text OR value->>'cliente_endereco_id'=e.cliente_endereco_id::text LIMIT 1
        ) previous ON true
        WHERE e.rota_id=p_rota_id AND e.empresa_id=v_rota.empresa_id
    ) WHERE id=p_rota_id;
    RETURN jsonb_build_object('sucesso',true,'codigo','ORDEM_ATUALIZADA','mensagem','Ordem salva. O mapa foi atualizado.');
END;
$$;
REVOKE ALL ON FUNCTION public.reordenar_paradas_rota(uuid,uuid[],uuid[],jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reordenar_paradas_rota(uuid,uuid[],uuid[],jsonb) TO authenticated;
-- Keep the existing three-argument API for manual reorder clients.
CREATE OR REPLACE FUNCTION public.reordenar_paradas_rota(p_rota_id uuid,p_entrega_ids uuid[],p_ordem_esperada uuid[])
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=public AS $compat$
SELECT public.reordenar_paradas_rota(p_rota_id,p_entrega_ids,p_ordem_esperada,NULL::jsonb);
$compat$;
REVOKE ALL ON FUNCTION public.reordenar_paradas_rota(uuid,uuid[],uuid[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reordenar_paradas_rota(uuid,uuid[],uuid[]) TO authenticated;

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
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_dados->'paradas') p WHERE
   NULLIF(p->>'janela_data','') IS NOT NULL OR NULLIF(p->>'coleta_origem_id','') IS NOT NULL) THEN
  RETURN jsonb_build_object('sucesso',false,'codigo','USE_ENVIO_PEDIDOS','mensagem','Envie pedidos com condições pelo fluxo de aceite do motorista.');
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

CREATE OR REPLACE FUNCTION ec_private.tracking_active(p_entrega uuid,p_rota uuid,p_motorista uuid)
RETURNS boolean LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT EXISTS(
  SELECT 1 FROM public.entregas e
  JOIN public.rotas_planejadas r ON r.id=e.rota_id AND r.empresa_id=e.empresa_id AND r.motorista_id=e.motorista_id
  JOIN public.motoristas m ON m.id=e.motorista_id AND m.empresa_id=e.empresa_id AND m.ativo
  JOIN public.empresas c ON c.id=e.empresa_id AND c.ativa
  JOIN public.empresa_membros em ON em.empresa_id=e.empresa_id AND em.user_id=m.user_id AND em.motorista_id=m.id AND em.status='aprovado' AND em.papel='motorista'
  WHERE e.id=p_entrega AND e.rota_id=p_rota AND e.motorista_id=p_motorista
   AND r.status='em_execucao' AND e.status NOT IN ('entregue','tentativa_falha','cancelada')
   AND (e.coleta_origem_id IS NULL OR EXISTS(SELECT 1 FROM public.entregas p WHERE p.id=e.coleta_origem_id AND p.empresa_id=e.empresa_id AND p.status='entregue'))
   AND NOT EXISTS(SELECT 1 FROM public.pedidos_fluxo f WHERE f.entrega_id=e.id AND f.etapa<>'liberado')
   AND e.id=(SELECT x.id FROM public.entregas x WHERE x.rota_id=r.id AND x.empresa_id=r.empresa_id
    AND x.status NOT IN ('entregue','tentativa_falha','cancelada')
    AND (x.coleta_origem_id IS NULL OR EXISTS(SELECT 1 FROM public.entregas p WHERE p.id=x.coleta_origem_id AND p.empresa_id=x.empresa_id AND p.status='entregue'))
    AND NOT EXISTS(SELECT 1 FROM public.pedidos_fluxo f WHERE f.entrega_id=x.id AND f.etapa<>'liberado')
    ORDER BY (x.chegada_em IS NOT NULL) DESC,x.ordem_na_rota NULLS LAST,x.id LIMIT 1)
 );
$$;
REVOKE ALL ON FUNCTION ec_private.tracking_active(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;
NOTIFY pgrst, 'reload schema';
