import { useEffect, useState } from 'react';
import { requireCompanyId } from '../lib/company';
import { supabase } from '../lib/supabase';

type Subscription = {
  legado: boolean; operacional: boolean; estado?: string; dias_restantes?: number;
  teste_fim?: string; pago_ate?: string; servidor_em: string;
  atendimentos_mes?: number; limite_atendimentos?: number; motoristas_ativos?: number;
};

export function CompanySubscriptionNotice() {
  const [subscription, setSubscription] = useState<Subscription | null>(null);
  const [companyId, setCompanyId] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let active = true;
    let sequence = 0;
    let timer: ReturnType<typeof setTimeout>;
    async function refresh() {
      const generation = ++sequence;
      clearTimeout(timer);
      try {
        const id = await requireCompanyId();
        const { data, error: err } = await supabase.rpc('obter_minha_assinatura', { p_empresa_id: id });
        if (err) throw err;
        const next = data as unknown as Subscription;
        if (typeof next?.legado !== 'boolean' || typeof next?.operacional !== 'boolean') throw new Error();
        if (!active || generation !== sequence) return;
        setCompanyId(id); setSubscription(next); setError('');
        // Match server time; the phone/computer clock cannot extend the trial.
        const expiry = Math.max(Date.parse(next.teste_fim || '') || 0, Date.parse(next.pago_ate || '') || 0);
        const remaining = expiry - Date.parse(next.servidor_em);
        timer = setTimeout(refresh, next.legado ? 300_000 : remaining > 0 ? Math.max(1000, Math.min(60_000, remaining + 100)) : 60_000);
      } catch {
        if (active && generation === sequence) { setError('Não foi possível conferir a assinatura. Tentaremos novamente.'); timer = setTimeout(refresh, 30_000); }
      }
    }
    void refresh();
    window.addEventListener('focus', refresh);
    return () => { active = false; clearTimeout(timer); window.removeEventListener('focus', refresh); };
  }, []);
  async function subscribe() {
    setBusy(true); setError('');
    try {
      const { data, error: err } = await supabase.functions.invoke('assinatura-checkout', { body: { empresa_id: companyId } });
      if (err) throw err;
      const url = new URL(data?.url);
      if (url.protocol !== 'https:' || !['www.mercadopago.com.br', 'mercadopago.com.br'].includes(url.hostname)) throw new Error();
      window.location.assign(url.href);
    } catch { setError('Não foi possível abrir o pagamento. Tente novamente em instantes.'); }
    finally { setBusy(false); }
  }
  if (subscription?.legado) return error ? <p role="alert" className="px-6 py-3 text-sm text-amber-900">{error}</p> : null;
  if (!subscription) return error ? <p role="alert" className="px-6 py-3 text-sm text-amber-900">{error}</p> : null;
  return <section aria-label="Assinatura da empresa" className="border-b border-amber-200 bg-amber-50 px-4 py-3 text-sm text-slate-800 sm:px-8">
    <div className="flex flex-wrap items-center justify-between gap-3">
      <div>
        <p className="font-semibold">{subscription.estado === 'teste' ? `Teste grátis: ${subscription.dias_restantes} dias restantes` : subscription.operacional ? 'Assinatura ativa' : 'Seu período de acesso terminou'}</p>
        <p className="mt-1 text-xs">{subscription.operacional ? `${subscription.atendimentos_mes ?? 0} de 1.000 atendimentos neste mês · até 3 motoristas ativos` : 'Seus dados continuam disponíveis para consulta. Assine para retomar as operações.'}</p>
      </div>
      {!subscription.operacional && <button onClick={subscribe} disabled={busy || !companyId} className="min-h-11 rounded-xl bg-orange-700 px-4 py-2 font-semibold text-white disabled:opacity-50">{busy ? 'Abrindo pagamento…' : 'Assinar por R$ 149,90/mês'}</button>}
    </div>
    {error && <p role="alert" className="mt-2 text-red-700">{error}</p>}
  </section>;
}
