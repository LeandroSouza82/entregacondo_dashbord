CREATE OR REPLACE FUNCTION public.fn_usuario_pode_operar_motorista(
    p_empresa_id UUID, p_motorista_id UUID
)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
    SELECT auth.uid() IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.motoristas m
        JOIN public.empresas e ON e.id = m.empresa_id AND e.ativa = TRUE
        JOIN public.veiculos_motoristas vm ON vm.user_id = m.user_id AND vm.empresa_id = m.empresa_id
        WHERE m.id = p_motorista_id AND m.empresa_id = p_empresa_id AND m.ativo = TRUE
          AND vm.status_analise = 'aprovado'
          AND (public.fn_validar_completude_veiculo(vm.id)->>'valido')::boolean IS TRUE
          AND (public.fn_usuario_e_gestor_empresa(p_empresa_id, auth.uid()) IS TRUE OR (
              m.user_id = auth.uid() AND EXISTS (
                  SELECT 1 FROM public.empresa_membros em
                  WHERE em.empresa_id = p_empresa_id AND em.user_id = auth.uid()
                    AND em.motorista_id = m.id AND em.papel = 'motorista' AND em.status = 'aprovado'
              )
          ))
    );
$$;