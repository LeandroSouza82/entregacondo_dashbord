-- Compatibilidade conservadora com o cadastro veicular anterior.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='veiculos_motoristas' AND column_name='status_analise')
       AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='veiculos_motoristas' AND column_name='status_aprovacao') THEN
        ALTER TABLE public.veiculos_motoristas RENAME COLUMN status_aprovacao TO status_analise;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='veiculos_motoristas' AND column_name='analisado_por')
       AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='veiculos_motoristas' AND column_name='aprovado_por') THEN
        ALTER TABLE public.veiculos_motoristas RENAME COLUMN aprovado_por TO analisado_por;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='veiculos_motoristas' AND column_name='analisado_em')
       AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='veiculos_motoristas' AND column_name='aprovado_em') THEN
        ALTER TABLE public.veiculos_motoristas RENAME COLUMN aprovado_em TO analisado_em;
    END IF;
    IF EXISTS (SELECT 1 FROM public.veiculos_motoristas GROUP BY user_id HAVING count(*)>1) THEN
        RAISE EXCEPTION 'Mais de um veículo legado por usuário. Reconcilie os vínculos sem excluir evidências antes da migração.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid='public.veiculos_motoristas'::regclass AND c.contype IN ('p','u')
        AND c.conkey=ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid=c.conrelid AND attname='user_id')]::smallint[]) THEN
        ALTER TABLE public.veiculos_motoristas ADD CONSTRAINT uq_veiculo_usuario UNIQUE(user_id);
    END IF;
END $$;

-- A regra anterior exigia dimensões de moto, removidas do contrato atual.
-- As colunas legadas são preservadas; somente a validação incompatível é substituída.
ALTER TABLE public.veiculos_motoristas DROP CONSTRAINT IF EXISTS ck_veiculo_regras_tipo;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.veiculos_motoristas'::regclass AND conname='chk_veiculo_contrato_mobile') THEN
        ALTER TABLE public.veiculos_motoristas ADD CONSTRAINT chk_veiculo_contrato_mobile CHECK (
            (tipo_veiculo='carro' AND compartimento IS NULL AND volume_litros IS NULL AND tamanho_compartimento IS NULL AND capacidade_kg IS NULL)
            OR (tipo_veiculo='moto' AND compartimento='bau' AND volume_litros IS NOT NULL AND volume_litros>0 AND tamanho_compartimento IS NULL AND capacidade_kg IS NOT NULL AND capacidade_kg>0)
            OR (tipo_veiculo='moto' AND compartimento IN ('mochila','bag') AND tamanho_compartimento IN ('pequeno','medio','grande') AND tamanho_compartimento IS NOT NULL AND volume_litros IS NULL AND capacidade_kg IS NOT NULL AND capacidade_kg>0)
        );
    END IF;
END $$;