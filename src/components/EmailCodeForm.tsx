import { useEffect, useState, type FormEvent } from 'react';
import { supabase } from '../lib/supabase';

export function EmailCodeForm({ email, onBack }: { email: string; onBack: () => void }) {
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [seconds, setSeconds] = useState(60);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  useEffect(() => {
    if (!seconds) return;
    const timer = window.setTimeout(() => setSeconds(value => value - 1), 1000);
    return () => window.clearTimeout(timer);
  }, [seconds]);
  async function verify(event: FormEvent) {
    event.preventDefault();
    if (!/^\d{6,10}$/.test(code)) { setError('Informe o código numérico recebido por e-mail.'); return; }
    setBusy(true); setError(''); setMessage('');
    try {
      const { data, error: err } = await supabase.auth.verifyOtp({ email, token: code, type: 'signup' });
      if (err || !data.session) {
        setError(err?.code === 'over_request_rate_limit' ? 'Muitas tentativas. Aguarde antes de tentar novamente.' : 'Código incorreto, expirado ou já utilizado. Confira o e-mail ou solicite outro código.');
      }
    } catch { setError('Não foi possível confirmar. Confira sua conexão e tente novamente.'); }
    finally { setBusy(false); }
  }
  async function resend() {
    setBusy(true); setError(''); setMessage('');
    try {
      const { error: err } = await supabase.auth.resend({ type: 'signup', email, options: { emailRedirectTo: window.location.origin + '/?auth_action=signup' } });
      setSeconds(60);
      if (err) { setError('Não foi possível reenviar agora. Aguarde e tente novamente.'); return; }
      setMessage('Se houver confirmação pendente, enviaremos outro código. Confira também o spam.');
    } catch { setError('Confira sua conexão e tente novamente.'); }
    finally { setBusy(false); }
  }
  return <section className="space-y-4" aria-label="Confirmar e-mail por código">
    <h2 className="text-xl font-bold text-slate-900">Confirme seu e-mail</h2>
    <p className="break-words text-sm text-slate-600">Digite o código enviado para <strong>{email}</strong>. Seus 30 dias começam depois da confirmação e do cadastro com CPF ou CNPJ.</p>
    <form onSubmit={verify} className="space-y-4">
      <label className="block text-sm font-semibold">Código de confirmação
        <input autoFocus autoComplete="one-time-code" inputMode="numeric" pattern="[0-9]{6,10}" minLength={6} maxLength={10} required value={code} onChange={event => setCode(event.target.value.replace(/\D/g, ''))} className="mt-2 block min-h-12 w-full rounded-xl border-2 border-slate-300 p-3 text-center text-xl tracking-widest" />
      </label>
      <button disabled={busy} className="min-h-12 w-full rounded-xl bg-orange-700 px-4 py-3 font-bold text-white disabled:opacity-50">{busy ? 'Aguarde…' : 'Confirmar código e continuar'}</button>
    </form>
    {error && <p role="alert" className="text-sm text-red-700">{error}</p>}
    {message && <p role="status" className="text-sm text-emerald-800">{message}</p>}
    <button type="button" disabled={busy || seconds > 0} onClick={() => void resend()} className="min-h-11 w-full font-semibold text-orange-800 underline disabled:opacity-50">{seconds ? `Reenviar código em ${seconds}s` : 'Reenviar código'}</button>
    <button type="button" disabled={busy} onClick={onBack} className="min-h-11 w-full text-sm text-slate-600 underline">Voltar ao acesso</button>
  </section>;
}
