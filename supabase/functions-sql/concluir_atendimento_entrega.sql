-- Arrival is explicit; receipts are immutable and scoped to the assigned operation.
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS chegada_em timestamptz;
CREATE TABLE IF NOT EXISTS public.entrega_comprovantes (
 entrega_id uuid PRIMARY KEY REFERENCES public.entregas(id),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 registrado_por uuid NOT NULL REFERENCES auth.users(id),
 recebedor_tipo text NOT NULL,
 recebedor_nome text CHECK (length(recebedor_nome)<=160),
 observacao text CHECK (length(observacao)<=1000),
 foto_path text,
 assinatura_path text,
 chegada_em timestamptz NOT NULL,
 concluida_em timestamptz NOT NULL,
 duracao_segundos integer NOT NULL CHECK (duracao_segundos>=0),
 latitude double precision CHECK (latitude BETWEEN -90 AND 90),
 longitude double precision CHECK (longitude BETWEEN -180 AND 180),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS entrega_comprovantes_empresa_idx ON public.entrega_comprovantes(empresa_id);
ALTER TABLE public.entrega_comprovantes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.entrega_comprovantes FROM anon,authenticated;
GRANT SELECT ON public.entrega_comprovantes TO authenticated;
DROP POLICY IF EXISTS comprovante_operacao_select ON public.entrega_comprovantes;
CREATE POLICY comprovante_operacao_select ON public.entrega_comprovantes FOR SELECT TO authenticated USING (
 EXISTS(SELECT 1 FROM public.entregas e WHERE e.id=entrega_id AND e.empresa_id=entrega_comprovantes.empresa_id
 AND public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id))
);
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('entregas-comprovantes','entregas-comprovantes',false,10485760,ARRAY['image/jpeg','image/png']) ON CONFLICT(id) DO NOTHING;
DROP POLICY IF EXISTS comprovante_operacao_upload ON storage.objects;
CREATE POLICY comprovante_operacao_upload ON storage.objects FOR INSERT TO authenticated WITH CHECK (
 bucket_id='entregas-comprovantes' AND split_part(name,'/',2)=(select auth.uid())::text
 AND EXISTS(SELECT 1 FROM public.entregas e WHERE e.id=public.fn_safe_uuid(split_part(name,'/',3))
 AND e.empresa_id=public.fn_safe_uuid(split_part(name,'/',1)) AND e.status NOT IN ('entregue','tentativa_falha','cancelada')
 AND public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id))
);
DROP POLICY IF EXISTS comprovante_operacao_download ON storage.objects;
CREATE POLICY comprovante_operacao_download ON storage.objects FOR SELECT TO authenticated USING (
 bucket_id='entregas-comprovantes' AND EXISTS(SELECT 1 FROM public.entregas e
 WHERE e.id=public.fn_safe_uuid(split_part(name,'/',3)) AND e.empresa_id=public.fn_safe_uuid(split_part(name,'/',1))
 AND public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id))
);

CREATE OR REPLACE FUNCTION public.iniciar_atendimento_entrega(p_entrega_id uuid,p_chegada_em timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE e public.entregas%ROWTYPE;
BEGIN
 SELECT * INTO e FROM public.entregas WHERE id=p_entrega_id FOR UPDATE;
 IF auth.uid() IS NULL OR NOT FOUND OR public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id) IS NOT TRUE THEN
 RETURN jsonb_build_object('sucesso',false,'mensagem','Acesso negado à tarefa.'); END IF;
 IF e.status IN ('entregue','tentativa_falha','cancelada') THEN RETURN jsonb_build_object('sucesso',false,'mensagem','Esta tarefa já foi finalizada.'); END IF;
 IF p_chegada_em IS NULL OR p_chegada_em>now()+interval '5 minutes' THEN RETURN jsonb_build_object('sucesso',false,'mensagem','Confira o relógio do aparelho.'); END IF;
 UPDATE public.entregas SET chegada_em=COALESCE(chegada_em,p_chegada_em) WHERE id=e.id RETURNING * INTO e;
 RETURN jsonb_build_object('sucesso',true,'chegada_em',e.chegada_em);
