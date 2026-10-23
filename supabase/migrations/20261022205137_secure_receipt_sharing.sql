-- Compatibility endpoint for authenticated operations. UUID alone is never public authorization.
CREATE OR REPLACE FUNCTION public.obter_comprovante_publico(p_entrega_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre na sua conta.' USING ERRCODE='42501'; END IF;
 SELECT jsonb_build_object('sucesso',true,'entrega_id',cp.entrega_id,'destinatario_nome',e.destinatario_nome,
  'endereco',COALESCE(to_jsonb(e)->>'endereco',a.endereco_completo),'empresa_nome',c.nome,
  'recebedor_tipo',cp.recebedor_tipo,'recebedor_nome',cp.recebedor_nome,'observacao',cp.observacao,
  'foto_path',cp.foto_path,'assinatura_path',cp.assinatura_path,'concluida_em',cp.concluida_em,'duracao_segundos',cp.duracao_segundos)
 INTO result FROM public.entrega_comprovantes cp JOIN public.entregas e ON e.id=cp.entrega_id AND e.empresa_id=cp.empresa_id
 JOIN public.empresas c ON c.id=cp.empresa_id LEFT JOIN public.clientes_enderecos a ON a.id=e.cliente_endereco_id AND a.empresa_id=e.empresa_id
 WHERE cp.entrega_id=p_entrega_id AND public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id) IS TRUE;
 RETURN COALESCE(result,'{"sucesso":false}'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.obter_comprovante_publico(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.obter_comprovante_publico(uuid) TO authenticated;

-- A share is scoped to one immutable receipt; the bucket itself remains private.
DROP POLICY IF EXISTS comprovante_publico_download ON storage.objects;
UPDATE storage.buckets SET public=false WHERE id='entregas-comprovantes';
CREATE SCHEMA IF NOT EXISTS ec_private;
REVOKE ALL ON SCHEMA ec_private FROM PUBLIC,anon,authenticated;
CREATE TABLE IF NOT EXISTS ec_private.receipt_shares (
 entrega_id uuid PRIMARY KEY REFERENCES public.entrega_comprovantes(entrega_id) ON DELETE CASCADE,
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 criado_por uuid NOT NULL REFERENCES auth.users(id),
 token_hash bytea NOT NULL UNIQUE CHECK(octet_length(token_hash)=32),
 expires_at timestamptz NOT NULL,
 foto_url text, assinatura_url text
);
CREATE INDEX IF NOT EXISTS receipt_shares_empresa_idx ON ec_private.receipt_shares(empresa_id);
CREATE INDEX IF NOT EXISTS receipt_shares_criado_por_idx ON ec_private.receipt_shares(criado_por);
ALTER TABLE ec_private.receipt_shares ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ec_private.receipt_shares FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION ec_private.receipt_url_matches(p_url text,p_path text) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT COALESCE(p_url IS NOT NULL AND p_path IS NOT NULL AND length(p_url)<=8192
  AND p_url ~ '^https://[a-zA-Z0-9.-]+(:[0-9]+)?/storage/v1/object/sign/entregas-comprovantes/'
  AND split_part(split_part(p_url,'?',1),'/storage/v1/object/sign/entregas-comprovantes/',2)=p_path
  AND p_url ~ '[?]token=[A-Za-z0-9_.-]+$',false);
$$;
REVOKE ALL ON FUNCTION ec_private.receipt_url_matches(text,text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.criar_compartilhamento_comprovante(
 p_entrega_id uuid,p_token text,p_foto_url text DEFAULT NULL,p_assinatura_url text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE cp public.entrega_comprovantes%ROWTYPE; e public.entregas%ROWTYPE; expires timestamptz;
BEGIN
 SELECT * INTO cp FROM public.entrega_comprovantes WHERE entrega_id=p_entrega_id FOR UPDATE;
 IF auth.uid() IS NULL OR NOT FOUND OR public.fn_usuario_e_gestor_empresa(cp.empresa_id,auth.uid()) IS NOT TRUE THEN
  RAISE EXCEPTION 'Apenas a gestão da empresa pode compartilhar este comprovante.' USING ERRCODE='42501'; END IF;
 SELECT * INTO e FROM public.entregas WHERE id=cp.entrega_id AND empresa_id=cp.empresa_id;
 IF NOT FOUND OR public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id) IS NOT TRUE
  OR e.status NOT IN ('entregue','tentativa_falha') THEN
  RAISE EXCEPTION 'Comprovante indisponível para compartilhamento.' USING ERRCODE='42501'; END IF;
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Token inválido.'; END IF;
 IF (cp.foto_path IS NULL AND p_foto_url IS NOT NULL) OR (cp.foto_path IS NOT NULL AND NOT ec_private.receipt_url_matches(p_foto_url,cp.foto_path))
  OR (cp.assinatura_path IS NULL AND p_assinatura_url IS NOT NULL) OR (cp.assinatura_path IS NOT NULL AND NOT ec_private.receipt_url_matches(p_assinatura_url,cp.assinatura_path)) THEN
  RAISE EXCEPTION 'Gere as imagens temporárias deste comprovante antes de compartilhar.'; END IF;
 expires:=clock_timestamp()+interval '55 minutes';
 INSERT INTO ec_private.receipt_shares(entrega_id,empresa_id,criado_por,token_hash,expires_at,foto_url,assinatura_url)
 VALUES(cp.entrega_id,cp.empresa_id,auth.uid(),sha256(convert_to(p_token,'UTF8')),expires,p_foto_url,p_assinatura_url)
 ON CONFLICT(entrega_id) DO UPDATE SET criado_por=EXCLUDED.criado_por,token_hash=EXCLUDED.token_hash,expires_at=EXCLUDED.expires_at,
 foto_url=EXCLUDED.foto_url,assinatura_url=EXCLUDED.assinatura_url;
 RETURN jsonb_build_object('sucesso',true,'expira_em',expires,'servidor_em',clock_timestamp());
END $$;
REVOKE ALL ON FUNCTION public.criar_compartilhamento_comprovante(uuid,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.criar_compartilhamento_comprovante(uuid,text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.obter_comprovante_compartilhado(p_token text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RETURN '{"sucesso":false}'::jsonb; END IF;
 SELECT jsonb_build_object('sucesso',true,'entrega_id',cp.entrega_id,'destinatario_nome',e.destinatario_nome,
  'endereco',COALESCE(to_jsonb(e)->>'endereco',a.endereco_completo),'empresa_nome',c.nome,'tipo_tarefa',e.tipo_tarefa,
  'recebedor_tipo',cp.recebedor_tipo,'recebedor_nome',cp.recebedor_nome,'observacao',cp.observacao,
  'concluida_em',cp.concluida_em,'duracao_segundos',cp.duracao_segundos,
  'foto_url',s.foto_url,'assinatura_url',s.assinatura_url,'expira_em',s.expires_at,'servidor_em',now()) INTO result
 FROM ec_private.receipt_shares s
 JOIN public.entrega_comprovantes cp ON cp.entrega_id=s.entrega_id AND cp.empresa_id=s.empresa_id
 JOIN public.entregas e ON e.id=cp.entrega_id AND e.empresa_id=cp.empresa_id AND e.status IN ('entregue','tentativa_falha')
 JOIN public.empresas c ON c.id=s.empresa_id AND c.ativa
 LEFT JOIN public.clientes_enderecos a ON a.id=e.cliente_endereco_id AND a.empresa_id=e.empresa_id
 WHERE s.token_hash=sha256(convert_to(p_token,'UTF8')) AND s.expires_at>now()
  AND public.fn_usuario_e_gestor_empresa(s.empresa_id,s.criado_por) IS TRUE
  AND (cp.foto_path IS NULL AND s.foto_url IS NULL OR ec_private.receipt_url_matches(s.foto_url,cp.foto_path))
  AND (cp.assinatura_path IS NULL AND s.assinatura_url IS NULL OR ec_private.receipt_url_matches(s.assinatura_url,cp.assinatura_path));
 RETURN COALESCE(result,'{"sucesso":false}'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.obter_comprovante_compartilhado(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.obter_comprovante_compartilhado(text) TO anon,authenticated;

CREATE OR REPLACE FUNCTION public.revogar_compartilhamento_comprovante(p_entrega_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE company uuid;
BEGIN
 SELECT empresa_id INTO company FROM public.entrega_comprovantes WHERE entrega_id=p_entrega_id;
 IF auth.uid() IS NULL OR NOT FOUND OR public.fn_usuario_e_gestor_empresa(company,auth.uid()) IS NOT TRUE THEN
  RAISE EXCEPTION 'Acesso de gestão obrigatório nesta empresa.' USING ERRCODE='42501'; END IF;
 DELETE FROM ec_private.receipt_shares WHERE entrega_id=p_entrega_id AND empresa_id=company;
 RETURN '{"sucesso":true}'::jsonb;
END $$;
REVOKE ALL ON FUNCTION public.revogar_compartilhamento_comprovante(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.revogar_compartilhamento_comprovante(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
