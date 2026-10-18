-- ==============================================================================
-- MODULO SQL: 06_grants.sql
-- Concessão explícita e coerente de privilégios.
-- Elimina contradições: sem mutações diretas em tabelas operacionais ou administrativas.
-- Mutações ocorrem exclusivamente por RPCs com SECURITY DEFINER auditadas.
-- ==============================================================================

-- 1. REVOGAÇÃO GERAL DE ESCRITA DIRETA PARA ANON E AUTHENTICATED
REVOKE ALL ON public.empresas FROM anon, authenticated;
REVOKE ALL ON public.perfis_usuarios FROM anon, authenticated;
REVOKE ALL ON public.empresa_membros FROM anon, authenticated;
REVOKE ALL ON public.solicitacoes_acesso FROM anon, authenticated;
REVOKE ALL ON public.auditoria_acessos FROM anon, authenticated;
REVOKE ALL ON public.motoristas FROM anon, authenticated;
REVOKE ALL ON public.veiculos_motoristas FROM anon, authenticated;
REVOKE ALL ON public.veiculos_documentos FROM anon, authenticated;
REVOKE ALL ON public.clientes_enderecos FROM anon, authenticated;
REVOKE ALL ON public.rotas_planejadas FROM anon, authenticated;
REVOKE ALL ON public.entregas FROM anon, authenticated;
REVOKE ALL ON public.historico_atendimentos FROM anon, authenticated;

-- 2. CONCESSÃO DE LEITURA (SELECT) RESTRITA VIA RLS
GRANT SELECT ON public.empresas TO authenticated;
GRANT SELECT ON public.perfis_usuarios TO authenticated;
GRANT SELECT ON public.empresa_membros TO authenticated;
GRANT SELECT ON public.solicitacoes_acesso TO authenticated;
GRANT SELECT ON public.auditoria_acessos TO authenticated;
GRANT SELECT ON public.motoristas TO authenticated;
GRANT SELECT ON public.veiculos_motoristas TO authenticated;
GRANT SELECT ON public.veiculos_documentos TO authenticated;
GRANT SELECT ON public.clientes_enderecos TO authenticated;
GRANT SELECT ON public.rotas_planejadas TO authenticated;
GRANT SELECT ON public.entregas TO authenticated;
GRANT SELECT ON public.historico_atendimentos TO authenticated;

-- 3. PERMISSÃO DE EDIÇÃO BÁSICA EXCLUSIVA NO PRÓPRIO PERFIL
GRANT UPDATE (nome, telefone, avatar_url) ON public.perfis_usuarios TO authenticated;

-- 4. REVOGAÇÃO DE SOBRECARGAS OBSOLETAS E PRIVILÉGIOS PÚBLICOS PADRÃO
DROP FUNCTION IF EXISTS public.anexar_documento_veiculo(UUID, TEXT, TEXT, TEXT, INT);
DROP FUNCTION IF EXISTS public.analisar_veiculo_motorista(UUID, BOOLEAN, TEXT);
DROP FUNCTION IF EXISTS public.aprovar_solicitacao_motorista(UUID, UUID, BOOLEAN, TEXT, VARCHAR);
DROP FUNCTION IF EXISTS public.aprovar_solicitacao_motorista(UUID, UUID, BOOLEAN, TEXT, VARCHAR, INT);

REVOKE EXECUTE ON FUNCTION public.fn_validar_autorizacao_condutor(UUID, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_validar_completude_veiculo(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cadastrar_meu_veiculo(JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.anexar_documento_veiculo(UUID, TEXT, TEXT, TEXT, INT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.remover_documento_veiculo(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.analisar_veiculo_motorista(UUID, BOOLEAN, INT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.aprovar_solicitacao_motorista(UUID, UUID, BOOLEAN, TEXT, VARCHAR, BOOLEAN, INT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.registrar_limpeza_storage_executada(UUID, BOOLEAN, TEXT) FROM PUBLIC;

-- 5. CONCESSÃO DE EXECUÇÃO NAS RPCS DE NEGÓCIO
GRANT EXECUTE ON FUNCTION public.fn_safe_uuid(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_usuario_pertence_empresa(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_usuario_e_gestor_empresa(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_usuario_e_admin_empresa(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_usuario_e_motorista_ativo(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_motorista_id_do_usuario(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_validar_autorizacao_condutor(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_validar_completude_veiculo(UUID) TO authenticated;

GRANT EXECUTE ON FUNCTION public.obter_meu_status_acesso() TO authenticated;
GRANT EXECUTE ON FUNCTION public.solicitar_acesso_empresa(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cadastrar_meu_veiculo(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.anexar_documento_veiculo(UUID, TEXT, TEXT, TEXT, INT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remover_documento_veiculo(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.registrar_limpeza_storage_executada(UUID, BOOLEAN, TEXT) TO authenticated;

GRANT EXECUTE ON FUNCTION public.aprovar_solicitacao_motorista(UUID, UUID, BOOLEAN, TEXT, VARCHAR, BOOLEAN, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rejeitar_solicitacao_acesso(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.suspender_acesso_membro(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reativar_acesso_membro(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.alterar_papel_membro(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.analisar_veiculo_motorista(UUID, BOOLEAN, INT, TEXT) TO authenticated;

GRANT EXECUTE ON FUNCTION public.despachar_rota_transacional(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.iniciar_rota(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.concluir_rota(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.registrar_conclusao_entrega(UUID, BOOLEAN, TEXT, NUMERIC, NUMERIC, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sincronizar_meu_perfil() TO authenticated;

GRANT EXECUTE ON FUNCTION public.bootstrap_primeiro_gestor(TEXT, TEXT, TEXT) TO service_role;
