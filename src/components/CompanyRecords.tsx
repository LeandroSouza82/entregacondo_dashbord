import { useEffect, useState } from 'react';
import { RotateCw, Inbox } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { requireCompanyId, hasActiveSupabaseSession } from '../lib/company';

export function CompanyRecords({ table, title }: { table: 'entregas' | 'motoristas' | 'clientes_enderecos'; title: string }) {
  const [rows, setRows] = useState<Record<string, unknown>[]>([]);
  const [loading, setLoading] = useState(true);
  const [revision, setRevision] = useState(0);

  useEffect(() => {
    let active = true;

    async function load() {
      setLoading(true);
      try {
        if (!(await hasActiveSupabaseSession())) {
          if (active) setRows([]);
          return;
        }
        const company = await requireCompanyId();
        const { data, error } = await supabase
          .from(table)
          .select('*')
          .eq('empresa_id', company)
          .order('created_at', { ascending: false });

        if (!error && Array.isArray(data)) {
          if (active) setRows(data);
        } else {
          if (active) setRows([]);
        }
      } catch (e) {
        console.warn(`[CompanyRecords] Consulta à tabela ${table} silenciada com fallback seguro:`, e);
        if (active) setRows([]);
      } finally {
        if (active) setLoading(false);
      }
    }

    void load();
    return () => {
      active = false;
    };
  }, [table, revision]);

  return (
    <section className="bg-white border border-gray-300 rounded-2xl p-6 space-y-5 shadow-card animate-fadeIn">
      <header className="flex items-center justify-between pb-4 border-b border-slate-100">
        <div>
          <h1 className="text-xl font-bold text-navy-900">{title}</h1>
          <p className="text-xs text-slate-500 mt-0.5">Registros da empresa no banco de dados</p>
        </div>
        <button
          type="button"
          onClick={() => setRevision(r => r + 1)}
          className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-slate-700 bg-slate-50 hover:bg-slate-100 border border-slate-200 rounded-xl transition-colors"
        >
          <RotateCw className="w-3.5 h-3.5 text-slate-400" />
          <span>Atualizar</span>
        </button>
      </header>

      {loading ? (
        <div className="py-12 text-center text-xs text-slate-500 animate-pulse">
          Carregando registros…
        </div>
      ) : rows.length === 0 ? (
        <div className="py-12 px-4 text-center max-w-sm mx-auto space-y-2">
          <div className="w-12 h-12 rounded-xl bg-slate-50 border border-slate-200 flex items-center justify-center mx-auto text-slate-400">
            <Inbox className="w-6 h-6" />
          </div>
          <h3 className="text-sm font-bold text-navy-900">Nenhum registro encontrado</h3>
          <p className="text-xs text-slate-500">
            Ainda não há dados cadastrados nesta tabela para a empresa ativa.
          </p>
        </div>
      ) : (
        <ul className="divide-y divide-slate-100">
          {rows.map(row => (
            <li key={String(row.id || Math.random())} className="py-3.5 flex items-center justify-between gap-4 text-xs hover:bg-slate-50/60 transition-colors rounded-lg px-2">
              <div>
                <strong className="text-navy-900 font-semibold block">
                  {String(row.nome || row.nome_identificador || row.codigo_rastreio || 'Sem identificador')}
                </strong>
                <p className="text-slate-500 text-[11px] mt-0.5">
                  {String(row.destinatario_nome || row.endereco_completo || row.veiculo_modelo || '')}
                </p>
              </div>
              {row.status ? (
                <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-slate-100 text-slate-700 uppercase tracking-wider">
                  {String(row.status).replace('_', ' ')}
                </span>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
