import { useEffect, useState } from 'react';
import { requireCompanyId } from '../lib/company';
import { supabase } from '../lib/supabase';
import { notifyCompanyNameChanged } from '../lib/companyIdentity';

export function CompanySettings() {
  const [companyId, setCompanyId] = useState('');
  const [name, setName] = useState('');
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState('');
  const [saved, setSaved] = useState(false);
  useEffect(() => {
    let active = true;
    void (async () => {
      try {
        const id = await requireCompanyId();
        const { data, error: err } = await supabase.from('empresas').select('nome').eq('id', id).single();
        if (err) throw err;
        if (active) { setCompanyId(id); setName(data.nome); }
      } catch { if (active) setError('Não foi possível carregar a empresa.'); }
      finally { if (active) setBusy(false); }
    })();
    return () => { active = false; };
  }, []);
  async function save(event: React.FormEvent) {
    event.preventDefault(); setBusy(true); setError(''); setSaved(false);
    try {
      const { data, error: err } = await supabase.rpc('configurar_nome_empresa', { p_empresa_id: companyId, p_nome: name.trim() });
      if (err || !(data as {sucesso?: boolean})?.sucesso) throw err || new Error();
      notifyCompanyNameChanged(companyId, name);
      setSaved(true);
    } catch { setError('Não foi possível salvar o nome. Confira seu acesso de gestão e tente novamente.'); }
    finally { setBusy(false); }
  }
  return <form onSubmit={save} className="bg-white rounded-2xl p-6 border border-slate-200 max-w-xl space-y-4">
    <h2 className="text-xl font-bold text-navy-900">Configurações da empresa</h2>
    <p className="text-sm text-slate-600">Este é o nome que seus clientes verão nas mensagens, no acompanhamento e nos comprovantes. Cadastre uma vez para todos os motoristas.</p>
    <label className="block text-sm font-semibold">Nome da empresa
      <input value={name} onChange={e => { setName(e.target.value); setSaved(false); }} required minLength={2} maxLength={120} disabled={busy} className="mt-2 block w-full rounded-lg border border-slate-300 p-3" />
    </label>
    <section aria-label="Prévia da mensagem ao cliente" className="rounded-xl bg-slate-50 p-4 text-sm text-slate-700">
      <p className="mb-2 font-semibold">Assim sua empresa aparece para o cliente</p>
      <p>Olá! Sou [motorista], da {name.trim() || '[sua empresa]'}. Estou a caminho para realizar sua entrega.</p>
      <p className="mt-3 text-xs text-slate-500">Tecnologia EntregaCondo</p>
    </section>
    {error ? <p role="alert" className="text-sm text-red-700">{error}</p> : null}
    {saved ? <p role="status" className="text-sm text-green-700">Nome da empresa salvo.</p> : null}
    <button disabled={busy || !companyId} className="rounded-lg bg-blue-700 px-4 py-3 text-white disabled:opacity-50">{busy ? 'Aguarde…' : 'Salvar nome'}</button>
  </form>;
}
