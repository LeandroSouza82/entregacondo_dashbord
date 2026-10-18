import { supabase, isSupabaseConfigured } from '../../../lib/supabase';
import type { VeiculoDeclarado } from '../types/vehicle';

export async function obterVeiculosEmpresa(): Promise<VeiculoDeclarado[]> {
  if (!isSupabaseConfigured) {
    return [];
  }

  const { data, error } = await supabase
    .from('veiculos_motoristas')
    .select('*')
    .order('created_at', { ascending: false });

  if (error) {
    console.warn('Aviso ao consultar veiculos_motoristas:', error.message);
    return [];
  }

  return (data || []) as VeiculoDeclarado[];
}
