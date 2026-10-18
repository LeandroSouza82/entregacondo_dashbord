import { supabase, isSupabaseConfigured } from '../../../lib/supabase';
import type { DocumentoVeiculoItem } from '../types/vehicleDocument';

export async function obterDocumentosVeiculo(veiculoId: string): Promise<DocumentoVeiculoItem[]> {
  if (!isSupabaseConfigured) {
    return [];
  }

  const { data, error } = await supabase
    .from('veiculos_documentos')
    .select('*')
    .eq('veiculo_id', veiculoId)
    .order('created_at', { ascending: true });

  if (error) {
    console.warn('Aviso ao consultar veiculos_documentos:', error.message);
    return [];
  }

  return (data || []) as DocumentoVeiculoItem[];
}
