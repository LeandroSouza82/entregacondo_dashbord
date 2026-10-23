BEGIN;
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

DROP POLICY IF EXISTS comprovante_publico_download ON storage.objects;
UPDATE storage.buckets SET public=false WHERE id='entregas-comprovantes';
COMMIT;
