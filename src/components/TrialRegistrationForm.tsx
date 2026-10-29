import { useState, type FormEvent } from 'react';
import type { TrialRegistration } from '../lib/company';
import { isValidDocument, normalizeDocument } from '../lib/trialRegistration';

const inputClass = 'w-full h-11 rounded-xl border-2 border-slate-200 px-3 text-sm text-slate-900 focus:outline-none focus:border-orange-500 focus:ring-2 focus:ring-orange-200';

export function TrialRegistrationForm({ email, initialName, onComplete, onSignOut }: {
  email: string; initialName: string;
  onComplete: (registration: TrialRegistration) => Promise<void>;
  onSignOut: () => Promise<void>;
}) {
  const [kind, setKind] = useState<'pf' | 'pj'>('pf');
  const [document, setDocument] = useState('');
  const [name, setName] = useState(initialName);
  const [legalName, setLegalName] = useState('');
  const [tradeName, setTradeName] = useState('');
  const [phone, setPhone] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError('');
    if (!isValidDocument(kind, document)) { setError(`Informe um ${kind === 'pf' ? 'CPF' : 'CNPJ'} válido.`); return; }
    const mobile = phone.replace(/[()\s-]/g, '');
    if (!/^[1-9]\d9\d{8}$/.test(mobile)) { setError('Informe um celular brasileiro com DDD e 11 dígitos.'); return; }
    if (name.trim().length < 3 || (kind === 'pj' && legalName.trim().length < 2)) { setError('Confira os nomes informados.'); return; }
    setBusy(true);
    try {
      await onComplete({ tipo_pessoa: kind, documento: normalizeDocument(document), nome_responsavel: name.trim(),
        razao_social: kind === 'pj' ? legalName.trim() : '', nome_fantasia: tradeName.trim(), celular: mobile });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Não foi possível concluir o cadastro. Tente novamente.');
    } finally { setBusy(false); }
  }

  return <form onSubmit={submit} className="space-y-4" aria-label="Cadastro para teste grátis">
    <div className="text-sm text-slate-600 space-y-2">
      <p className="font-semibold text-slate-900">Etapa 2 de 2 · Complete seu cadastro</p>
      <p>E-mail confirmado: <span className="break-all">{email}</span></p>
      <p>Seus 30 dias começam após concluir esta etapa. Um teste por CPF ou CNPJ, sem cartão.</p>
    </div>
    <fieldset disabled={busy} className="space-y-4">
      <legend className="text-xs font-bold text-slate-800 mb-2">Tipo de cadastro</legend>
      <div className="flex flex-wrap gap-4 text-sm">
        <label className="flex gap-2 items-center"><input type="radio" name="person-kind" value="pf" checked={kind === 'pf'} onChange={() => { setKind('pf'); setDocument(''); setError(''); }} />Pessoa física</label>
        <label className="flex gap-2 items-center"><input type="radio" name="person-kind" value="pj" checked={kind === 'pj'} onChange={() => { setKind('pj'); setDocument(''); setError(''); }} />Pessoa jurídica</label>
      </div>
      <div>
        <label htmlFor="trial-document" className="block text-xs font-bold text-slate-800 mb-1.5">{kind === 'pf' ? 'CPF' : 'CNPJ'} *</label>
        <input id="trial-document" className={inputClass} required autoComplete="off" inputMode={kind === 'pf' ? 'numeric' : 'text'} autoCapitalize="characters" spellCheck={false}
          maxLength={18} value={document} onChange={e => setDocument(e.target.value)} aria-describedby="trial-document-help" />
        <p id="trial-document-help" className="text-xs text-slate-500 mt-1">Use seu documento ou o da empresa que você representa. Trocar de conta não renova o teste.</p>
      </div>
      <div>
        <label htmlFor="trial-name" className="block text-xs font-bold text-slate-800 mb-1.5">{kind === 'pf' ? 'Nome completo' : 'Nome completo do responsável'} *</label>
        <input id="trial-name" className={inputClass} required minLength={3} maxLength={120} autoComplete="name" value={name} onChange={e => setName(e.target.value)} />
      </div>
      {kind === 'pj' && <div>
        <label htmlFor="trial-legal-name" className="block text-xs font-bold text-slate-800 mb-1.5">Razão social *</label>
        <input id="trial-legal-name" className={inputClass} required minLength={2} maxLength={120} autoComplete="organization" value={legalName} onChange={e => setLegalName(e.target.value)} />
      </div>}
      <div>
        <label htmlFor="company-name" className="block text-xs font-bold text-slate-800 mb-1.5">{kind === 'pj' ? 'Nome fantasia' : 'Nome do negócio'} (opcional)</label>
        <input id="company-name" className={inputClass} maxLength={120} value={tradeName} onChange={e => setTradeName(e.target.value)} aria-describedby="company-name-help" />
        <p id="company-name-help" className="text-xs text-slate-500 mt-1">Identifica seus atendimentos. Se ficar vazio, usaremos {kind === 'pj' ? 'a razão social' : 'seu nome'}.</p>
      </div>
      <div>
        <label htmlFor="trial-phone" className="block text-xs font-bold text-slate-800 mb-1.5">Celular com DDD *</label>
        <input id="trial-phone" className={inputClass} type="tel" required autoComplete="tel-national" maxLength={16} placeholder="(48) 99999-9999" value={phone} onChange={e => setPhone(e.target.value)} />
      </div>
    </fieldset>
    {error && <p role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-700">{error}</p>}
    <p className="text-xs text-slate-500">Usamos estes dados para seu cadastro e controle do teste. O registro de uso do CPF/CNPJ é mantido para impedir novas liberações, inclusive após excluir a conta.</p>
    <button type="submit" disabled={busy} className="w-full rounded-xl bg-orange-600 py-3 text-sm font-bold text-white hover:bg-orange-700 disabled:opacity-50">{busy ? 'Concluindo cadastro…' : 'Concluir cadastro e liberar 30 dias'}</button>
    <button type="button" disabled={busy} onClick={() => { setBusy(true); void onSignOut().catch(() => { setError('Não foi possível sair. Tente novamente.'); setBusy(false); }); }} className="w-full text-sm text-slate-600 underline disabled:opacity-50">Entrar com outra conta</button>
  </form>;
}
