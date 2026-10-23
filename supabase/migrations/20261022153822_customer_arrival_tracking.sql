-- Customer arrival tracking. Tokens are bearer secrets; only their SHA-256 is stored.
-- No direct access to the private table, including authenticated dashboard users.
ALTER TABLE public.clientes_enderecos ADD COLUMN IF NOT EXISTS whatsapp_cliente varchar(30);
CREATE SCHEMA IF NOT EXISTS ec_private;
REVOKE ALL ON SCHEMA ec_private FROM PUBLIC, anon, authenticated;
CREATE TABLE IF NOT EXISTS ec_private.customer_tracking (
 entrega_id uuid PRIMARY KEY REFERENCES public.entregas(id) ON DELETE CASCADE,
 rota_id uuid NOT NULL, motorista_id uuid NOT NULL, token_hash bytea NOT NULL UNIQUE,
 cliente_endereco_id uuid NOT NULL, recipient_phone text NOT NULL,
 expires_at timestamptz NOT NULL DEFAULT now()+interval '8 hours',
 latitude double precision, longitude double precision, observed_at timestamptz,
 eta_at timestamptz, eta_observed_at timestamptz
);
ALTER TABLE ec_private.customer_tracking ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ec_private.customer_tracking FROM PUBLIC, anon, authenticated;

-- Also rechecked on EVERY public read: terminal status, reassignment, departure to
-- another stop, membership suspension or route closure immediately hide all GPS.
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
   AND NOT EXISTS(SELECT 1 FROM public.pedidos_fluxo f WHERE f.entrega_id=e.id AND f.etapa<>'liberado')
   AND e.id=(SELECT x.id FROM public.entregas x WHERE x.rota_id=r.id AND x.empresa_id=r.empresa_id
    AND x.status NOT IN ('entregue','tentativa_falha','cancelada')
    AND NOT EXISTS(SELECT 1 FROM public.pedidos_fluxo f WHERE f.entrega_id=x.id AND f.etapa<>'liberado')
    ORDER BY (x.chegada_em IS NOT NULL) DESC,x.ordem_na_rota NULLS LAST,x.id LIMIT 1)
 );
