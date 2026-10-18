-- ==============================================================================
-- MODULO SQL: 04_storage.sql
-- Bucket privado e políticas de ciclo de vida seguro para fotos e documentos.
-- Bloqueia exclusão direta de qualquer evidência vinculada (pendente ou aprovada).
-- Bloqueia sobrescrita (UPDATE/upsert) de evidências vinculadas.
-- Permite exclusão autorizada de uploads temporários e arquivos desvinculados.
--
-- GARANTIAS OBTIDAS:
-- 1. Toda evidência vinculada em veiculos_documentos está protegida contra
--    exclusão direta e sobrescrita pela API do Storage.
-- 2. Concorrência entre análise/aprovação e exclusão é neutralizada: a política
--    impede o DELETE no Storage enquanto a linha persistir em veiculos_documentos.
-- 3. Apenas a RPC remover_documento_veiculo (ou substituição autorizada) desvincula
--    o arquivo no Postgres, rebaixa o veículo para 'pendente' e então autoriza a
--    remoção física pelo cliente.
-- 4. Uploads temporários não vinculados podem ser limpos pelo próprio condutor.
--
-- LIMITAÇÕES:
-- O Supabase Storage e o PostgreSQL não compartilham transação atômica 2PC.
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

-- 2. Políticas de Ciclo de Vida e Acesso no schema storage.objects

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
-- Bloqueia terminantemente a sobrescrita direta de qualquer evidência vinculada.
-- Um arquivo só pode ser atualizado se for um upload temporário ainda não vinculado.
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
    )
);

-- POLÍTICA 4: Exclusão (DELETE) com proteção de evidências vinculadas
-- Bloqueia a exclusão direta de QUALQUER evidência vinculada (pendente ou aprovada).
-- A exclusão é autorizada apenas para:
-- A) Uploads temporários do próprio condutor que ainda não foram vinculados via RPC.
-- B) Arquivos desvinculados previamente através da RPC remover_documento_veiculo ou substituição.
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
    -- PROTEÇÃO CRÍTICA: Bloqueia exclusão direta enquanto o arquivo estiver vinculado
    NOT EXISTS (
        SELECT 1
        FROM public.veiculos_documentos vd
        WHERE vd.storage_path = name
    )
);
