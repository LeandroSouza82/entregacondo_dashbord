import { useEffect, useRef, useState } from 'react';
import { requireCompanyId } from '../lib/company';
import { supabase } from '../lib/supabase';

type Subscription = {
  legado: boolean; operacional: boolean; estado?: string; dias_restantes?: number;
  teste_fim?: string; pago_ate?: string; servidor_em: string;
  atendimentos_mes?: number; limite_atendimentos?: number;
  checkout_estado?: 'pending' | 'authorized' | 'paused' | 'cancelled' | null;
  checkout_pendente?: boolean; cobranca_inicio?: string | null;
};
function dateTime(value?: string | null) {
  if (!value || !Number.isFinite(Date.parse(value))) return 'a data informada no checkout';
  return new Intl.DateTimeFormat('pt-BR', { dateStyle: 'short', timeStyle: 'short', timeZone: 'America/Sao_Paulo' }).format(new Date(value));
}

export function CompanySubscriptionNotice() {
  const [subscription, setSubscription] = useState<Subscription | null>(null);
  const [companyId, setCompanyId] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [revision, setRevision] = useState(0);
  const [message, setMessage] = useState('');
  const alive = useRef(true);
  const operation = useRef(false);
  useEffect(() => { alive.current = true; return () => { alive.current = false; }; }, []);
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
        const expiry = Math.max(Date.parse(next.teste_fim || '') || 0, Date.parse(next.pago_ate || '') || 0);
        const remaining = expiry - Date.parse(next.servidor_em);
        timer = setTimeout(refresh, next.legado ? 300_000 : remaining > 0 ? Math.max(1000, Math.min(30_000, remaining + 100)) : 30_000);
      } catch {
        if (active && generation === sequence) {
          setCompanyId(''); setSubscription(null);
          setError('Não foi possível conferir a assinatura. Tente atualizar em instantes.');
          timer = setTimeout(refresh, 30_000);
        }
      }
    }
    void refresh();
    window.addEventListener('focus', refresh);
    return () => { active = false; clearTimeout(timer); window.removeEventListener('focus', refresh); };
  }, [revision]);

  async function billingAction(consultar: boolean) {
    if (operation.current || !companyId) return;
    operation.current = true; setBusy(true); setError(''); setMessage('');
    try {
      const id = await requireCompanyId();
      if (id !== companyId) throw new Error('Company changed');
      const { data, error: err } = await supabase.functions.invoke('assinatura-checkout', { body: { empresa_id: id, consultar } });
      if (!alive.current) return;
      if (await requireCompanyId() !== id) throw new Error('Company changed');
      if (err) {
        let detail: unknown;
        try { detail = (await err.context?.json())?.error; } catch { /* No JSON error body. */ }
        if (typeof detail === 'string' && detail.startsWith('Pagamentos ainda estão em validação')) {
          setError('As assinaturas estão em validação. A contratação real ainda não está disponível; seu teste continua até a data indicada.');
          return;
        }
        throw err;
      }
      if (consultar || data?.estado === 'authorized') {
        setMessage(data?.estado === 'authorized'
          ? 'Contratação confirmada pelo Mercado Pago. A liberação paga depende da confirmação da mensalidade.'
          : data?.estado === 'sem_checkout' ? 'Nenhuma contratação iniciada. Você pode assinar pelo botão abaixo.'
          : 'Situação conferida. Se ainda estiver pendente, conclua a contratação no Mercado Pago.');
        setRevision(value => value + 1);
        return;
      }
      const url = new URL(data?.url);
      if (url.protocol !== 'https:' || !['www.mercadopago.com.br', 'mercadopago.com.br'].includes(url.hostname)) throw new Error();
      window.location.assign(url.href);
    } catch {
      if (alive.current) setError(consultar ? 'Não foi possível conferir o Mercado Pago. Tente novamente em instantes.' : 'Não foi possível abrir o pagamento. Tente novamente em instantes.');
    } finally {
      operation.current = false;
      if (alive.current) setBusy(false);
    }
  }
  const returned = /^#\/?assinatura\/?$/.test(window.location.hash);
  if (subscription?.legado) return null;
  if (!subscription) return error ? <section aria-label="Assinatura da empresa" className="px-6 py-3"><p role="alert">{error}</p><button onClick={() => setRevision(value => value + 1)} className="min-h-11 underline">Atualizar assinatura</button></section> : null;
  const trial = subscription.estado === 'teste';
  const paid = subscription.estado === 'ativa';
  const suspended = subscription.estado === 'suspensa';
  const authorized = subscription.checkout_estado === 'authorized';
  const paused = subscription.checkout_estado === 'paused';
  const canSubscribe = !paid && !suspended && !authorized && !paused;
  return <section id="assinatura" aria-label="Assinatura da empresa" className="border-b border-amber-200 bg-amber-50 px-4 py-4 text-sm text-slate-800 sm:px-8">
    <div className="flex flex-wrap items-center justify-between gap-4">
      <div className="max-w-3xl">
        <p className="font-semibold">{trial ? `Teste grátis: ${subscription.dias_restantes} dias restantes` : paid ? 'Assinatura ativa' : suspended ? 'Assinatura suspensa' : 'Seu período de acesso terminou'}</p>
        <p className="mt-1">Plano de R$ 149,90/mês por empresa · até 3 motoristas ativos e 1.000 atendimentos por mês.</p>
        {trial && <p className="mt-2">Seu teste vai até {dateTime(subscription.teste_fim)} (horário de Brasília). Você pode assinar agora: mantém os dias grátis e a primeira mensalidade fica prevista para o fim do teste. Depois, a cobrança é mensal pelo Mercado Pago.</p>}
        {authorized && <p className="mt-2 font-medium">Contratação confirmada no Mercado Pago.{trial ? ` Primeira cobrança prevista para ${dateTime(subscription.cobranca_inicio || subscription.teste_fim)}.` : ' Aguardando confirmação da mensalidade para liberar o período pago.'}</p>}
        {subscription.checkout_pendente && !authorized && <p className="mt-2">Contratação iniciada, ainda pendente. Continue no Mercado Pago para confirmar o meio de pagamento.</p>}
        {paid && <p className="mt-2">Acesso pago até {dateTime(subscription.pago_ate)}. A continuidade depende da confirmação das próximas mensalidades.</p>}
        {paused && <p className="mt-2">A recorrência está pausada no Mercado Pago. Confira e regularize a assinatura por lá.</p>}
        {subscription.checkout_estado === 'cancelled' && <p className="mt-2">A recorrência foi cancelada. Você pode contratar novamente quando não houver período pago ativo.</p>}
        {!subscription.operacional && <p className="mt-2">Seus dados continuam disponíveis para consulta. Novas operações e conclusões de atendimentos ficam bloqueadas até a confirmação do pagamento.{suspended ? ' Consulte o suporte para regularizar a suspensão.' : ''}</p>}
        {trial && !authorized && <p className="mt-1 text-xs">Sem contratação, não há cobrança automática ao fim do teste. Após vencer, ficam disponíveis as consultas; operar exige pagamento confirmado.</p>}
        <p className="mt-1 text-xs">Uso neste mês: {subscription.atendimentos_mes ?? 0} de {subscription.limite_atendimentos ?? 1000} atendimentos.</p>
      </div>
      <div className="flex flex-wrap gap-2">
        {canSubscribe && <button onClick={() => void billingAction(false)} disabled={busy || !companyId} className="min-h-11 rounded-xl bg-orange-700 px-4 py-2 font-semibold text-white disabled:opacity-50">{busy ? 'Aguarde…' : subscription.checkout_pendente ? 'Continuar contratação · R$ 149,90/mês' : 'Assinar por R$ 149,90/mês'}</button>}
        {(returned || authorized || subscription.checkout_pendente || paid || paused) && <button onClick={() => void billingAction(true)} disabled={busy || !companyId} className="min-h-11 rounded-xl border border-slate-400 bg-white px-4 py-2 font-semibold disabled:opacity-50">{busy ? 'Conferindo…' : 'Conferir no Mercado Pago'}</button>}
      </div>
    </div>
    {returned && <p className="mt-3">Você voltou do Mercado Pago. Confira a situação acima; voltar a esta página não confirma a contratação nem o pagamento.</p>}
    {message && <p role="status" className="mt-2">{message}</p>}
    {error && <p role="alert" className="mt-2 text-red-700">{error}</p>}
  </section>;
}
