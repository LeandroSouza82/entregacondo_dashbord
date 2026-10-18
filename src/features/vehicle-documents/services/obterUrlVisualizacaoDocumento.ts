import { supabase, isSupabaseConfigured } from '../../../lib/supabase';

/**
 * Gera URL assinada temporária para visualização segura de documentos.
 * NUNCA utiliza getPublicUrl para documentos pessoais ou cadastrais.
 */
export async function obterUrlVisualizacaoDocumento(storagePath: string, expiresInSegundos = 3600): Promise<string> {
  if (!isSupabaseConfigured) {
    throw new Error('Supabase não configurado.');
  }

  const { data, error } = await supabase.storage
    .from('veiculos-documentos')
    .createSignedUrl(storagePath, expiresInSegundos);

  if (error || !data?.signedUrl) {
    throw new Error(error?.message || 'Falha ao gerar link seguro de visualização.');
  }

  return data.signedUrl;
}
