import { useEffect, useRef, useState, type FormEvent } from 'react';
import { createEmailActionClient, supabase } from '../lib/supabase';
import { EntregaCondoLogo } from './common/EntregaCondoLogo';

export default function EmailActionView({ recovery, legacy = false }: { recovery: boolean; legacy?: boolean }) {
  const [client] = useState(() => legacy ? supabase : createEmailActionClient());
  const [token] = useState(() => new URLSearchParams(window.location.hash.split('?')[1] || '').get('token_hash') || '');
  const [ready, setReady] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [password, setPassword] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const verification = useRef<Promise<void> | null>(null);
  const [done, setDone] = useState(false);
  useEffect(() => {
    let active = true;
    if (!verification.current) verification.current = (async () => {
      if (legacy) {
        const { data, error: err } = await client.auth.getSession();
        if (err || !data.session) throw new Error('invalid');
        const user = await client.auth.getUser();
        if (user.error || !user.data.user?.email_confirmed_at) throw new Error('invalid');
      } else {
        if (!token || !/^[a-f0-9]{32,128}$/i.test(token)) throw new Error('invalid');
        const { data, error: err } = await client.auth.verifyOtp({ token_hash: token, type: recovery ? 'recovery' : 'signup' });
        if (err || !data.user || !data.session) throw new Error('invalid');
      }
      if (!recovery) {
        const signOut = await client.auth.signOut({ scope: 'local' });
        if (signOut.error) throw new Error('signout');
      }
    })();
    void verification.current.then(() => {
      if (!active) return;
      // Remove one-time credentials from the address/history after consumption.
      window.history.replaceState(null, '', recovery ? '/#/definir-senha' : '/#/ativar');
      setReady(true); if (!recovery) window.location.replace('/#/login?ativado=1');
    }).catch(() => { if (active) setError('Este link está inválido, já foi utilizado ou venceu. Volte ao login e solicite um novo e-mail.'); });
    return () => { active = false; };
  }, [client, legacy, recovery, token]);
  async function save(event: FormEvent) {
    event.preventDefault(); setError('');
    if (password.length < 8) { setError('Use uma senha com pelo menos 8 caracteres.'); return; }
    if (password !== confirmation) { setError('As senhas precisam ser iguais.'); return; }
    setBusy(true);
    try {
      const { error: err } = await client.auth.updateUser({ password });
      if (err) throw err;
      const result = await client.auth.signOut({ scope: 'local' });
      if (result.error) throw result.error;
      setPassword(''); setConfirmation(''); setDone(true); window.location.replace('/#/login?senha=definida');
    } catch { setError('Não foi possível concluir. Tente novamente; se o link venceu, solicite outro pelo login.'); }
    finally { setBusy(false); }
  }
  return <main className="flex min-h-screen items-center justify-center bg-slate-100 p-5">
    <section className="w-full max-w-md space-y-5 rounded-3xl bg-white p-8 shadow-lg">
      <EntregaCondoLogo height={44} wordmarkColor="#0F1B2D" subtitle="Gestão" />
      <h1 className="text-2xl font-bold text-slate-900">{done ? recovery ? 'Senha definida' : 'Seu acesso foi ativado' : recovery ? 'Defina sua senha' : 'Ativando seu acesso'}</h1>
      {done ? <><p>{recovery ? 'Agora entre com seu e-mail e a senha que você acabou de definir.' : 'Bem-vindo ao EntregaCondo Gestão! Agora entre com o e-mail e a senha do cadastro. Seus 30 dias começam quando sua empresa for criada no primeiro acesso.'}</p><a href="/#/login" className="inline-flex min-h-12 items-center rounded-xl bg-orange-700 px-5 py-3 font-bold text-white">Ir para o login</a></> : ready && recovery ? <form onSubmit={save} className="space-y-4">
        <label className="block font-semibold">Nova senha<input type="password" autoComplete="new-password" minLength={8} required value={password} onChange={e => setPassword(e.target.value)} className="mt-2 block min-h-11 w-full rounded-lg border border-slate-300 p-3" /></label>
        <label className="block font-semibold">Repita a nova senha<input type="password" autoComplete="new-password" minLength={8} required value={confirmation} onChange={e => setConfirmation(e.target.value)} className="mt-2 block min-h-11 w-full rounded-lg border border-slate-300 p-3" /></label>
        <button disabled={busy} className="min-h-12 rounded-xl bg-orange-700 px-5 py-3 font-bold text-white disabled:opacity-50">{busy ? 'Salvando…' : 'Salvar senha e ir para o login'}</button>
      </form> : !error && <p role="status">Conferindo seu link de acesso…</p>}
      {error && <><p role="alert" className="text-red-700">{error}</p><a href="/#/login" className="inline-flex min-h-11 items-center font-semibold text-orange-800 underline">Voltar ao login</a></>}
    </section>
  </main>;
}
