import { supabase } from './supabase';

export async function requireCompanyId(): Promise<string> {
  // 1. Tenta sincronizar perfil na nuvem, mas tolera ausência da RPC no schema cache
  try {
    const profile = await supabase.rpc('sincronizar_meu_perfil');
    if (profile.error) {
      console.warn('[company] RPC sincronizar_meu_perfil ignorada:', profile.error.message);
    }
  } catch (err) {
    console.warn('[company] Falha ao invocar RPC sincronizar_meu_perfil:', err);
  }

  // 2. Tenta obter status de acesso via RPC oficial
  try {
    const { data, error } = await supabase.rpc('obter_meu_status_acesso');
    if (!error && data) {
      const status = data as { empresa_id?: string; status?: string; papel?: string } | null;
      if (status?.empresa_id && (status.status === 'aprovado' || !status.status) && (!status.papel || ['admin', 'gestor'].includes(status.papel))) {
        localStorage.setItem('ec_active_company_id', status.empresa_id);
        return status.empresa_id;
      }
    }
  } catch (err) {
    console.warn('[company] Falha ao invocar RPC obter_meu_status_acesso:', err);
  }

  // 3. Obtém usuário autenticado atual
  const { data: userRes, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userRes?.user) {
    throw new Error('Usuário não autenticado.');
  }

  const userId = userRes.user.id;
  const userMetadata = userRes.user.user_metadata || {};
  const nomeUsuario = userMetadata.name || userMetadata.full_name || userRes.user.email?.split('@')[0] || 'Gestor';

  // Sincroniza perfis_usuarios diretamente se possível
  try {
    await supabase.from('perfis_usuarios').upsert({
      id: userId,
      email: userRes.user.email ?? '',
      nome: nomeUsuario,
      avatar_url: userMetadata.avatar_url ?? null,
      updated_at: new Date().toISOString(),
    }, { onConflict: 'id' });
  } catch {
    // Silencia se RLS não permitir inserção direta
  }

  // 4. Verifica se o usuário já possui vínculo aprovado em empresa_membros
  try {
    const { data: membro } = await supabase
      .from('empresa_membros')
      .select('empresa_id, papel, status')
      .eq('user_id', userId)
      .maybeSingle();

    if (membro?.empresa_id) {
      localStorage.setItem('ec_active_company_id', membro.empresa_id);
      return membro.empresa_id;
    }
  } catch (err) {
    console.warn('[company] Falha ao consultar empresa_membros existente:', err);
  }

  throw new Error('Usuário sem vínculo aprovado com uma empresa. Solicite aprovação do gestor.');
}
