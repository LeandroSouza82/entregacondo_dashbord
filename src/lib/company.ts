import { supabase } from './supabase';
export async function requireCompanyId(): Promise<string> {
  const profile = await supabase.rpc('sincronizar_meu_perfil');
  if (profile.error) throw new Error(profile.error.message);
  const { data, error } = await supabase.rpc('obter_meu_status_acesso');
  if (error) throw new Error(error.message);
  const status = data as { empresa_id?: string; status?: string; papel?: string } | null;
  if (!status?.empresa_id || status.status !== 'aprovado' || !['admin', 'gestor'].includes(status.papel || '')) {
    throw new Error('Acesso de gestão não liberado para esta conta.');
  }
  return status.empresa_id;
}
