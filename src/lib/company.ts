import { supabase } from './supabase';

const DEMO_COMPANY_ID = '11111111-1111-1111-1111-111111111111';

export function isDemoModeActive(): boolean {
  if (typeof window === 'undefined') return false;
  try {
    return (
      new URLSearchParams(window.location.search).get('demo') === 'true' ||
      window.localStorage.getItem('ec_demo_auth') === 'true'
    );
  } catch {
    return false;
  }
}

export async function hasActiveSupabaseSession(): Promise<boolean> {
  try {
    const { data } = await supabase.auth.getSession();
    return Boolean(data?.session?.access_token);
  } catch {
    return false;
  }
}

export class TrialRegistrationRequiredError extends Error {
  constructor() { super('Complete seu cadastro para liberar os 30 dias grátis.'); }
}

export type TrialRegistration = {
  tipo_pessoa: 'pf' | 'pj'; documento: string; nome_responsavel: string;
  razao_social: string; nome_fantasia: string; celular: string;
};

export async function requireCompanyId(registration?: TrialRegistration): Promise<string> {
  const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
  if (sessionError) throw new Error('Não foi possível conferir sua sessão. Entre novamente.');
  if (!sessionData.session) {
    if (import.meta.env.DEV && isDemoModeActive()) return DEMO_COMPANY_ID;
    throw new Error('Usuário não autenticado.');
  }
  const profile = await supabase.rpc('sincronizar_meu_perfil');
  if (profile.error) throw new Error('Não foi possível preparar seu perfil. Tente novamente.');
  for (let attempt = 0; attempt < 2; attempt++) {
    const { data, error } = await supabase.rpc('obter_meu_status_acesso');
    if (error) throw new Error('Não foi possível conferir seu vínculo empresarial. Tente novamente.');
    const access = data as {empresa_id?: string; status?: string; papel?: string; mensagem?: string} | null;
    if (access?.status === 'aprovado' && ['admin', 'gestor'].includes(access.papel || '') && access.empresa_id) {
      localStorage.setItem('ec_active_company_id', access.empresa_id);
      return access.empresa_id;
    }
    if (attempt === 0 && access?.status === 'sem_vinculo') {
      if (!registration) throw new TrialRegistrationRequiredError();
      const result = await supabase.rpc('registrar_teste_empresa', { p_cadastro: registration });
      if (result.error) throw new Error(result.error.message || 'Não foi possível iniciar o teste.');
      if (!(result.data as {sucesso?: boolean})?.sucesso) throw new Error('Não foi possível preparar sua empresa.');
      continue;
    }
    localStorage.removeItem('ec_active_company_id');
    throw new Error(access?.mensagem || 'Acesso de gestão não aprovado nesta empresa.');
  }
  throw new Error('Não foi possível preparar sua empresa. Tente novamente.');
}
