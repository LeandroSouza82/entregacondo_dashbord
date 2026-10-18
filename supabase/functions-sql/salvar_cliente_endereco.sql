-- Salva endereços somente para gestores aprovados da empresa ativa.
CREATE OR REPLACE FUNCTION public.salvar_cliente_endereco(p_dados JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_empresa UUID := public.fn_safe_uuid(p_dados->>'empresa_id'); v_item public.clientes_enderecos; v_lat NUMERIC; v_lng NUMERIC;
BEGIN
 IF public.fn_usuario_e_gestor_empresa(v_empresa, auth.uid()) IS NOT TRUE THEN
   RETURN jsonb_build_object('sucesso', false, 'mensagem', 'Acesso de gestão obrigatório nesta empresa.');
 END IF;
 IF NULLIF(trim(p_dados->>'nome_identificador'),'') IS NULL OR NULLIF(trim(p_dados->>'endereco_completo'),'') IS NULL THEN
   RETURN jsonb_build_object('sucesso',false,'mensagem','Nome e endereço são obrigatórios.');
 END IF;
 v_lat := (p_dados->>'latitude')::numeric; v_lng := (p_dados->>'longitude')::numeric;
 IF v_lat IS NULL OR v_lng IS NULL OR NOT (v_lat BETWEEN -90 AND 90) OR NOT (v_lng BETWEEN -180 AND 180) THEN
   RETURN jsonb_build_object('sucesso',false,'mensagem','Coordenadas inválidas.');
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(v_empresa::text || lower(trim(p_dados->>'nome_identificador')) || lower(trim(p_dados->>'endereco_completo')),0));
 SELECT * INTO v_item FROM public.clientes_enderecos WHERE empresa_id=v_empresa
   AND lower(nome_identificador)=lower(trim(p_dados->>'nome_identificador')) AND lower(endereco_completo)=lower(trim(p_dados->>'endereco_completo')) LIMIT 1;
 IF NOT FOUND THEN
   INSERT INTO public.clientes_enderecos(empresa_id,nome_identificador,destinatario_padrao,endereco_completo,numero,bairro,cidade,cep,latitude,longitude,tipo_local,observacoes_acesso)
   VALUES(v_empresa,trim(p_dados->>'nome_identificador'),NULLIF(trim(p_dados->>'destinatario_padrao'),''),trim(p_dados->>'endereco_completo'),COALESCE(p_dados->>'numero',''),COALESCE(p_dados->>'bairro',''),COALESCE(p_dados->>'cidade',''),COALESCE(p_dados->>'cep',''),v_lat,v_lng,COALESCE(p_dados->>'tipo_local','condominio_horizontal'),p_dados->>'observacoes_acesso') RETURNING * INTO v_item;
 END IF;
 RETURN jsonb_build_object('sucesso',true,'cliente',to_jsonb(v_item));
END; $$;
REVOKE ALL ON FUNCTION public.salvar_cliente_endereco(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.salvar_cliente_endereco(JSONB) TO authenticated;