$$;
REVOKE ALL ON FUNCTION ec_private.tracking_active(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.configurar_nome_empresa(p_empresa_id uuid,p_nome text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL OR public.fn_usuario_e_gestor_empresa(p_empresa_id,auth.uid()) IS NOT TRUE THEN
  RAISE EXCEPTION 'Acesso de gestão obrigatório nesta empresa.' USING ERRCODE='42501'; END IF;
 IF p_nome IS NULL OR length(btrim(p_nome)) NOT BETWEEN 2 AND 120 THEN RAISE EXCEPTION 'Informe um nome entre 2 e 120 caracteres.'; END IF;
 UPDATE public.empresas SET nome=btrim(p_nome) WHERE id=p_empresa_id;
 RETURN jsonb_build_object('sucesso',true);
END $$;

CREATE OR REPLACE FUNCTION public.preparar_aviso_cliente(p_entrega_id uuid,p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE e public.entregas%ROWTYPE; h bytea; t ec_private.customer_tracking%ROWTYPE; result jsonb;
BEGIN
 SELECT * INTO e FROM public.entregas WHERE id=p_entrega_id FOR UPDATE;
 IF auth.uid() IS NULL OR NOT FOUND OR public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id) IS NOT TRUE
  OR NOT EXISTS(SELECT 1 FROM public.motoristas m WHERE m.id=e.motorista_id AND m.user_id=auth.uid())
  OR ec_private.tracking_active(e.id,e.rota_id,e.motorista_id) IS NOT TRUE THEN
  RAISE EXCEPTION 'Avise somente o próximo atendimento liberado da sua rota ativa.' USING ERRCODE='42501'; END IF;
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Token inválido.'; END IF;
 IF e.destinatario_telefone IS NULL OR e.destinatario_telefone !~ '^[1-9][0-9]{9,14}$' THEN RAISE EXCEPTION 'WhatsApp do cliente não cadastrado ou inválido.'; END IF;
 h:=sha256(convert_to(p_token,'UTF8'));
 SELECT * INTO t FROM ec_private.customer_tracking WHERE entrega_id=e.id;
 IF t.token_hash=h AND (t.expires_at<=now() OR t.cliente_endereco_id IS DISTINCT FROM e.cliente_endereco_id OR t.recipient_phone IS DISTINCT FROM e.destinatario_telefone) THEN
  RETURN jsonb_build_object('sucesso',false,'codigo','EXPIRADO','mensagem','Gere um novo link.'); END IF;
 -- Repeated taps reuse the same valid link; a new device/token revokes the old one.
 INSERT INTO ec_private.customer_tracking(entrega_id,rota_id,motorista_id,token_hash,cliente_endereco_id,recipient_phone)
 VALUES(e.id,e.rota_id,e.motorista_id,h,e.cliente_endereco_id,e.destinatario_telefone)
 ON CONFLICT(entrega_id) DO UPDATE SET rota_id=EXCLUDED.rota_id,motorista_id=EXCLUDED.motorista_id,
 token_hash=EXCLUDED.token_hash,cliente_endereco_id=EXCLUDED.cliente_endereco_id,recipient_phone=EXCLUDED.recipient_phone,expires_at=now()+interval '8 hours',latitude=NULL,longitude=NULL,observed_at=NULL,eta_at=NULL,eta_observed_at=NULL
 WHERE customer_tracking.token_hash<>EXCLUDED.token_hash OR customer_tracking.rota_id<>EXCLUDED.rota_id OR customer_tracking.motorista_id<>EXCLUDED.motorista_id OR customer_tracking.cliente_endereco_id<>EXCLUDED.cliente_endereco_id OR customer_tracking.recipient_phone<>EXCLUDED.recipient_phone;
 SELECT jsonb_build_object('sucesso',true,'empresa_nome',c.nome,'motorista_nome',COALESCE(NULLIF(btrim(p.nome),''),m.nome),
  'telefone',e.destinatario_telefone,'tipo_tarefa',e.tipo_tarefa,'descricao_outro',e.descricao_outro)
 INTO result FROM public.empresas c JOIN public.motoristas m ON m.id=e.motorista_id LEFT JOIN public.perfis_usuarios p ON p.id=m.user_id WHERE c.id=e.empresa_id;
 RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.obter_meu_acompanhamento(p_rota_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT COALESCE((SELECT jsonb_build_object('sucesso',true,'entrega_id',t.entrega_id,'latitude',a.latitude,'longitude',a.longitude)
 FROM ec_private.customer_tracking t JOIN public.entregas e ON e.id=t.entrega_id
 JOIN public.clientes_enderecos a ON a.id=e.cliente_endereco_id AND a.empresa_id=e.empresa_id
 JOIN public.motoristas m ON m.id=t.motorista_id
 WHERE t.rota_id=p_rota_id AND m.user_id=auth.uid() AND t.expires_at>now()
 AND public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id)
 AND e.cliente_endereco_id=t.cliente_endereco_id AND e.destinatario_telefone=t.recipient_phone
 AND ec_private.tracking_active(e.id,t.rota_id,t.motorista_id) LIMIT 1),'{"sucesso":false}'::jsonb);
$$;

CREATE OR REPLACE FUNCTION public.publicar_localizacao_acompanhamento(p_entrega_id uuid,p_latitude double precision,p_longitude double precision,p_observada_em timestamptz,p_previsao_chegada_em timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL OR p_latitude IS NULL OR p_longitude IS NULL
 OR NOT(p_latitude BETWEEN -90 AND 90) OR NOT(p_longitude BETWEEN -180 AND 180)
 OR p_observada_em IS NULL OR p_observada_em NOT BETWEEN now()-interval '2 minutes' AND now()+interval '30 seconds'
 OR (p_previsao_chegada_em IS NOT NULL AND p_previsao_chegada_em NOT BETWEEN p_observada_em AND p_observada_em+interval '24 hours') THEN
 RETURN jsonb_build_object('sucesso',false); END IF;
 UPDATE ec_private.customer_tracking t SET latitude=p_latitude,longitude=p_longitude,observed_at=p_observada_em,
 eta_at=COALESCE(p_previsao_chegada_em,t.eta_at),eta_observed_at=CASE WHEN p_previsao_chegada_em IS NULL THEN t.eta_observed_at ELSE p_observada_em END
 FROM public.entregas e,public.motoristas m WHERE t.entrega_id=p_entrega_id AND e.id=t.entrega_id AND m.id=e.motorista_id AND m.user_id=auth.uid()
 AND t.expires_at>now() AND (t.observed_at IS NULL OR p_observada_em>t.observed_at)
 AND public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id)
 AND e.cliente_endereco_id=t.cliente_endereco_id AND e.destinatario_telefone=t.recipient_phone
 AND ec_private.tracking_active(e.id,t.rota_id,t.motorista_id);
 RETURN jsonb_build_object('sucesso',FOUND);
END $$;

CREATE OR REPLACE FUNCTION public.obter_acompanhamento_cliente(p_token text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE t ec_private.customer_tracking%ROWTYPE; result jsonb;
BEGIN
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RETURN jsonb_build_object('estado','indisponivel'); END IF;
 SELECT * INTO t FROM ec_private.customer_tracking WHERE token_hash=sha256(convert_to(p_token,'UTF8'));
 IF NOT FOUND THEN RETURN jsonb_build_object('estado','indisponivel'); END IF;
 IF t.expires_at<=now() OR ec_private.tracking_active(t.entrega_id,t.rota_id,t.motorista_id) IS NOT TRUE
 OR NOT EXISTS(SELECT 1 FROM public.entregas e WHERE e.id=t.entrega_id AND e.cliente_endereco_id=t.cliente_endereco_id AND e.destinatario_telefone=t.recipient_phone) THEN
  RETURN jsonb_build_object('estado','encerrado'); END IF;
 SELECT jsonb_build_object('estado','ativo','empresa',c.nome,'tipo_tarefa',e.tipo_tarefa,
  'destino',jsonb_build_object('latitude',a.latitude,'longitude',a.longitude),
  'posicao',CASE WHEN t.observed_at IS NULL THEN NULL ELSE jsonb_build_object('latitude',t.latitude,'longitude',t.longitude) END,
  'atualizada_em',t.observed_at,'previsao_chegada_em',t.eta_at,'previsao_atualizada_em',t.eta_observed_at,'servidor_em',now())
 INTO result FROM public.entregas e JOIN public.empresas c ON c.id=e.empresa_id
 JOIN public.clientes_enderecos a ON a.id=e.cliente_endereco_id AND a.empresa_id=e.empresa_id WHERE e.id=t.entrega_id;
 RETURN COALESCE(result,jsonb_build_object('estado','indisponivel'));
END $$;
REVOKE ALL ON FUNCTION public.configurar_nome_empresa(uuid,text),public.preparar_aviso_cliente(uuid,text),public.obter_meu_acompanhamento(uuid),public.publicar_localizacao_acompanhamento(uuid,double precision,double precision,timestamptz,timestamptz),public.obter_acompanhamento_cliente(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.configurar_nome_empresa(uuid,text),public.preparar_aviso_cliente(uuid,text),public.obter_meu_acompanhamento(uuid),public.publicar_localizacao_acompanhamento(uuid,double precision,double precision,timestamptz,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obter_acompanhamento_cliente(text) TO anon,authenticated;

CREATE OR REPLACE FUNCTION public.salvar_cliente_endereco(p_dados JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_empresa_id UUID;
    v_nome TEXT;
    v_endereco TEXT;
    v_complemento TEXT;
    v_lat NUMERIC;
    v_lng NUMERIC;
    v_place_id TEXT;
    v_tempo_medio INT;
    v_id UUID;
    v_registro public.clientes_enderecos%ROWTYPE;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'NAO_AUTENTICADO', 'mensagem', 'Não autenticado.');
    END IF;

    -- 1. Resolução e validação estrita da empresa do gestor
    v_empresa_id := public.fn_safe_uuid(p_dados->>'empresa_id');
    IF v_empresa_id IS NULL THEN
        SELECT em.empresa_id INTO v_empresa_id
        FROM public.empresa_membros em
        WHERE em.user_id = v_user_id
          AND em.status = 'aprovado'
          AND em.papel IN ('admin', 'gestor')
        LIMIT 1;
    END IF;

    -- Rejeita se não houver empresa ou se o usuário não for gestor autorizado dela
    IF v_empresa_id IS NULL OR public.fn_usuario_e_gestor_empresa(v_empresa_id, v_user_id) IS NOT TRUE THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'ACESSO_NEGADO', 'mensagem', 'Acesso de gestão obrigatório nesta empresa.');
    END IF;

    IF p_dados ? 'whatsapp_cliente' AND NULLIF(p_dados->>'whatsapp_cliente','') IS NOT NULL AND p_dados->>'whatsapp_cliente' !~ '^[1-9][0-9]{9,14}$' THEN
        RETURN jsonb_build_object('sucesso',false,'mensagem','WhatsApp inválido.');
    END IF;

    -- 2. Extrai o nome/label aceitando qualquer variação enviada pelo frontend
    v_nome := TRIM(COALESCE(
        p_dados->>'nome_identificador',
        p_dados->>'label',
        p_dados->>'nome',
        p_dados->>'nome_cliente',
        p_dados->>'cliente_nome',
        p_dados->>'condominio',
        p_dados->>'destinatario_padrao',
        split_part(p_dados->>'full_address', ',', 1),
        split_part(p_dados->>'endereco_completo', ',', 1),
        split_part(p_dados->>'endereco', ',', 1)
    ));

    -- 3. Extrai o endereço aceitando variações
    v_endereco := TRIM(COALESCE(
        p_dados->>'full_address',
        p_dados->>'endereco_completo',
        p_dados->>'endereco',
        p_dados->>'logradouro'
    ));

    -- 4. Extrai complemento / observações de acesso
    v_complemento := NULLIF(TRIM(COALESCE(
        p_dados->>'observacoes_acesso',
        p_dados->>'complemento',
        p_dados->>'bloco_apartamento'
    )), '');

    -- 5. Extrai coordenadas aceitando variações lat/lng e latitude/longitude
    v_lat := (COALESCE(p_dados->>'latitude', p_dados->>'lat'))::NUMERIC;
    v_lng := (COALESCE(p_dados->>'longitude', p_dados->>'lng'))::NUMERIC;

    IF v_lat IS NULL OR v_lng IS NULL OR NOT (v_lat BETWEEN -90 AND 90) OR NOT (v_lng BETWEEN -180 AND 180) THEN
        v_lat := -27.5954;
        v_lng := -48.5480;
    END IF;

    v_place_id := NULLIF(TRIM(COALESCE(p_dados->>'place_id', p_dados->>'placeId')), '');

    v_tempo_medio := COALESCE(
        (p_dados->>'tempo_medio_minutos')::INT,
        (p_dados->>'tempo_medio_atendimento_min')::INT,
        15
    );

    IF v_nome IS NULL OR v_nome = '' THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'DADOS_INVALIDOS', 'mensagem', 'Nome do cliente ou condomínio é obrigatório.');
    END IF;

    IF v_endereco IS NULL OR v_endereco = '' THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'DADOS_INVALIDOS', 'mensagem', 'Endereço é obrigatório.');
    END IF;

    -- Lock transacional para evitar duplicação concorrente do mesmo condomínio
    PERFORM pg_advisory_xact_lock(hashtextextended(v_empresa_id::text || lower(v_nome) || lower(v_endereco), 0));

    -- Verifica se foi fornecido ID específico ou se o registro já existe pelo nome/endereço
    v_id := public.fn_safe_uuid(p_dados->>'id');

    IF v_id IS NOT NULL THEN
        UPDATE public.clientes_enderecos
        SET 
            whatsapp_cliente = CASE WHEN p_dados ? 'whatsapp_cliente' THEN NULLIF(p_dados->>'whatsapp_cliente','') ELSE whatsapp_cliente END,
            nome_identificador = v_nome,
            endereco_completo = v_endereco,
            latitude = v_lat,
            longitude = v_lng,
            place_id = COALESCE(v_place_id, place_id),
            tempo_medio_minutos = v_tempo_medio,
            observacoes_acesso = COALESCE(v_complemento, observacoes_acesso),
            updated_at = timezone('utc'::text, now())
        WHERE id = v_id AND empresa_id = v_empresa_id
        RETURNING * INTO v_registro;
    END IF;

    IF v_registro.id IS NULL THEN
        SELECT * INTO v_registro
        FROM public.clientes_enderecos
        WHERE empresa_id = v_empresa_id
          AND (lower(nome_identificador) = lower(v_nome) AND lower(endereco_completo) = lower(v_endereco))
        LIMIT 1;

        IF v_registro.id IS NOT NULL THEN
            UPDATE public.clientes_enderecos
            SET 
                whatsapp_cliente = CASE WHEN p_dados ? 'whatsapp_cliente' THEN NULLIF(p_dados->>'whatsapp_cliente','') ELSE whatsapp_cliente END,
                latitude = v_lat,
                longitude = v_lng,
                place_id = COALESCE(v_place_id, place_id),
                tempo_medio_minutos = v_tempo_medio,
                observacoes_acesso = COALESCE(v_complemento, observacoes_acesso),
                updated_at = timezone('utc'::text, now())
            WHERE id = v_registro.id
            RETURNING * INTO v_registro;
        ELSE
            INSERT INTO public.clientes_enderecos (
                empresa_id,
                nome_identificador,
                destinatario_padrao,
                whatsapp_cliente,
                endereco_completo,
                numero,
                bairro,
                cidade,
                cep,
                latitude,
                longitude,
                place_id,
                tempo_medio_minutos,
                total_entregas_realizadas,
                tipo_local,
                observacoes_acesso,
                created_at,
                updated_at
            ) VALUES (
                v_empresa_id,
                v_nome,
                p_dados->>'destinatario_padrao',
                NULLIF(p_dados->>'whatsapp_cliente',''),
                v_endereco,
                COALESCE(p_dados->>'numero', ''),
                COALESCE(p_dados->>'bairro', ''),
                COALESCE(p_dados->>'cidade', 'Florianópolis'),
                COALESCE(p_dados->>'cep', '88000-000'),
                v_lat,
                v_lng,
                v_place_id,
                v_tempo_medio,
                0,
                COALESCE(p_dados->>'tipo_local', 'condominio_horizontal'),
                v_complemento,
                timezone('utc'::text, now()),
                timezone('utc'::text, now())
            )
            RETURNING * INTO v_registro;
        END IF;
    END IF;

    RETURN to_jsonb(v_registro) || jsonb_build_object(
        'id',v_registro.id,
        'nome',v_registro.nome_identificador,
        'endereco',v_registro.endereco_completo,
        'sucesso', true,
        'mensagem', 'Endereço salvo com sucesso no banco de dados.',
        'cliente', row_to_json(v_registro)
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.salvar_cliente_endereco(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.salvar_cliente_endereco(jsonb) TO authenticated;