END $$;
REVOKE ALL ON FUNCTION public.iniciar_atendimento_entrega(uuid,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.iniciar_atendimento_entrega(uuid,timestamptz) TO authenticated;

CREATE OR REPLACE FUNCTION public.concluir_atendimento_entrega(
 p_entrega_id uuid,p_sucesso boolean,p_chegada_em timestamptz,p_conclusao_em timestamptz,p_comprovante jsonb DEFAULT '{}'::jsonb,p_motivo text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE e public.entregas%ROWTYPE; result jsonb; arrival timestamptz; finish timestamptz; proof_path text; seconds integer;
BEGIN
 SELECT * INTO e FROM public.entregas WHERE id=p_entrega_id FOR UPDATE;
 IF auth.uid() IS NULL OR NOT FOUND OR public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id) IS NOT TRUE THEN
 RETURN jsonb_build_object('sucesso',false,'mensagem','Acesso negado à tarefa.'); END IF;
 IF p_sucesso IS NULL THEN RETURN jsonb_build_object('sucesso',false,'mensagem','Resultado inválido.'); END IF;
 -- Same outcome retry never alters an immutable receipt or the statistics.
 IF e.status IN ('entregue','tentativa_falha','cancelada') THEN
 RETURN public.registrar_conclusao_entrega(e.id,p_sucesso,p_motivo); END IF;
 arrival:=COALESCE(e.chegada_em,p_chegada_em); finish:=COALESCE(p_conclusao_em,now());
 IF arrival IS NULL OR arrival>finish OR finish>now()+interval '5 minutes' THEN
 RETURN jsonb_build_object('sucesso',false,'mensagem','Marque sua chegada e confira o horário do aparelho.'); END IF;
 IF p_sucesso AND (jsonb_typeof(p_comprovante) IS DISTINCT FROM 'object' OR COALESCE(p_comprovante->>'recebedor_tipo','') NOT IN
 ('sindico','zelador','faxineiro','porteiro','vizinho','proprio_cliente','familiar','recepcao','funcionario','responsavel_coleta','outro')) THEN
 RETURN jsonb_build_object('sucesso',false,'mensagem','Informe quem recebeu ou entregou o pacote.'); END IF;
 IF length(COALESCE(p_comprovante->>'recebedor_nome',''))>160 OR length(COALESCE(p_comprovante->>'observacao',''))>1000 THEN
 RETURN jsonb_build_object('sucesso',false,'mensagem','Nome ou observação excede o limite.'); END IF;
 FOREACH proof_path IN ARRAY ARRAY[NULLIF(p_comprovante->>'foto_path',''),NULLIF(p_comprovante->>'assinatura_path','')] LOOP
 IF proof_path IS NOT NULL AND (split_part(proof_path,'/',1)<>e.empresa_id::text OR split_part(proof_path,'/',2)<>auth.uid()::text OR split_part(proof_path,'/',3)<>e.id::text
 OR NOT EXISTS(SELECT 1 FROM storage.objects o WHERE o.bucket_id='entregas-comprovantes' AND o.name=proof_path)) THEN
 RETURN jsonb_build_object('sucesso',false,'mensagem','Comprovante não enviado ou sem autorização.'); END IF;
 END LOOP;
 seconds:=GREATEST(0,floor(extract(epoch FROM (finish-arrival)))::integer);
 result:=public.registrar_conclusao_entrega(e.id,p_sucesso,p_motivo,GREATEST(0.01,seconds/60.0),0,arrival,finish);
 IF result->>'sucesso' IS DISTINCT FROM 'true' THEN RETURN result; END IF;
 UPDATE public.entregas SET chegada_em=arrival WHERE id=e.id;
 INSERT INTO public.entrega_comprovantes(entrega_id,empresa_id,registrado_por,recebedor_tipo,recebedor_nome,observacao,foto_path,assinatura_path,chegada_em,concluida_em,duracao_segundos,latitude,longitude)
 VALUES(e.id,e.empresa_id,auth.uid(),CASE WHEN p_sucesso THEN p_comprovante->>'recebedor_tipo' ELSE 'tentativa_falha' END,
 NULLIF(trim(p_comprovante->>'recebedor_nome'),''),NULLIF(trim(p_comprovante->>'observacao'),''),NULLIF(p_comprovante->>'foto_path',''),NULLIF(p_comprovante->>'assinatura_path',''),arrival,finish,seconds,
 (p_comprovante->>'latitude')::double precision,(p_comprovante->>'longitude')::double precision);
 RETURN result||jsonb_build_object('duracao_segundos',seconds);
END $$;
REVOKE ALL ON FUNCTION public.concluir_atendimento_entrega(uuid,boolean,timestamptz,timestamptz,jsonb,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.concluir_atendimento_entrega(uuid,boolean,timestamptz,timestamptz,jsonb,text) TO authenticated;
