-- ==============================================================================
-- MODULO SQL: 04_storage.sql
-- Bucket privado, protocolo de coordenação de ciclo de vida e fila de limpeza.
-- Bloqueia exclusão direta de qualquer evidência vinculada (pendente ou aprovada).
-- Bloqueia sobrescrita (UPDATE/upsert) de evidências vinculadas ou em limpeza.
-- Coordena desvinculação, substituição e limpeza física recuperável.
--
-- GARANTIAS OBTIDAS:
-- 1. Toda evidência vinculada em veiculos_documentos está protegida contra
--    exclusão direta e sobrescrita pela API do Storage via RLS em storage.objects.
-- 2. Concorrência entre análise/aprovação e exclusão é neutralizada: a política
--    impede o DELETE no Storage enquanto a linha persistir em veiculos_documentos.
-- 3. A desvinculação atômica em veiculos_documentos insere o objeto na tabela
--    storage_limpeza_fila com status 'pendente'.
-- 4. Apenas após a desvinculação a política RLS autoriza o DELETE físico pelo cliente.
-- 5. Objetos marcados na fila de limpeza não podem ser reutilizados em novos anexos.
-- 6. Falhas na limpeza física são registradas de forma persistente e recuperável
--    na tabela storage_limpeza_fila para auditoria e retentativas.
--
-- LIMITAÇÕES REAIS:
-- O Supabase Storage e o PostgreSQL não compartilham transação distribuída 2PC.
-- As regras são coordenadas via RLS em storage.objects. Acessos que utilizem a
-- chave master service_role ou acessos diretos à infraestrutura de blocos (S3/disco)
-- contornam o motor SQL e não são governados por estas políticas.
-- ==============================================================================

-- 1. Criação e parametrização do bucket privado 'veiculos-documentos'
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'veiculos-documentos',
    'veiculos-documentos',
    FALSE,
    10485760, -- 10 MB
    ARRAY['image/jpeg', 'image/png', 'application/pdf']
)
ON CONFLICT (id) DO UPDATE SET
    public = FALSE,
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'application/pdf'];

-- 2. Fila persistente e auditável de limpeza do Storage
CREATE TABLE IF NOT EXISTS public.storage_limpeza_fila (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bucket_id VARCHAR(100) NOT NULL DEFAULT 'veiculos-documentos',
    storage_path TEXT NOT NULL,
    empresa_id UUID NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    motivo TEXT NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'pendente'
        CHECK (status IN ('pendente', 'em_processamento', 'concluido', 'falhou')),
    tentativas INT NOT NULL DEFAULT 0,
    max_tentativas INT NOT NULL DEFAULT 5,
    ultimo_erro TEXT,
    autorizado_em TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    processado_em TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_storage_limpeza_status_path 
ON public.storage_limpeza_fila(status, storage_path);

CREATE INDEX IF NOT EXISTS idx_storage_limpeza_empresa 
ON public.storage_limpeza_fila(empresa_id, status);

ALTER TABLE public.storage_limpeza_fila ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Gestores e condutores visualizam fila de limpeza da empresa" ON public.storage_limpeza_fila;
CREATE POLICY "Gestores e condutores visualizam fila de limpeza da empresa"
ON public.storage_limpeza_fila FOR SELECT
TO authenticated
USING (
    public.fn_usuario_e_gestor_empresa(empresa_id) OR user_id = auth.uid()
);

-- 3. Função auditada para registrar resultado da limpeza física do Storage
CREATE OR REPLACE FUNCTION public.registrar_limpeza_storage_executada(
    p_fila_id UUID,
    p_sucesso BOOLEAN,
    p_erro TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_item RECORD;
BEGIN
    SELECT * INTO v_item
    FROM public.storage_limpeza_fila
    WHERE id = p_fila_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ITEM_FILA_NAO_ENCONTRADO',
            'mensagem', 'Item da fila de limpeza não encontrado.'
        );
    END IF;

    -- Permissão: condutor proprietário do arquivo ou gestor da empresa
    IF v_item.user_id != auth.uid() AND NOT public.fn_usuario_e_gestor_empresa(v_item.empresa_id) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Sem permissão para registrar limpeza deste item.'
        );
    END IF;

    IF p_sucesso THEN
        UPDATE public.storage_limpeza_fila
        SET status = 'concluido',
            tentativas = tentativas + 1,
            ultimo_erro = NULL,
            processado_em = timezone('utc'::text, now()),
            updated_at = timezone('utc'::text, now())
        WHERE id = v_item.id;
    ELSE
        UPDATE public.storage_limpeza_fila
        SET status = CASE WHEN tentativas + 1 >= max_tentativas THEN 'falhou' ELSE 'pendente' END,
            tentativas = tentativas + 1,
            ultimo_erro = p_erro,
            processado_em = timezone('utc'::text, now()),
            updated_at = timezone('utc'::text, now())
        WHERE id = v_item.id;
    END IF;

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'LIMPEZA_REGISTRADA',
        'status', CASE WHEN p_sucesso THEN 'concluido' WHEN v_item.tentativas + 1 >= v_item.max_tentativas THEN 'falhou' ELSE 'pendente' END
    );
END;
$$;

