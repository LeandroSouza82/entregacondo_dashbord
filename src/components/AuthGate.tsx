import { useEffect, useRef, useState, type ReactNode, type FormEvent } from 'react';
import type { Session, User } from '@supabase/supabase-js';
import { 
  Building2, 
  User as UserIcon, 
  Mail, 
  Lock, 
  LogIn, 
  UserPlus, 
  AlertCircle,
  Eye,
  EyeOff
} from 'lucide-react';
import { supabase, isSupabaseConfigured } from '../lib/supabase';
import { AuthEmailActions } from './AuthEmailActions';
import { CompanySetupRequiredError, requireCompanyId } from '../lib/company';

type AuthMode = 'login' | 'cadastro';

export function AuthGate({ children, initialMode = 'login' }: { children: ReactNode; initialMode?: AuthMode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [currentUser, setCurrentUser] = useState<User | null>(null);
  const [ready, setReady] = useState(false);
  const [authorizedUserId, setAuthorizedUserId] = useState<string | null>(null);
  const [setupUserId, setSetupUserId] = useState<string | null>(null);
  const [setupName, setSetupName] = useState('');
  const [accessRevision, setAccessRevision] = useState(0);
  const accessRequest = useRef(0);
  const [error, setError] = useState('');
  const [successMessage, setSuccessMessage] = useState(() => window.location.hash.includes('ativado=1') ? 'Acesso ativado! Entre com seu e-mail e senha para começar.' : window.location.hash.includes('senha=definida') ? 'Senha definida! Entre com seu e-mail e a nova senha.' : '');
  const [busy, setBusy] = useState(false);
  const [demoAtivo, setDemoAtivo] = useState<boolean>(() => {
    if (typeof window === 'undefined' || !import.meta.env.DEV) return false;
    const fromQuery = new URLSearchParams(window.location.search).get('demo') === 'true';
    const fromStorage = localStorage.getItem('ec_demo_auth') === 'true';
    if (fromQuery || fromStorage) {
      localStorage.setItem('ec_demo_auth', 'true');
      if (!localStorage.getItem('ec_active_company_id')) {
        localStorage.setItem('ec_active_company_id', '11111111-1111-1111-1111-111111111111');
      }
      return true;
    }
    return false;
  });

  // Controle de visibilidade de senha
  const [showPassword, setShowPassword] = useState(false);
  const [showRegisterPassword, setShowRegisterPassword] = useState(false);

  // Modo da tela: 'login' ou 'cadastro'
  const [modo, setModo] = useState<AuthMode>(initialMode);

  // Campos do formulário
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [nomeCompleto, setNomeCompleto] = useState('');
  const [nomeEmpresa, setNomeEmpresa] = useState('');

  useEffect(() => {
    let active = true;

    supabase.auth.getSession().then(({ data, error }) => {
      if (!active) return;
      if (error) setError(error.message);
      setSession(data.session);
      setCurrentUser(data.session?.user ?? null);
      setReady(true);
    });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, value) => {
      if (active) {
        accessRequest.current++;
        setAuthorizedUserId(null);
        setSession(value);
        setCurrentUser(value?.user ?? null);
        if (!value) {
          localStorage.removeItem('ec_active_company_id');
        }
        setError('');
      }
    });

    return () => {
      active = false;
      subscription.unsubscribe();
    };
  }, []);

  useEffect(() => {
    let active = true;
    const request = ++accessRequest.current;

    async function validarAcesso() {
      setSetupUserId(null);
      setSetupName('');
      if (!session) return;
      setError('');
      setAuthorizedUserId(null);

      try {
        await requireCompanyId();
        if (active && request === accessRequest.current) {
          setAuthorizedUserId(session.user.id);
        }
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : String(err);

        if (active && request === accessRequest.current) {
          if (err instanceof CompanySetupRequiredError) setSetupUserId(session.user.id);
          else setError(msg);
        }
      }
    }

    validarAcesso();

    return () => {
      active = false;
    };
  }, [session, accessRevision]);

  async function criarEmpresa(event: FormEvent) {
    event.preventDefault();
    if (!session || setupUserId !== session.user.id || busy) return;
    const request = accessRequest.current;
    setBusy(true);
    setError('');
    try {
      const name = setupName.trim();
      if (name.length < 2 || name.length > 120) throw new Error('Informe o nome da empresa entre 2 e 120 caracteres.');
      const { data, error: setupError } = await supabase.rpc('iniciar_teste_empresa', { p_nome_empresa: name });
      if (setupError) throw new Error(setupError.message || 'Não foi possível criar sua empresa. Tente novamente.');
      if (!(data as { sucesso?: boolean })?.sucesso) throw new Error('Não foi possível criar sua empresa. Tente novamente.');
      await requireCompanyId();
      if (request === accessRequest.current) {
        setSetupUserId(null);
        setAuthorizedUserId(session.user.id);
      }
    } catch (err) {
      if (request === accessRequest.current) setError(err instanceof Error ? err.message : 'Não foi possível criar sua empresa. Tente novamente.');
    } finally {
      setBusy(false);
    }
  }

  async function login(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError('');
    setSuccessMessage('');

    try {
      if (!email.trim() || !password) {
        throw new Error('Informe o e-mail e a senha para entrar.');
      }

      const { data, error: signInError } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      });

      if (signInError) {
        if (signInError.message.includes('Invalid login credentials')) {
          throw new Error('E-mail ou senha incorretos.');
        }
        throw signInError;
      }

      if (data?.session) {
        setSession(data.session);
        setCurrentUser(data.user);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Não foi possível entrar na conta.');
    } finally {
      setBusy(false);
    }
  }

  async function registrarGestor(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError('');
    setSuccessMessage('');

    try {
      // 1. Validações preliminares no cliente
      if (!nomeCompleto.trim()) {
        throw new Error('Informe seu nome completo.');
      }
      if (nomeEmpresa.trim().length < 2 || nomeEmpresa.trim().length > 120) {
        throw new Error('Informe o nome da empresa entre 2 e 120 caracteres.');
      }
      if (!email.trim()) {
        throw new Error('Informe um e-mail válido.');
      }
      if (password.length < 6) {
        throw new Error('A senha deve ter pelo menos 6 caracteres.');
      }

      // 2. Registro no Supabase Auth com metadados do gestor
      const { data: signUpData, error: signUpError } = await supabase.auth.signUp({
        email: email.trim(),
        password,
        options: {
          emailRedirectTo: window.location.origin + '/?auth_action=signup',
          data: {
            name: nomeCompleto.trim(),
            full_name: nomeCompleto.trim(),
            empresa_nome: nomeEmpresa.trim(),
          },
        },
      });

      if (signUpError) {
        if (signUpError.message.toLowerCase().includes('already registered')) {
          throw new Error('Este e-mail já está cadastrado. Alterne para "Já tenho conta" para fazer login.');
        }
        throw signUpError;
      }

      if (Array.isArray(signUpData.user?.identities) && signUpData.user.identities.length === 0) {
        setModo('login'); setPassword('');
        throw new Error('Este e-mail já possui cadastro. Entre com sua senha ou com Google. Se ainda não tem senha, use “Esqueci ou quero definir minha senha”. Uma nova tentativa de cadastro não altera sua senha.');
      }
      let activeUser = signUpData.user;
      let activeSession = signUpData.session;

      // Se a sessão não foi retornada diretamente no signUp, só tenta login imediato se o e-mail já estiver confirmado
      if (!activeSession && activeUser?.email_confirmed_at) {
        const { data: signInData, error: signInError } = await supabase.auth.signInWithPassword({
          email: email.trim(),
          password,
        });

        if (!signInError && signInData?.session) {
          activeSession = signInData.session;
          activeUser = signInData.user;
        }
      }

      // Access is verified by the effect through the atomic server-side provisioning RPC.
      if (activeSession) {
        setSession(activeSession);
        setCurrentUser(activeUser);
      } else {
        setPassword('');
        setSuccessMessage('Cadastro recebido! Confirme seu e-mail e entre para criar sua empresa e iniciar seus 30 dias grátis. Você poderá contratar o plano pelo painel, sem perder os dias de teste.');
        setModo('login');
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Não foi possível concluir o cadastro.');
    } finally {
      setBusy(false);
    }
  }

  if ((session && authorizedUserId === session.user.id) || demoAtivo) {
    const userEmail = currentUser?.email || session?.user.email || 'gestor.demo@entregacondo.com.br';
    return (
      <>
        <div className="flex justify-end items-center gap-4 p-2 bg-[#E4E5E9] text-sm border-b border-gray-300">
          <span className="font-medium text-slate-700">{userEmail}</span>
          <button
            className="text-slate-500 hover:text-red-700 transition-colors cursor-pointer"
            onClick={() => {
              localStorage.removeItem('ec_demo_auth');
              localStorage.removeItem('ec_active_company_id');
              if (typeof window !== 'undefined' && window.location.search.includes('demo=')) {
                const url = new URL(window.location.href);
                url.searchParams.delete('demo');
                window.history.replaceState({}, '', url.pathname + url.search);
              }
              setDemoAtivo(false);
              setSession(null);
              setAuthorizedUserId(null);
              void supabase.auth.signOut();
            }}
          >
            Sair da conta
          </button>
          {error && <span role="alert" className="text-amber-600 text-xs">{error}</span>}
        </div>
        {children}
      </>
    );
  }

  return (
    <main 
      className="min-h-screen flex items-center justify-center p-4 sm:p-6 bg-cover bg-no-repeat bg-[center_left]"
      style={{
        backgroundImage: 'url(/login-bg.jpg)',
        backgroundColor: '#111E30',
      }}
    >
      <div className="w-full max-w-[420px] bg-white rounded-3xl p-8 sm:p-9 shadow-2xl border border-slate-100/90 space-y-6">
        
        <a href="https://entregacondo.com.br/" className="inline-block text-xs text-slate-500 hover:text-orange-700">← Conhecer o EntregaCondo</a>
        {/* CABEÇALHO */}
        <div className="text-center space-y-2">
          <div className="inline-flex items-center justify-center w-14 h-14 rounded-2xl bg-[#0F1B2D] p-2 shadow-lg mb-1 border border-slate-800">
            <img 
              src="/app-logo.png" 
              alt="EntregaCondo Logo" 
              className="w-full h-full object-contain"
            />
          </div>
          <h1 className="text-2xl font-black tracking-tight text-slate-900">
            EntregaCondo <span className="text-orange-600">·</span> Gestão
          </h1>
          <p className="text-xs sm:text-sm text-slate-500 font-medium">
            {modo === 'login'
              ? 'Acesse o painel operacional da sua administradora'
              : 'Cadastre sua empresa e personalize seus atendimentos'}
          </p>
        </div>

        {!isSupabaseConfigured ? (
          <div className="p-4 bg-red-50 border border-red-200 rounded-xl text-red-700 text-sm">
            Configure as variáveis de conexão do Supabase para continuar.
          </div>
        ) : !ready ? (
          <div className="text-center py-8 text-slate-500 text-sm animate-pulse">
            Carregando EntregaCondo…
          </div>
        ) : session ? (
          <div className="space-y-4">
            {setupUserId === session.user.id ? (
              <form onSubmit={criarEmpresa} className="space-y-4" aria-label="Concluir cadastro da empresa">
                <div className="text-sm text-slate-600 space-y-2">
                  <h2 className="font-bold text-slate-900">Falta apenas cadastrar sua empresa</h2>
                  <p className="break-all">Você entrou com {session.user.email}.</p>
                  <p>Informe o nome da empresa para começar seus 30 dias grátis, sem cartão. Depois, você poderá assinar pelo painel sem perder os dias de teste.</p>
                </div>
                <label htmlFor="setup-company-name" className="block text-sm font-medium text-slate-800">Nome da empresa</label>
                <input id="setup-company-name" value={setupName} onChange={event => setSetupName(event.target.value)} required minLength={2} maxLength={120} autoComplete="organization" disabled={busy} className="w-full border border-slate-300 rounded-lg p-3 text-sm" />
                {error && <p role="alert" className="text-red-700 text-sm">{error}</p>}
                <button type="submit" disabled={busy} className="w-full bg-orange-600 hover:bg-orange-700 text-white rounded-lg p-3 text-sm font-semibold disabled:opacity-50">{busy ? 'Preparando sua empresa…' : 'Criar empresa e iniciar teste grátis'}</button>
              </form>
            ) : <p role={error ? 'alert' : 'status'} className="text-slate-600 text-sm text-center">{error || 'Conferindo acesso à empresa…'}</p>}
            <div className="flex gap-3">
              {setupUserId !== session.user.id && (
                <button
                  type="button"
                  className="flex-1 bg-slate-100 hover:bg-slate-200 text-slate-800 rounded-lg p-2.5 text-sm font-medium transition-colors cursor-pointer"
                  onClick={() => setAccessRevision(value => value + 1)}
                >
                  Atualizar acesso
                </button>
              )}
              <button
                type="button"
                className="flex-1 border border-slate-300 hover:bg-slate-50 text-slate-700 rounded-lg p-2.5 text-sm font-medium transition-colors cursor-pointer"
                onClick={() => void supabase.auth.signOut()}
              >
                Sair e usar outra conta
              </button>
            </div>
          </div>
        ) : (
          <>
            {/* SELETOR DE MODO: JÁ TENHO CONTA | CRIAR NOVA CONTA (PILL STYLE) */}
            <div className="flex items-center justify-center gap-1.5 p-1 bg-slate-100/90 rounded-2xl text-xs font-semibold text-slate-600">
              <button
                type="button"
                onClick={() => {
                  setModo('login');
                  setError('');
                  setSuccessMessage('');
                }}
                className={`flex-1 py-2 px-3 rounded-xl transition-all flex items-center justify-center gap-1.5 cursor-pointer ${
                  modo === 'login'
                    ? 'bg-white text-slate-900 border border-orange-500/80 shadow-xs font-bold'
                    : 'text-slate-500 hover:text-slate-800'
                }`}
              >
                <LogIn className="w-3.5 h-3.5 text-orange-600" />
                <span>Já tenho conta</span>
              </button>
              <button
                type="button"
                onClick={() => {
                  setModo('cadastro');
                  setError('');
                  setSuccessMessage('');
                }}
                className={`flex-1 py-2 px-3 rounded-xl transition-all flex items-center justify-center gap-1.5 cursor-pointer ${
                  modo === 'cadastro'
                    ? 'bg-white text-orange-600 border border-orange-500/80 shadow-xs font-bold'
                    : 'text-slate-500 hover:text-slate-800'
                }`}
              >
                <UserPlus className="w-3.5 h-3.5" />
                <span>Criar empresa · 30 dias grátis</span>
              </button>
            </div>

            {/* MENSAGEM DE SUCESSO */}
            {successMessage && (
              <div className="p-3 bg-emerald-50 border border-emerald-200 rounded-xl text-emerald-800 text-xs font-medium">
                {successMessage}
              </div>
            )}

            {/* MENSAGEM DE ERRO */}
            {error && (
              <div role="alert" className="p-3 bg-red-50 border border-red-200 rounded-xl text-red-700 text-xs font-medium flex items-start gap-2">
                <AlertCircle className="w-4 h-4 text-red-500 shrink-0 mt-0.5" />
                <span>{error}</span>
              </div>
            )}

            {/* FORMULÁRIO DE LOGIN */}
            {modo === 'login' && (
              <form onSubmit={login} className="space-y-4">
                <div>
                  <label className="block text-xs font-bold text-slate-800 mb-1.5">
                    E-mail do Gestor
                  </label>
                  <div className="relative">
                    <Mail className="w-4 h-4 text-slate-400 absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
                    <input
                      className="w-full pl-10 pr-3.5 h-11 bg-white border-2 border-slate-200 hover:border-slate-300 rounded-xl text-sm font-semibold text-slate-900 placeholder:text-slate-400 shadow-2xs focus:outline-none focus:border-orange-500 focus:ring-4 focus:ring-orange-500/15 transition-all"
                      type="email"
                      placeholder="gestor@administradora.com"
                      autoComplete="username"
                      required
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                    />
                  </div>
                </div>

                <div>
                  <label className="block text-xs font-bold text-slate-800 mb-1.5">
                    Palavra-passe / Senha
                  </label>
                  <div className="relative">
                    <Lock className="w-4 h-4 text-slate-400 absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
                    <input
                      className="w-full pl-10 pr-11 h-11 bg-white border-2 border-slate-200 hover:border-slate-300 rounded-xl text-sm font-semibold text-slate-900 placeholder:text-slate-400 shadow-2xs focus:outline-none focus:border-orange-500 focus:ring-4 focus:ring-orange-500/15 transition-all"
                      type={showPassword ? 'text' : 'password'}
                      placeholder="••••••••"
                      autoComplete="current-password"
                      required
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                    />
                    <button
                      type="button"
                      onClick={() => setShowPassword((prev) => !prev)}
                      className="absolute right-3 top-1/2 -translate-y-1/2 p-1.5 text-slate-400 hover:text-slate-700 transition-colors cursor-pointer rounded-lg hover:bg-slate-100 focus:outline-none"
                      title={showPassword ? 'Ocultar senha' : 'Exibir senha'}
                      aria-label={showPassword ? 'Ocultar senha' : 'Exibir senha'}
                    >
                      {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                    </button>
                  </div>
                </div>

                <button
                  type="submit"
                  disabled={busy}
                  className="w-full bg-orange-600 hover:bg-orange-700 text-white text-sm font-bold rounded-xl py-3 shadow-md shadow-orange-600/20 transition-all flex items-center justify-center gap-2 disabled:opacity-50 cursor-pointer"
                >
                  <LogIn className="w-4 h-4" />
                  <span>{busy ? 'Entrando…' : 'Entrar no Dashboard'}</span>
                </button>
              </form>
            )}

            {modo === 'login' && <AuthEmailActions email={email} />}

            {/* FORMULÁRIO DE CADASTRO DE GESTOR */}
            {modo === 'cadastro' && <p className="text-xs leading-relaxed text-slate-600">30 dias grátis, sem cartão. Depois, R$ 149,90/mês por empresa, com até 3 motoristas ativos e 1.000 atendimentos por mês. Você pode assinar durante o teste e manter os dias grátis: a primeira mensalidade fica prevista para o fim do período. Confirme seu e-mail para começar. Sem contratação, não há cobrança automática; após vencer, seus dados ficam disponíveis para consulta e as operações dependem de pagamento confirmado.</p>}
            {modo === 'cadastro' && (
              <form onSubmit={registrarGestor} className="space-y-4">
                <div>
                  <label className="block text-xs font-bold text-slate-800 mb-1.5">
                    Nome Completo <span className="text-red-500">*</span>
                  </label>
                  <div className="relative">
                    <UserIcon className="w-4 h-4 text-slate-400 absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
                    <input
                      className="w-full pl-10 pr-3.5 h-11 bg-white border-2 border-slate-200 hover:border-slate-300 rounded-xl text-sm font-semibold text-slate-900 placeholder:text-slate-400 shadow-2xs focus:outline-none focus:border-orange-500 focus:ring-4 focus:ring-orange-500/15 transition-all"
                      type="text"
                      placeholder="Ex: Carlos Oliveira"
                      required
                      value={nomeCompleto}
                      onChange={(e) => setNomeCompleto(e.target.value)}
                    />
                  </div>
                </div>

                <div>
                  <label htmlFor="company-name" className="block text-xs font-bold text-slate-800 mb-1.5">
                    Nome da sua empresa <span className="text-red-500">*</span>
                  </label>
                  <div className="relative">
                    <Building2 className="w-4 h-4 text-slate-400 absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
                    <input
                      className="w-full pl-10 pr-3.5 h-11 bg-white border-2 border-slate-200 hover:border-slate-300 rounded-xl text-sm font-semibold text-slate-900 placeholder:text-slate-400 shadow-2xs focus:outline-none focus:border-orange-500 focus:ring-4 focus:ring-orange-500/15 transition-all"
                      type="text"
                      id="company-name"
                      placeholder="Ex: Essenza Condomínios"
                      autoComplete="organization"
                      minLength={2}
                      maxLength={120}
                      aria-describedby="company-name-help"
                      required
                      value={nomeEmpresa}
                      onChange={(e) => setNomeEmpresa(e.target.value)}
                    />
                  </div>
                  <p id="company-name-help" className="mt-2 text-xs leading-relaxed text-slate-500">Este nome identifica sua empresa nas mensagens, no acompanhamento e nos comprovantes. Você pode alterá-lo em Configurações.</p>
                </div>

                <div>
                  <label className="block text-xs font-bold text-slate-800 mb-1.5">
                    E-mail de Acesso <span className="text-red-500">*</span>
                  </label>
                  <div className="relative">
                    <Mail className="w-4 h-4 text-slate-400 absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
                    <input
                      className="w-full pl-10 pr-3.5 h-11 bg-white border-2 border-slate-200 hover:border-slate-300 rounded-xl text-sm font-semibold text-slate-900 placeholder:text-slate-400 shadow-2xs focus:outline-none focus:border-orange-500 focus:ring-4 focus:ring-orange-500/15 transition-all"
                      type="email"
                      placeholder="gestor@suaempresa.com"
                      autoComplete="username"
                      required
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                    />
                  </div>
                </div>

                <div>
                  <label className="block text-xs font-bold text-slate-800 mb-1.5">
                    Palavra-passe / Senha (mínimo 6 caracteres) <span className="text-red-500">*</span>
                  </label>
                  <div className="relative">
                    <Lock className="w-4 h-4 text-slate-400 absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
                    <input
                      className="w-full pl-10 pr-11 h-11 bg-white border-2 border-slate-200 hover:border-slate-300 rounded-xl text-sm font-semibold text-slate-900 placeholder:text-slate-400 shadow-2xs focus:outline-none focus:border-orange-500 focus:ring-4 focus:ring-orange-500/15 transition-all"
                      type={showRegisterPassword ? 'text' : 'password'}
                      placeholder="••••••••"
                      autoComplete="new-password"
                      required
                      minLength={6}
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                    />
                    <button
                      type="button"
                      onClick={() => setShowRegisterPassword((prev) => !prev)}
                      className="absolute right-3 top-1/2 -translate-y-1/2 p-1.5 text-slate-400 hover:text-slate-700 transition-colors cursor-pointer rounded-lg hover:bg-slate-100 focus:outline-none"
                      title={showRegisterPassword ? 'Ocultar senha' : 'Exibir senha'}
                      aria-label={showRegisterPassword ? 'Ocultar senha' : 'Exibir senha'}
                    >
                      {showRegisterPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                    </button>
                  </div>
                </div>

                <button
                  type="submit"
                  disabled={busy}
                  className="w-full bg-orange-600 hover:bg-orange-700 text-white text-sm font-bold rounded-xl py-3 shadow-md shadow-orange-600/20 transition-all flex items-center justify-center gap-2 disabled:opacity-50 cursor-pointer"
                >
                  <UserPlus className="w-4 h-4" />
                  <span>{busy ? 'Preparando cadastro…' : 'Criar conta e testar grátis'}</span>
                </button>
              </form>
            )}

          </>
        )}
        <p className="text-center text-xs text-slate-500"><a href="https://entregacondo.com.br/privacidade" className="underline underline-offset-2">Privacidade</a><span aria-hidden="true"> · </span><a href="https://entregacondo.com.br/termos" className="underline underline-offset-2">Termos de uso</a></p>
      </div>
    </main>
  );
}
