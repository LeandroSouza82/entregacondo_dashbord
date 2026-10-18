import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { requireCompanyId } from '../lib/company';
export function CompanyRecords({ table, title }: { table: 'entregas' | 'motoristas' | 'clientes_enderecos'; title: string }) {
 const [rows, setRows] = useState<Record<string, unknown>[]>([]);
 const [error, setError] = useState(''); const [loading, setLoading] = useState(true); const [revision, setRevision] = useState(0);
 useEffect(() => { let active = true;
   async function load() { setLoading(true); setError(''); try {
     const company = await requireCompanyId();
     const { data, error } = await supabase.from(table).select('*').eq('empresa_id', company).order('created_at', { ascending: false });
     if (error) throw error;
     if (active) setRows(data || []);
   } catch(e) { if (active) { setRows([]); setError(e instanceof Error ? e.message : 'Falha ao consultar o servidor.'); } }
   finally { if(active) setLoading(false); } }
   void load(); return () => { active = false; };
 }, [table, revision]);
 return <section className="bg-white border rounded-2xl p-6 space-y-5"><header className="flex justify-between"><h1 className="text-xl font-bold">{title}</h1><button onClick={() => setRevision(r => r + 1)}>Atualizar</button></header>
 {loading ? <p>Carregando…</p> : error ? <p role="alert" className="text-red-700">{error}</p> : rows.length === 0 ? <p>Nenhum cadastro encontrado.</p> : <ul className="divide-y">{rows.map(row => <li key={String(row.id)} className="py-4"><strong>{String(row.nome || row.nome_identificador || row.codigo_rastreio || '')}</strong><p>{String(row.destinatario_nome || row.endereco_completo || row.veiculo_modelo || '')}</p><p>{String(row.status || '')}</p></li>)}</ul>}
 </section>;
}
