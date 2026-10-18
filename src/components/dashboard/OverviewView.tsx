import { useEffect, useState } from 'react';
import { supabase } from '../../lib/supabase';
import { requireCompanyId } from '../../lib/company';
import type { Database } from '../../types/database';
type Delivery = Database['public']['Tables']['entregas']['Row'];
export function OverviewView({ onGoToOptimizer, onOpenNewDelivery }: { onGoToOptimizer?: () => void; onOpenNewDelivery?: () => void }) {
  const [deliveries, setDeliveries] = useState<Delivery[]>([]);
  const [drivers, setDrivers] = useState(0);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    let active = true;
    async function load() {
      setLoading(true); setError('');
      try {
        const id = await requireCompanyId();
        const today = new Date(); today.setHours(0, 0, 0, 0);
        const results = await Promise.all([
          supabase.from('entregas').select('*').eq('empresa_id', id).gte('created_at', today.toISOString()).order('created_at', { ascending: false }),
          supabase.from('motoristas').select('id', { count: 'exact', head: true }).eq('empresa_id', id).eq('ativo', true),
        ]);
        for (const result of results) if (result.error) throw result.error;
        if (active) { setDeliveries(results[0].data || []); setDrivers(results[1].count || 0); }
      } catch (e) { if (active) { setDeliveries([]); setDrivers(0); setError(e instanceof Error ? e.message : 'Falha ao consultar o banco.'); } }
      finally { if (active) setLoading(false); }
    }
    void load(); return () => { active = false; };
  }, [revision]);
  const counts = [['Entregas hoje', deliveries.length], ['Concluídas', deliveries.filter(d => d.status === 'entregue').length], ['Em trânsito', deliveries.filter(d => d.status === 'em_transito').length], ['Motoristas ativos', drivers]];
  return <section className="space-y-6"><header className="flex justify-between"><h1 className="text-2xl font-bold">Visão geral</h1><div className="flex gap-4"><button onClick={() => setRevision(r => r + 1)}>Atualizar</button><button onClick={onGoToOptimizer || onOpenNewDelivery}>Nova entrega</button></div></header>
    {loading ? <p>Carregando dados da empresa…</p> : error ? <p role="alert" className="text-red-700">{error}</p> : <><div className="grid grid-cols-2 lg:grid-cols-4 gap-4">{counts.map(([label, count]) => <div key={label} className="bg-white border rounded-xl p-5"><p>{label}</p><strong className="text-3xl">{count}</strong></div>)}</div><div className="bg-white border rounded-xl p-5"><h2 className="font-bold mb-4">Entregas de hoje</h2>{deliveries.length === 0 ? <p>Nenhuma entrega cadastrada hoje.</p> : <ul className="divide-y">{deliveries.map(d => <li key={d.id} className="py-3 flex justify-between gap-3"><span>{d.codigo_rastreio} · {d.destinatario_nome}</span><span>{d.status}</span></li>)}</ul>}</div></>}
  </section>;
}
