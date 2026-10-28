import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';

export function AuthEmailActions({ email }: { email: string }) {
  const [busy, setBusy] = useState(false);
  const [seconds, setSeconds] = useState(0);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  useEffect(() => {
    if (!seconds) return;
    const timer = setTimeout(() => setSeconds(value => value - 1), 1000);
    return () => clearTimeout(timer);
  }, [seconds]);
  async function send(kind: 'confirmation' | 'recovery') {
    setMessage(''); setError('');
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) { setError('Preencha seu e-mail no campo acima.'); return; }
    setBusy(true);
    try {
      const result = kind === 'confirmation'
        ? await supabase.auth.resend({ type: 'signup', email: email.trim(), options: { emailRedirectTo: window.location.origin + '/?auth_action=signup' } })
        : await supabase.auth.resetPasswordForEmail(email.trim(), { redirectTo: window.location.origin + '/?auth_action=recovery' });
      if (result.error) throw result.error;
      setSeconds(60);
      setMessage(kind === 'confirmation'
        ? 'Se houver uma confirmação pendente para esse e-mail, você receberá o link. Confira também o spam. Se já tinha conta, entre com Google ou use a opção de senha.'
        : 'Se esse e-mail puder receber a recuperação, enviaremos um link para definir sua senha. Confira também o spam.');
    } catch { setError('Não foi possível solicitar o e-mail. Aguarde e tente novamente. Se continuar, fale com o suporte.'); }
    finally { setBusy(false); }
  }
  async function google() {
    setBusy(true); setError('');
    try {
      const { error: err } = await supabase.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: window.location.origin + '/', queryParams: { prompt: 'select_account' } } });
      if (err) throw err;
    } catch { setError('Não foi possível abrir o Google. Tente novamente em instantes.'); }
    finally { setBusy(false); }
  }
  return <section aria-label="Ajuda para acessar sua conta" className="space-y-2 border-t border-slate-200 pt-4 text-sm">
    <button type="button" onClick={() => void google()} disabled={busy} className="min-h-11 w-full rounded-xl border border-slate-300 bg-white px-3 py-2 font-semibold disabled:opacity-50">Continuar com Google</button>
    <p className="text-xs text-slate-600">Já usava Google? Entre por ele. Uma nova tentativa de cadastro não cria nem troca a senha da sua conta.</p>
    <button type="button" onClick={() => void send('recovery')} disabled={busy || seconds > 0} className="min-h-11 w-full rounded-lg px-2 text-left font-semibold text-orange-800 underline disabled:opacity-50">Esqueci ou quero definir minha senha</button>
    <button type="button" onClick={() => void send('confirmation')} disabled={busy || seconds > 0} className="min-h-11 w-full rounded-lg px-2 text-left text-slate-700 underline disabled:opacity-50">Reenviar confirmação de e-mail</button>
    {seconds > 0 && <p className="text-xs text-slate-500">Aguarde {seconds}s para solicitar outro e-mail.</p>}
    {message && <p role="status" className="rounded-lg bg-emerald-50 p-3 text-xs text-emerald-900">{message}</p>}
    {error && <p role="alert" className="text-xs text-red-700">{error}</p>}
  </section>;
}
