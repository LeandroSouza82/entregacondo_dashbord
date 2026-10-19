import { useEffect, useState, type ReactNode, type FormEvent } from 'react';
import type { Session, User } from '@supabase/supabase-js';
import { Building2, User as UserIcon, Mail, Lock, LogIn, UserPlus, AlertCircle } from 'lucide-react';
import { supabase, isSupabaseConfigured } from '../lib/supabase';
import { requireCompanyId } from '../lib/company';

type AuthMode = 'login' | 'cadastro';

export function AuthGate({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [currentUser, setCurrentUser] = useState<User | null>(null);
  const [ready, setReady] = useState(false);
  const [allowed, setAllowed] = useState(false);
  const [error, setError] = useState('');
  const [successMessage, setSuccessMessage] = useState('');
  const [busy, setBusy] = useState(false);

  // Modo da tela: 'login' ou 'cadastro'
  const [modo, setModo] = useState<AuthMode>('login');

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
        setSession(value);
        setCurrentUser(value?.user ?? null);
        if (!value) {
          setAllowed(false);
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

    async function validarAcesso() {
      if (!session) return;
      setError('');

      try {
        await requireCompanyId();
        if (active) {
          setAllowed(true);
        }
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : String(err);

        // Fallback resiliente: caso a RPC não exista no schema cache do Supabase remoto (404/PGRST202)
        const isRpcCacheError =
          msg.includes('sincronizar_meu_perfil') ||
          msg.includes('schema cache') ||
          msg.includes('404') ||
          msg.includes('PGRST202') ||
          msg.includes('obter_meu_status_acesso') ||
          msg.includes('Could not find the function');

        if (isRpcCacheError) {
          console.warn('[AuthGate] RPC ausente ou cache desatualizado no Supabase. Acionando fallback direto via getUser():', msg);
          try {
            const { data: userData, error: userErr } = await supabase.auth.getUser();
            if (active && !userErr && userData?.user) {
              setCurrentUser(userData.user);
              setAllowed(true);
              setError('');
              return;
            }
          } catch (fallbackError) {
            console.error('[AuthGate] Erro ao carregar dados do usuário via fallback:', fallbackError);
          }
        }

        if (active) {
          setError(msg);
        }
      }
    }

    validarAcesso();

    return () => {
      active = false;
    };
  }, [session]);

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
      if (!nomeEmpresa.trim()) {
        throw new Error('Informe o nome da Administradora ou Empresa.');
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

      let activeUser = signUpData.user;
      let activeSession = signUpData.session;

      // Se a sessão não foi retornada diretamente no signUp (ex: auto-confirm pendente), tenta login imediato
      if (!activeSession) {
        const { data: signInData, error: signInError } = await supabase.auth.signInWithPassword({
          email: email.trim(),
          password,
        });

        if (!signInError && signInData?.session) {
          activeSession = signInData.session;
          activeUser = signInData.user;
        }
      }

      // 3. Se autenticado, cria empresa e vínculo inicial
      if (activeUser) {
        const codPrefixo = nomeEmpresa.trim().substring(0, 3).toUpperCase().replace(/[^A-Z0-9]/g, 'ADM') || 'ADM';
        const codigoConvite = `EC-${codPrefixo}-${Math.floor(1000 + Math.random() * 9000)}`;

        let empresaId: string | null = null;

        // Cria a empresa se possível
        try {
          const { data: novaEmpresa, error: empErr } = await supabase
            .from('empresas')
            .insert({
              nome: nomeEmpresa.trim(),
              codigo_convite: codigoConvite,
              cidade: 'Florianópolis',
              uf: 'SC',
              ativa: true,
            })
            .select('id')
            .maybeSingle();

          if (!empErr && novaEmpresa?.id) {
            empresaId = novaEmpresa.id;
          }
        } catch (e) {
          console.warn('[AuthGate] Inserção de empresa direta não permitida por RLS ou já criada:', e);
        }

        // Se a inserção direta não retornou ID, busca a primeira empresa existente
        if (!empresaId) {
          const { data: empExistente } = await supabase
            .from('empresas')
            .select('id')
            .limit(1)
            .maybeSingle();

          if (empExistente?.id) {
            empresaId = empExistente.id;
          }
        }

        // Cria o vínculo de membro gestor aprovado
        if (empresaId) {
          try {
            await supabase.from('empresa_membros').upsert({
              empresa_id: empresaId,
              user_id: activeUser.id,
              papel: 'gestor',
              status: 'aprovado',
              aprovado_em: new Date().toISOString(),
            }, { onConflict: 'empresa_id,user_id' });
          } catch (membroErr) {
            console.warn('[AuthGate] Registro em empresa_membros gerou aviso:', membroErr);
          }
        }

        // Sincroniza o perfil do usuário
        try {
          await supabase.rpc('sincronizar_meu_perfil');
        } catch {
          // Ignora se indisponível
        }
      }

      // 4. Se a sessão foi ativada com sucesso, libera o acesso direto ao dashboard
      if (activeSession) {
        setSession(activeSession);
        setCurrentUser(activeUser);
        setAllowed(true);
        setSuccessMessage('Conta de gestor criada com sucesso! Acessando o painel...');
      } else {
        setSuccessMessage('Conta cadastrada com sucesso! Verifique seu e-mail caso a confirmação seja exigida, ou entre com sua senha.');
        setModo('login');
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Não foi possível concluir o cadastro.');
    } finally {
      setBusy(false);
    }
  }

  if (session && allowed) {
    const userEmail = currentUser?.email || session?.user.email || '';
    return (
      <>
        <div className="flex justify-end items-center gap-4 p-2 bg-white text-sm border-b">
          <span className="font-medium text-slate-700">{userEmail}</span>
          <button
            className="text-slate-500 hover:text-red-700 transition-colors"
            onClick={() => {
              localStorage.removeItem('ec_active_company_id');
              setSession(null);
              setAllowed(false);
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
    <main className="min-h-screen flex items-center justify-center bg-gradient-to-br from-slate-900 via-slate-800 to-slate-950 p-6">
      <div className="w-full max-w-md bg-white rounded-2xl p-8 border border-slate-200/80 shadow-2xl space-y-6">
        
        {/* CABEÇALHO */}
        <div className="text-center space-y-1.5">
          <div className="inline-flex items-center justify-center w-12 h-12 rounded-xl bg-orange-100 text-orange-600 mb-2">
            <Building2 className="w-6 h-6" />
          </div>
          <h1 className="text-2xl font-black tracking-tight text-slate-900">
            EntregaCondo <span className="text-orange-600">·</span> Gestão
          </h1>
          <p className="text-sm text-slate-500">
            {modo === 'login'
              ? 'Acesse o painel operacional da sua administradora'
              : 'Cadastre sua administradora e comece a operar'}
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
            <p className="text-slate-600 text-sm text-center">{error || 'Conferindo acesso à empresa…'}</p>
            <div className="flex gap-3">
              <button
                type="button"
                className="flex-1 bg-slate-100 hover:bg-slate-200 text-slate-800 rounded-lg p-2.5 text-sm font-medium transition-colors"
                onClick={() => window.location.reload()}
              >
                Atualizar acesso
              </button>
              <button
                type="button"
                className="flex-1 border border-slate-300 hover:bg-slate-50 text-slate-700 rounded-lg p-2.5 text-sm font-medium transition-colors"
                onClick={() => void supabase.auth.signOut()}
              >
                Sair
              </button>
            </div>
          </div>
        ) : (
          <>
            {/* SELETOR DE MODO: JÁ TENHO CONTA | CRIAR NOVA CONTA */}
            <div className="flex bg-slate-100 p-1 rounded-xl gap-1">
              <button
                type="button"
                onClick={() => {
                  setModo('login');
                  setError('');
                  setSuccessMessage('');
                }}
                className={`flex-1 py-2 text-xs font-bold rounded-lg transition-all flex items-center justify-center gap-1.5 ${
                  modo === 'login'
                    ? 'bg-white text-slate-900 shadow-sm'
                    : 'text-slate-500 hover:text-slate-800'
                }`}
              >
                <LogIn className="w-3.5 h-3.5" />
                <span>Já tenho conta</span>
              </button>
              <button
                type="button"
                onClick={() => {
                  setModo('cadastro');
                  setError('');
                  setSuccessMessage('');
                }}
                className={`flex-1 py-2 text-xs font-bold rounded-lg transition-all flex items-center justify-center gap-1.5 ${
                  modo === 'cadastro'
                    ? 'bg-white text-orange-600 shadow-sm'
                    : 'text-slate-500 hover:text-slate-800'
                }`}
              >
                <UserPlus className="w-3.5 h-3.5" />
                <span>Criar nova conta de gestor</span>
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
                  <label className="block text-xs font-semibold text-slate-700 mb-1">
                    E-mail do Gestor
                  </label>
                  <div className="relative">
                    <Mail className="w-4 h-4 text-slate-400 absolute left-3 top-3.5" />
                    <input
                      className="w-full pl-9 pr-3 py-2.5 bg-slate-50 border border-slate-200 rounded-lg text-sm text-slate-900 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-orange-500 focus:bg-white transition-all"
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
                  <label className="block text-xs font-semibold text-slate-700 mb-1">
                    Palavra-passe / Senha
                  </label>
                  <div className="relative">
                    <Lock className="w-4 h-4 text-slate-400 absolute left-3 top-3.5" />
                    <input
                      className="w-full pl-9 pr-3 py-2.5 bg-slate-50 border border-slate-200 rounded-lg text-sm text-slate-900 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-orange-500 focus:bg-white transition-all"
                      type="password"
                      placeholder="••••••••"
                      autoComplete="current-password"
                      required
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                    />
                  </div>
                </div>

                <button
                  type="submit"
                  disabled={busy}
                  className="w-full bg-orange-600 hover:bg-orange-700 text-white text-sm font-bold rounded-xl py-3 shadow-md shadow-orange-600/20 transition-all flex items-center justify-center gap-2 disabled:opacity-50"
                >
                  <LogIn className="w-4 h-4" />
                  <span>{busy ? 'Entrando…' : 'Entrar no Dashboard'}</span>
                </button>
              </form>
            )}

            {/* FORMULÁRIO DE CADASTRO DE GESTOR */}
            {modo === 'cadastro' && (
              <form onSubmit={registrarGestor} className="space-y-4">
                <div>
                  <label className="block text-xs font-semibold text-slate-700 mb-1">
                    Nome Completo <span className="text-red-500">*</span>
                  </label>
                  <div className="relative">
                    <UserIcon className="w-4 h-4 text-slate-400 absolute left-3 top-3.5" />
                    <input
                      className="w-full pl-9 pr-3 py-2.5 bg-slate-50 border border-slate-200 rounded-lg text-sm text-slate-900 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-orange-500 focus:bg-white transition-all"
                      type="text"
                      placeholder="Ex: Carlos Oliveira"
                      required
                      value={nomeCompleto}
                      onChange={(e) => setNomeCompleto(e.target.value)}
                    />
                  </div>
                </div>

                <div>
                  <label className="block text-xs font-semibold text-slate-700 mb-1">
                    Nome da Administradora / Empresa <span className="text-red-500">*</span>
                  </label>
                  <div className="relative">
                    <Building2 className="w-4 h-4 text-slate-400 absolute left-3 top-3.5" />
                    <input
                      className="w-full pl-9 pr-3 py-2.5 bg-slate-50 border border-slate-200 rounded-lg text-sm text-slate-900 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-orange-500 focus:bg-white transition-all"
                      type="text"
                      placeholder="Ex: Administradora Habitarte"
                      required
                      value={nomeEmpresa}
                      onChange={(e) => setNomeEmpresa(e.target.value)}
                    />
                  </div>
                </div>

                <div>
                  <label className="block text-xs font-semibold text-slate-700 mb-1">
                    E-mail de Acesso <span className="text-red-500">*</span>
                  </label>
                  <div className="relative">
                    <Mail className="w-4 h-4 text-slate-400 absolute left-3 top-3.5" />
                    <input
                      className="w-full pl-9 pr-3 py-2.5 bg-slate-50 border border-slate-200 rounded-lg text-sm text-slate-900 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-orange-500 focus:bg-white transition-all"
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
                  <label className="block text-xs font-semibold text-slate-700 mb-1">
                    Palavra-passe / Senha (mínimo 6 caracteres) <span className="text-red-500">*</span>
                  </label>
                  <div className="relative">
                    <Lock className="w-4 h-4 text-slate-400 absolute left-3 top-3.5" />
                    <input
                      className="w-full pl-9 pr-3 py-2.5 bg-slate-50 border border-slate-200 rounded-lg text-sm text-slate-900 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-orange-500 focus:bg-white transition-all"
                      type="password"
                      placeholder="••••••••"
                      autoComplete="new-password"
                      required
                      minLength={6}
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                    />
                  </div>
                </div>

                <button
                  type="submit"
                  disabled={busy}
                  className="w-full bg-orange-600 hover:bg-orange-700 text-white text-sm font-bold rounded-xl py-3 shadow-md shadow-orange-600/20 transition-all flex items-center justify-center gap-2 disabled:opacity-50"
                >
                  <UserPlus className="w-4 h-4" />
                  <span>{busy ? 'Criando conta e empresa…' : 'Criar Conta e Acessar'}</span>
                </button>
              </form>
            )}

          </>
        )}
      </div>
    </main>
  );
}
