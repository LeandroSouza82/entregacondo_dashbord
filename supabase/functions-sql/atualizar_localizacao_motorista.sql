ALTER TABLE public.motoristas ADD COLUMN IF NOT EXISTS latitude_atual numeric(10,7);
ALTER TABLE public.motoristas ADD COLUMN IF NOT EXISTS longitude_atual numeric(10,7);
ALTER TABLE public.motoristas ADD COLUMN IF NOT EXISTS localizacao_atualizada_em timestamptz;
ALTER TABLE public.rotas_planejadas ADD COLUMN IF NOT EXISTS distancia_registrada_km numeric(12,3);
ALTER TABLE public.rotas_planejadas ADD COLUMN IF NOT EXISTS distancia_registrada_em timestamptz;
CREATE OR REPLACE FUNCTION public.atualizar_localizacao_motorista(p_rota_id uuid,p_latitude double precision,p_longitude double precision,p_distancia_km numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE r public.rotas_planejadas%ROWTYPE;
BEGIN
 SELECT * INTO r FROM public.rotas_planejadas WHERE id=p_rota_id FOR UPDATE;
 IF auth.uid() IS NULL OR NOT FOUND OR r.status<>'em_execucao' OR public.fn_usuario_pode_operar_motorista(r.empresa_id,r.motorista_id) IS NOT TRUE
 OR NOT EXISTS(SELECT 1 FROM public.motoristas m WHERE m.id=r.motorista_id AND m.empresa_id=r.empresa_id AND m.user_id=auth.uid()) THEN
 RETURN jsonb_build_object('sucesso',false,'mensagem','Localização permitida somente ao motorista da rota ativa.'); END IF;
 IF p_latitude IS NULL OR p_longitude IS NULL OR p_distancia_km IS NULL OR NOT(p_latitude BETWEEN -90 AND 90) OR NOT(p_longitude BETWEEN -180 AND 180) OR NOT(p_distancia_km BETWEEN 0 AND 100000) THEN
 RETURN jsonb_build_object('sucesso',false,'mensagem','Localização inválida.'); END IF;
 UPDATE public.motoristas SET latitude_atual=p_latitude,longitude_atual=p_longitude,localizacao_atualizada_em=now() WHERE id=r.motorista_id;
 UPDATE public.rotas_planejadas SET distancia_registrada_km=GREATEST(COALESCE(distancia_registrada_km,0),p_distancia_km),distancia_registrada_em=now() WHERE id=r.id;
 RETURN jsonb_build_object('sucesso',true);
END $$;
REVOKE ALL ON FUNCTION public.atualizar_localizacao_motorista(uuid,double precision,double precision,numeric) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.atualizar_localizacao_motorista(uuid,double precision,double precision,numeric) TO authenticated;
