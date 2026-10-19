-- ==============================================================================
-- MODULO SQL: 05_rls_policies.sql
-- Funções de verificação e políticas RLS para todas as tabelas públicas.
-- Bloqueio absoluto de registros sem empresa. Sem 'empresa_id IS NULL OR'.
-- ==============================================================================

-- 1. FUNÇÕES AUXILIARES DE AUTORIZAÇÃO (SECURITY DEFINER)

CREATE OR REPLACE FUNCTION public.fn_usuario_e_gestor_empresa(p_empresa_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.empresa_membros em
        JOIN public.empresas e ON e.id = em.empresa_id
        WHERE em.empresa_id = p_empresa_id
          AND em.user_id = auth.uid()
          AND em.papel IN ('admin', 'gestor')
          AND em.status = 'aprovado'
          AND e.ativa = TRUE
    );
$$;

CREATE OR REPLACE FUNCTION public.fn_usuario_e_admin_empresa(p_empresa_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.empresa_membros em
        JOIN public.empresas e ON e.id = em.empresa_id
        WHERE em.empresa_id = p_empresa_id
          AND em.user_id = auth.uid()
          AND em.papel = 'admin'
          AND em.status = 'aprovado'
          AND e.ativa = TRUE
    );
$$;

CREATE OR REPLACE FUNCTION public.fn_motorista_id_do_usuario(p_user_id UUID DEFAULT auth.uid())
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT em.motorista_id
    FROM public.empresa_membros em
    JOIN public.empresas e ON e.id = em.empresa_id
    WHERE em.user_id = p_user_id
      AND em.status = 'aprovado'
      AND em.motorista_id IS NOT NULL
      AND e.ativa = TRUE
    LIMIT 1;
$$;

-- 2. HABILITAÇÃO DE RLS EM TODAS AS TABELAS
ALTER TABLE public.empresas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.perfis_usuarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.empresa_membros ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.solicitacoes_acesso ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auditoria_acessos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.motoristas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.veiculos_motoristas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.veiculos_documentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clientes_enderecos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rotas_planejadas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.entregas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.historico_atendimentos ENABLE ROW LEVEL SECURITY;

-- 3. POLÍTICAS RLS

-- empresas
DROP POLICY IF EXISTS "Usuarios visualizam empresas das quais sao membros" ON public.empresas;
CREATE POLICY "Usuarios visualizam empresas das quais sao membros"
ON public.empresas FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.empresa_membros em
        WHERE em.empresa_id = id
          AND em.user_id = auth.uid()
    )
);

-- perfis_usuarios
DROP POLICY IF EXISTS "Usuarios visualizam proprio perfil ou de membros da mesma empresa" ON public.perfis_usuarios;
CREATE POLICY "Usuarios visualizam proprio perfil ou de membros da mesma empresa"
ON public.perfis_usuarios FOR SELECT
TO authenticated
USING (
    id = auth.uid() OR
    EXISTS (
        SELECT 1 FROM public.empresa_membros m1
        JOIN public.empresa_membros m2 ON m1.empresa_id = m2.empresa_id
        WHERE m1.user_id = auth.uid()
          AND m2.user_id = perfis_usuarios.id
          AND m1.status = 'aprovado'
    )
);

DROP POLICY IF EXISTS "Usuarios atualizam apenas proprio perfil" ON public.perfis_usuarios;
CREATE POLICY "Usuarios atualizam apenas proprio perfil"
ON public.perfis_usuarios FOR UPDATE
TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- empresa_membros
DROP POLICY IF EXISTS "Leitura de membros por membros da empresa" ON public.empresa_membros;
CREATE POLICY "Leitura de membros por membros da empresa"
ON public.empresa_membros FOR SELECT
TO authenticated
USING (
    user_id = auth.uid() OR
    public.fn_usuario_e_gestor_empresa(empresa_id, auth.uid())
);

-- solicitacoes_acesso
DROP POLICY IF EXISTS "Leitura de solicitacoes pelo usuario ou gestao" ON public.solicitacoes_acesso;
CREATE POLICY "Leitura de solicitacoes pelo usuario ou gestao"
ON public.solicitacoes_acesso FOR SELECT
TO authenticated
USING (
    user_id = auth.uid() OR
    public.fn_usuario_e_gestor_empresa(empresa_id, auth.uid())
);

-- auditoria_acessos
DROP POLICY IF EXISTS "Gestores leem auditoria da empresa" ON public.auditoria_acessos;
CREATE POLICY "Gestores leem auditoria da empresa"
ON public.auditoria_acessos FOR SELECT
TO authenticated
USING (
    public.fn_usuario_e_gestor_empresa(empresa_id, auth.uid())
);

