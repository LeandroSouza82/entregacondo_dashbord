ALTER TABLE public.rotas_planejadas
  ADD COLUMN IF NOT EXISTS iniciada_em timestamptz;
