-- ==============================================================================
-- MODULO SQL: 04_storage.sql
-- Bucket privado, protocolo de coordenação de ciclo de vida e fila de limpeza.
-- Bloqueia exclusão direta de qualquer evidência vinculada (pendente ou aprovada).
-- Bloqueia sobrescrita (UPDATE/upsert) de todas as evidências.
-- Coordena upload com reserva prévia, vinculação, substituição e descarte seguro.
--
-- GARANTIAS OBTIDAS:
-- 1. Todo upload exige reserva prévia via RPC reservar_upload_evidencia com caminho
--    único não reutilizável e status 'reservado'.
-- 2. Sobrescrita direta (UPDATE) de evidências é permanentemente bloqueada via RLS.
-- 3. Exclusão física (DELETE) só é autorizada para arquivos que NÃO estejam vinculados
--    em veiculos_documentos E cujo status na fila de limpeza seja 'pendente' ou 'em_processamento'.
-- 4. Anexar ou vincular documento disputa o lock da linha na fila de limpeza (FOR UPDATE).
--    Se houver tentativa concorrente de exclusão/descarte, a disputa no mesmo registro
--    impede a vinculação de arquivo em processo de limpeza ou já descartado.
-- 5. Objetos com status 'falhou' continuam bloqueados permanentemente contra upload ou
--    vinculação. A retomada exige chamada explícita e autorizada a retomar_limpeza_falha.
-- 6. A fila de limpeza possui constraint UNIQUE em storage_path, impedindo registros
--    conflitantes para o mesmo objeto.
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

-- 2. Fila persistente e auditável de limpeza e ciclo de vida do Storage
CREATE TABLE IF NOT EXISTS public.storage_limpeza_fila (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bucket_id VARCHAR(100) NOT NULL DEFAULT 'veiculos-documentos',
    storage_path TEXT NOT NULL UNIQUE,
    empresa_id UUID NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    motivo TEXT NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'pendente'
        CHECK (status IN ('reservado', 'vinculado', 'pendente', 'em_processamento', 'concluido', 'falhou')),
    tentativas INT NOT NULL DEFAULT 0,
    max_tentativas INT NOT NULL DEFAULT 5,
    ultimo_erro TEXT,
    autorizado_em TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    processado_em TIMESTAMPTZ,
    claim_token UUID,
    claimed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    lease_expires_at TIMESTAMPTZ,
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
    public.fn_usuario_e_gestor_empresa(empresa_id, auth.uid()) OR user_id = auth.uid()
);

-- 3. RPC: Reserva prévia de upload de evidência (Caminho único e coordenação de ciclo de vida)
-- RPC modular: functions-sql/reservar_upload_evidencia.sql

-- 4. RPC: Descarte coordenado de evidência temporária não vinculada
-- RPC modular: functions-sql/descartar_evidencia_temporaria.sql

-- 5. RPC: Reivindicação atômica de itens da fila de limpeza (Lock seguro contra concorrência)
-- RPC modular: functions-sql/reivindicar_itens_limpeza_storage.sql

-- 6. RPC: Retomada explícita e autorizada de limpeza falha
-- RPC modular: functions-sql/retomar_limpeza_falha.sql

-- 7. Função auditada para registrar resultado da limpeza física do Storage
-- RPC modular: functions-sql/registrar_limpeza_storage_executada.sql

-- 8. Políticas de Ciclo de Vida e Acesso no schema storage.objects

-- POLÍTICA 1: Upload (INSERT) de evidências pelo condutor autorizado com reserva prévia obrigatória
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
    -- EXIGE RESERVA PRÉVIA ATIVA (STATUS = 'reservado')
    EXISTS (
        SELECT 1
        FROM public.storage_limpeza_fila slf
        WHERE slf.storage_path = name
          AND slf.status = 'reservado'
          AND slf.user_id = auth.uid()
          AND slf.empresa_id = public.fn_safe_uuid(split_part(name, '/', 1))
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
        public.fn_usuario_e_gestor_empresa(public.fn_safe_uuid(split_part(name, '/', 1)), auth.uid())
    )
);

-- POLÍTICA 3: Alteração / Sobrescrita (UPDATE / upsert)
-- Bloqueia terminantemente qualquer UPDATE/sobrescrita de evidências veiculares.
DROP POLICY IF EXISTS "Atualizacao de documentos veiculares" ON storage.objects;
CREATE POLICY "Atualizacao de documentos veiculares"
ON storage.objects FOR UPDATE
TO authenticated
USING (FALSE)
WITH CHECK (FALSE);

-- POLÍTICA 4: Exclusão (DELETE) com protocolo coordenado de ciclo de vida
-- Bloqueia a exclusão direta de QUALQUER evidência vinculada.
-- A exclusão é autorizada apenas se o arquivo NÃO está vinculado em veiculos_documentos E
-- a exclusão física foi formalmente autorizada na fila de limpeza com status pendente ou em_processamento.
DROP POLICY IF EXISTS "Exclusao de documentos veiculares" ON storage.objects;
CREATE POLICY "Exclusao de documentos veiculares"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'veiculos-documentos' AND
    (
        (
            public.fn_safe_uuid(split_part(name, '/', 2)) = auth.uid() AND
            (public.fn_validar_autorizacao_condutor(public.fn_safe_uuid(split_part(name, '/', 1)), auth.uid())->>'autorizado')::boolean = TRUE
        )
        OR
        public.fn_usuario_e_gestor_empresa(public.fn_safe_uuid(split_part(name, '/', 1)), auth.uid())
    ) AND
    -- NUNCA permite excluir se persistir vínculo em veiculos_documentos
    NOT EXISTS (
        SELECT 1
        FROM public.veiculos_documentos vd
        WHERE vd.storage_path = name
    ) AND
    -- EXIGE autorização formal na fila de limpeza com status pendente ou em_processamento
    EXISTS (
        SELECT 1
        FROM public.storage_limpeza_fila slf
        WHERE slf.storage_path = name
          AND slf.status = 'em_processamento'
          AND slf.claimed_by = auth.uid()
          AND slf.claim_token IS NOT NULL
          AND slf.lease_expires_at > clock_timestamp()
    )
);