-- 4. Políticas de Ciclo de Vida e Acesso no schema storage.objects

-- POLÍTICA 1: Upload (INSERT) de evidências pelo condutor autorizado
DROP POLICY IF EXISTS "Condutores enviam documentos do proprio veiculo" ON storage.objects;
CREATE POLICY "Condutores enviam documentos do proprio veiculo"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'veiculos-documentos' AND
    public.fn_safe_uuid(split_part(name, '/', 2)) = auth.uid() AND
    public.fn_safe_uuid(split_part(name, '/', 1)) IS NOT NULL AND
    (
        (public.fn_validar_autorizacao_condutor(public.fn_safe_uuid(split_part(name, '/', 1)), auth.uid())->>'autorizado')::boolean = TRUE
    ) AND
    NOT EXISTS (
        SELECT 1
        FROM public.storage_limpeza_fila slf
        WHERE slf.storage_path = name
          AND slf.status IN ('pendente', 'em_processamento', 'concluido')
    )
);

-- POLÍTICA 2: Visualização (SELECT) por condutor proprietário ou gestor da empresa
DROP POLICY IF EXISTS "Acesso autorizado a documentos veiculares" ON storage.objects;
CREATE POLICY "Acesso autorizado a documentos veiculares"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'veiculos-documentos' AND
    (
        public.fn_safe_uuid(split_part(name, '/', 2)) = auth.uid()
        OR
        public.fn_usuario_e_gestor_empresa(public.fn_safe_uuid(split_part(name, '/', 1)))
    )
);

-- POLÍTICA 3: Alteração / Sobrescrita (UPDATE / upsert)
-- Bloqueia terminantemente a sobrescrita direta de qualquer evidência vinculada ou em fila de limpeza.
DROP POLICY IF EXISTS "Atualizacao de documentos veiculares" ON storage.objects;
CREATE POLICY "Atualizacao de documentos veiculares"
ON storage.objects FOR UPDATE
TO authenticated
USING (
    bucket_id = 'veiculos-documentos' AND
    public.fn_safe_uuid(split_part(name, '/', 2)) = auth.uid() AND
    (
        (public.fn_validar_autorizacao_condutor(public.fn_safe_uuid(split_part(name, '/', 1)), auth.uid())->>'autorizado')::boolean = TRUE
    ) AND
    NOT EXISTS (
        SELECT 1
        FROM public.veiculos_documentos vd
        WHERE vd.storage_path = name
    ) AND
    NOT EXISTS (
        SELECT 1
        FROM public.storage_limpeza_fila slf
        WHERE slf.storage_path = name
    )
)
WITH CHECK (
    bucket_id = 'veiculos-documentos' AND
    public.fn_safe_uuid(split_part(name, '/', 2)) = auth.uid() AND
    (
        (public.fn_validar_autorizacao_condutor(public.fn_safe_uuid(split_part(name, '/', 1)), auth.uid())->>'autorizado')::boolean = TRUE
    ) AND
    NOT EXISTS (
        SELECT 1
        FROM public.veiculos_documentos vd
        WHERE vd.storage_path = name
    ) AND
    NOT EXISTS (
        SELECT 1
        FROM public.storage_limpeza_fila slf
        WHERE slf.storage_path = name
    )
);

-- POLÍTICA 4: Exclusão (DELETE) com protocolo coordenado de ciclo de vida
-- Bloqueia a exclusão direta de QUALQUER evidência vinculada.
-- A exclusão é autorizada apenas se o arquivo NÃO está vinculado em veiculos_documentos E:
-- A) A exclusão física foi explicitamente autorizada na fila de limpeza (status pendente ou em_processamento), OU
-- B) É um upload temporário do próprio condutor que nunca foi vinculado nem enfileirado.
DROP POLICY IF EXISTS "Exclusao de documentos veiculares" ON storage.objects;
CREATE POLICY "Exclusao de documentos veiculares"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'veiculos-documentos' AND
    (
        -- Condutor proprietário autorizado (não suspenso)
        (
            public.fn_safe_uuid(split_part(name, '/', 2)) = auth.uid() AND
            (public.fn_validar_autorizacao_condutor(public.fn_safe_uuid(split_part(name, '/', 1)), auth.uid())->>'autorizado')::boolean = TRUE
        )
        OR
        -- Gestor da empresa
        public.fn_usuario_e_gestor_empresa(public.fn_safe_uuid(split_part(name, '/', 1)))
    ) AND
    -- PROTEÇÃO CRÍTICA 1: Bloqueia exclusão direta enquanto o arquivo estiver vinculado
    NOT EXISTS (
        SELECT 1
        FROM public.veiculos_documentos vd
        WHERE vd.storage_path = name
    ) AND
    -- PROTEÇÃO CRÍTICA 2: Coordenação do ciclo de limpeza
    (
        EXISTS (
            SELECT 1
            FROM public.storage_limpeza_fila slf
            WHERE slf.storage_path = name
              AND slf.status IN ('pendente', 'em_processamento')
        )
        OR
        NOT EXISTS (
            SELECT 1
            FROM public.storage_limpeza_fila slf
            WHERE slf.storage_path = name
        )
    )
);
