import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
const url = Deno.env.get('SUPABASE_URL')!;
const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
const environment = Deno.env.get('MP_ENVIRONMENT');
export const billing = {
  accessToken: ['production', 'test'].includes(environment || '') ? Deno.env.get('MERCADOPAGO_ACCESS_TOKEN') || '' : '',
  webhookSecret: Deno.env.get('MERCADOPAGO_WEBHOOK_SECRET') || '',
  publicUrl: 'https://entregacondo.com.br',
  live: environment === 'production',
  fetch,
  reserve: async (jwt: string, company: string) => {
    const publicKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const userClient = createClient(url, publicKey, { global: { headers: { Authorization: 'Bearer ' + jwt } }, auth: { persistSession: false, autoRefreshToken: false } });
    const { data: user, error: authError } = await userClient.auth.getUser(jwt);
    if (authError || !user.user || !user.user.email_confirmed_at) throw new Error('Invalid session');
    const { data, error } = await userClient.rpc('preparar_checkout_assinatura', { p_empresa_id: company });
    if (error) throw error;
    return data;
  },
  link: async (id: string, preapproval: string, checkoutUrl: string) => {
    const { data, error } = await client.rpc('vincular_checkout_assinatura', { p_checkout_id: id, p_preapproval_id: preapproval, p_url: checkoutUrl });
    if (error) throw error; return data === true;
  },
  context: async (id: string) => {
    const { data, error } = await client.rpc('obter_contexto_pagamento_assinatura', { p_pagamento_id: id });
    if (error) throw error; return data;
  },
  record: async (params: Record<string, unknown>) => {
    const { data, error } = await client.rpc('registrar_pagamento_assinatura', { ...params, p_ambiente: environment });
    if (error) throw error; return data === true;
  },
};
