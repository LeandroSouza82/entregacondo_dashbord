import { CustomerTrackingBrand } from './CustomerTrackingBrand';
import { lazy, Suspense, useEffect, useState } from 'react';
import { supabase } from '../../lib/supabase';
import { trackingIsStale, trackingETA, type ArrivalTracking } from './arrivalTracking';

const ArrivalMap = lazy(() => import('./ArrivalTrackingMap'));
const publicClient = () => supabase; // Uses only the limited token RPC, never table queries.
export function CustomerTrackingView({token}: {token: string}) {
  return <CustomerTrackingSession key={token} token={token} />;
}

function CustomerTrackingSession({token}: {token: string}) {
  const [data, setData] = useState<ArrivalTracking | null>(() => /^[0-9a-f]{64}$/.test(token) ? null : {estado: 'indisponivel'});
  const [error, setError] = useState('');
  const [clock, setClock] = useState(() => Date.now());
  const [serverOffset, setServerOffset] = useState(0);
  useEffect(() => {
    let active = true, timeout: ReturnType<typeof setTimeout>;
    const controller = new AbortController();
    // Fragment URLs keep the bearer secret out of normal server request logs.
    const robots = document.createElement('meta'); robots.name = 'robots'; robots.content = 'noindex, nofollow, noarchive'; document.head.append(robots);
    const referrer = document.createElement('meta'); referrer.name = 'referrer'; referrer.content = 'no-referrer'; document.head.append(referrer);
    async function poll() {
      try {
        const { data: raw, error: err } = await publicClient().rpc('obter_acompanhamento_cliente', {p_token: token}).abortSignal(controller.signal);
        if (!active) return;
        if (err) throw err;
        const next = raw as unknown as ArrivalTracking;
        setData(next); setError('');
        if (next.servidor_em) setServerOffset(Date.parse(next.servidor_em) - Date.now());
        if (next.estado !== 'ativo') return;
      } catch {
        if (!active) return;
        // Discard GPS on HTTP errors too; do not leave cached coordinates onscreen.
        setData(null); setError('Não foi possível atualizar. Verifique a conexão; tentaremos novamente.');
      }
      if (active) timeout = setTimeout(poll, 15_000);
    }
    if (/^[0-9a-f]{64}$/.test(token)) void poll();
    const ticker = setInterval(() => setClock(Date.now()), 15_000);
    return () => { active = false; controller.abort(); clearTimeout(timeout); clearInterval(ticker); robots.remove(); referrer.remove(); };
  }, [token]);
  const now = clock + (Number.isFinite(serverOffset) ? serverOffset : 0);
  const stale = data ? trackingIsStale(data, now) : true;
  const eta = data ? trackingETA(data, now) : null;
  return <main className="min-h-screen bg-slate-50 px-4 py-8 text-slate-900">
    <div className="mx-auto max-w-xl space-y-4">
      <header><p className="text-sm text-slate-600">Acompanhamento do atendimento</p><h1 className="mt-1 text-2xl font-bold">{data?.empresa || 'Sua chegada, acompanhada'}</h1></header>
      {error ? <p role="alert" className="rounded-xl bg-amber-50 p-4 text-amber-900">{error}</p> : null}
      {!data && !error ? <p role="status">Carregando acompanhamento…</p> : null}
      {data?.estado === 'ativo' ? <>
        <section className="overflow-hidden rounded-2xl border border-slate-200 bg-white" aria-label="Mapa do atendimento">
          {data.destino ? <Suspense fallback={<p className="p-6">Carregando mapa…</p>}><ArrivalMap destination={data.destino} position={data.posicao} /></Suspense> : null}
          <div className="space-y-2 p-5" aria-live="polite">
            <p className="text-lg font-semibold">{data.tipo_tarefa === 'coleta' ? 'Coleta a caminho' : data.tipo_tarefa === 'entrega' ? 'Entrega a caminho' : 'Atendimento a caminho'}</p>
            <p>{eta ? `Previsão de chegada: ${eta} (estimativa)` : 'Previsão de chegada indisponível'}</p>
            {data.atualizada_em ? <p className={`text-sm ${stale ? 'text-amber-800' : 'text-slate-600'}`}>{stale ? 'Localização desatualizada. ' : ''}Última atualização: {new Date(data.atualizada_em).toLocaleString('pt-BR')}</p> : <p className="text-sm text-slate-600">Aguardando a primeira localização do motorista.</p>}
          </div>
        </section>
      </> : null}
      {data?.estado === 'encerrado' ? <p role="status" className="rounded-2xl bg-white p-6">Acompanhamento encerrado. A localização do motorista não está mais disponível neste link.</p> : null}
      {data?.estado === 'indisponivel' ? <p role="status" className="rounded-2xl bg-white p-6">Link inválido ou indisponível. Solicite um novo aviso à empresa responsável.</p> : null}
      <CustomerTrackingBrand />
    </div>
  </main>;
}
