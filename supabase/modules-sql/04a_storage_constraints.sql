-- Aborta com diagnóstico; nunca ignora falha de integridade nem exclui dados.
DO $$
DECLARE v_constraint RECORD;
BEGIN
    IF EXISTS (SELECT 1 FROM public.storage_limpeza_fila GROUP BY storage_path HAVING count(*) > 1) THEN
        RAISE EXCEPTION 'Caminhos duplicados em storage_limpeza_fila. Reconcilie os registros sem excluir o histórico antes da migração.';
    END IF;
    IF EXISTS (SELECT 1 FROM public.storage_limpeza_fila WHERE status NOT IN ('reservado','vinculado','pendente','em_processamento','concluido','falhou')) THEN
        RAISE EXCEPTION 'Estado legado de Storage desconhecido. Migração interrompida sem alterar os dados.';
    END IF;
    FOR v_constraint IN SELECT conname FROM pg_constraint WHERE conrelid = 'public.storage_limpeza_fila'::regclass
        AND contype = 'c' AND pg_get_constraintdef(oid) LIKE '%status%'
    LOOP EXECUTE format('ALTER TABLE public.storage_limpeza_fila DROP CONSTRAINT %I', v_constraint.conname); END LOOP;
    ALTER TABLE public.storage_limpeza_fila ADD CONSTRAINT storage_limpeza_fila_status_check
        CHECK (status IN ('reservado','vinculado','pendente','em_processamento','concluido','falhou'));
    IF NOT EXISTS (SELECT 1 FROM pg_constraint c
        WHERE c.conrelid = 'public.storage_limpeza_fila'::regclass AND c.contype IN ('u','p')
          AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = c.conrelid AND attname = 'storage_path')]::smallint[]) THEN
        ALTER TABLE public.storage_limpeza_fila ADD CONSTRAINT storage_limpeza_fila_storage_path_key UNIQUE (storage_path);
    END IF;
END $$;
