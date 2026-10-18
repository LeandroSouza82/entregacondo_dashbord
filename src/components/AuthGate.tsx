import { useEffect, useState, type ReactNode, type FormEvent } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase, isSupabaseConfigured } from '../lib/supabase';
import { requireCompanyId } from '../lib/company';
export function AuthGate({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [ready, setReady] = useState(false);
  const [allowed, setAllowed] = useState(false);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  useEffect(() => {
    let active = true;
    supabase.auth.getSession().then(({ data, error }) => {
      if (!active) return;
      if (error) setError(error.message);
      setSession(data.session); setReady(true);
    });
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, value) => {
      if (active) { setSession(value); setAllowed(false); setError(''); }
    });
    return () => { active = false; subscription.unsubscribe(); };
  }, []);
  useEffect(() => {
    let active = true;
    if (session) requireCompanyId().then(() => { if (active) setAllowed(true); })
      .catch((e: Error) => { if (active) setError(e.message); });
    return () => { active = false; };
  }, [session]);
  async function login(event: FormEvent) {
    event.preventDefault(); setBusy(true); setError('');
    try {
      const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
      if (error) throw error;
    } catch (e) { setError(e instanceof Error ? e.message : 'Não foi possível entrar.'); }
    finally { setBusy(false); }
  }
  if (session && allowed) return <><div className="flex justify-end gap-4 p-2 bg-white text-sm"><span>{session.user.email}</span><button onClick={() => void supabase.auth.signOut().then(({ error }) => { if (error) setError(error.message); })}>Sair da conta</button>{error && <span role="alert">{error}</span>}</div>{children}</>;
  return <main className="min-h-screen flex items-center justify-center bg-slate-50 p-6"><form onSubmit={login} className="w-full max-w-md bg-white rounded-2xl p-8 border space-y-5"><h1 className="text-2xl font-bold">EntregaCondo · Gestão</h1>
    {!isSupabaseConfigured ? <p role="alert">Configure a conexão do EntregaCondo para continuar.</p> : !ready ? <p>Carregando…</p> : session ? <><p>{error || 'Conferindo acesso à empresa…'}</p><button type="button" onClick={() => window.location.reload()}>Atualizar acesso</button><button type="button" onClick={() => void supabase.auth.signOut()}>Sair</button></> : <>
    <label className="block">E-mail<input className="block w-full border rounded-lg p-3" type="email" autoComplete="username" required value={email} onChange={e => setEmail(e.target.value)} /></label>
    <label className="block">Senha<input className="block w-full border rounded-lg p-3" type="password" autoComplete="current-password" required value={password} onChange={e => setPassword(e.target.value)} /></label>
    {error && <p role="alert" className="text-red-700">{error}</p>}<button disabled={busy} className="w-full bg-orange-700 text-white rounded-lg p-3">{busy ? 'Entrando…' : 'Entrar'}</button></>}
  </form></main>;
}