-- motoristas
DROP POLICY IF EXISTS "Leitura de motoristas autorizada" ON public.motoristas;
CREATE POLICY "Leitura de motoristas autorizada"
ON public.motoristas FOR SELECT
TO authenticated
USING (
    public.fn_usuario_e_gestor_empresa(empresa_id, auth.uid())
    OR
    (
        user_id = auth.uid() AND
        EXISTS (
            SELECT 1 FROM public.empresa_membros em
            JOIN public.empresas e ON e.id = em.empresa_id
            WHERE em.empresa_id = motoristas.empresa_id
              AND em.user_id = auth.uid()
              AND em.status = 'aprovado'
              AND em.motorista_id = motoristas.id
              AND e.ativa = TRUE
        )
    )
);

-- veiculos_motoristas
DROP POLICY IF EXISTS "Leitura de veiculos por condutor ou gestao" ON public.veiculos_motoristas;
CREATE POLICY "Leitura de veiculos por condutor ou gestao"
ON public.veiculos_motoristas FOR SELECT
TO authenticated
USING (
    user_id = auth.uid() OR
    public.fn_usuario_e_gestor_empresa(empresa_id, auth.uid())
);

-- veiculos_documentos
DROP POLICY IF EXISTS "Leitura de documentos por condutor ou gestao" ON public.veiculos_documentos;
CREATE POLICY "Leitura de documentos por condutor ou gestao"
ON public.veiculos_documentos FOR SELECT
TO authenticated
USING (
    user_id = auth.uid() OR
    public.fn_usuario_e_gestor_empresa(empresa_id, auth.uid())
);

-- clientes_enderecos
DROP POLICY IF EXISTS "Leitura de clientes enderecos por gestao ou motorista atribuido" ON public.clientes_enderecos;
CREATE POLICY "Leitura de clientes enderecos por gestao ou motorista atribuido"
ON public.clientes_enderecos FOR SELECT
TO authenticated
USING (
    public.fn_usuario_e_gestor_empresa(empresa_id, auth.uid())
    OR
    EXISTS (
        SELECT 1 FROM public.entregas ent
        WHERE ent.cliente_endereco_id = clientes_enderecos.id
          AND ent.motorista_id = public.fn_motorista_id_do_usuario(auth.uid())
          AND ent.status IN ('atribuida', 'em_transito')
    )
);

-- rotas_planejadas
DROP POLICY IF EXISTS "Leitura de rotas por gestao ou motorista atribuido" ON public.rotas_planejadas;
CREATE POLICY "Leitura de rotas por gestao ou motorista atribuido"
ON public.rotas_planejadas FOR SELECT
TO authenticated
USING (
    public.fn_usuario_e_gestor_empresa(empresa_id, auth.uid())
    OR
    (
        motorista_id = public.fn_motorista_id_do_usuario(auth.uid())
        AND EXISTS (
            SELECT 1 FROM public.empresa_membros em
            JOIN public.empresas e ON e.id = em.empresa_id
            WHERE em.empresa_id = rotas_planejadas.empresa_id
              AND em.user_id = auth.uid()
              AND em.status = 'aprovado'
              AND e.ativa = TRUE
        )
    )
);

-- entregas
DROP POLICY IF EXISTS "Leitura de entregas por gestao ou motorista atribuido" ON public.entregas;
CREATE POLICY "Leitura de entregas por gestao ou motorista atribuido"
ON public.entregas FOR SELECT
TO authenticated
USING (
    public.fn_usuario_e_gestor_empresa(empresa_id, auth.uid())
    OR
    (
        motorista_id = public.fn_motorista_id_do_usuario(auth.uid())
        AND EXISTS (
            SELECT 1 FROM public.empresa_membros em
            JOIN public.empresas e ON e.id = em.empresa_id
            WHERE em.empresa_id = entregas.empresa_id
              AND em.user_id = auth.uid()
              AND em.status = 'aprovado'
              AND e.ativa = TRUE
        )
    )
);

-- historico_atendimentos
DROP POLICY IF EXISTS "Leitura de historico por gestao ou motorista" ON public.historico_atendimentos;
CREATE POLICY "Leitura de historico por gestao ou motorista"
ON public.historico_atendimentos FOR SELECT
TO authenticated
USING (
    motorista_id = public.fn_motorista_id_do_usuario(auth.uid())
    OR
    EXISTS (
        SELECT 1 FROM public.entregas e
        WHERE e.id = historico_atendimentos.entrega_id
          AND public.fn_usuario_e_gestor_empresa(e.empresa_id, auth.uid())
    )
);
