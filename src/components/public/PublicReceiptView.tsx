import {receiptShareTokenValid,readSharedReceipt,type SharedReceipt} from '../../features/receipts/receiptSharing';
import { useEffect, useState } from 'react';
import { supabase, supabaseUrl } from '../../lib/supabase';
import { receiptLabel } from '../dashboard/receiptLabels';
import { 
  CheckCircle2, 
  Clock, 
  Calendar, 
  UserCheck, 
  FileText, 
  MapPin, 
  Loader2, 
  AlertCircle,
  Maximize2,
  X
} from 'lucide-react';

export function PublicReceiptView({token}: {token:string}) {
  return <ReceiptSession key={token} token={token}/>;
}

function ReceiptSession({token}: {token:string}) {
  const [state,setState]=useState<{receipt:SharedReceipt|null;loading:boolean;error:string}>(()=>({receipt:null,loading:receiptShareTokenValid(token),error:receiptShareTokenValid(token)?'':'Link antigo ou inválido. Solicite um novo comprovante à empresa.'}));
  const [zoomImage,setZoomImage]=useState<string|null>(null);
  const [mediaError,setMediaError]=useState(false);
  const {receipt,loading,error}=state;
  useEffect(()=>{
    let active=true, inFlight=false;
    let poll:ReturnType<typeof setTimeout>|undefined, expiry:ReturnType<typeof setTimeout>|undefined;
    const controller=new AbortController();
    const robots=document.createElement('meta');robots.name='robots';robots.content='noindex, nofollow, noarchive';document.head.append(robots);
    const referrer=document.createElement('meta');referrer.name='referrer';referrer.content='no-referrer';document.head.append(referrer);
    function hide(message:string) {setState({receipt:null,loading:false,error:message});setZoomImage(null);}
    async function refresh() {
      if (!active || inFlight) return;
      inFlight=true;
      clearTimeout(poll);
      try {
        const request=new AbortController();
        const abort=()=>request.abort();
        controller.signal.addEventListener('abort',abort,{once:true});
        const timeout=setTimeout(abort,10000);
        let result;
        try {result=await supabase.rpc('obter_comprovante_compartilhado',{p_token:token}).abortSignal(request.signal);}
        finally {clearTimeout(timeout);controller.signal.removeEventListener('abort',abort);}
        if (!active) return;
        if (result.error) throw result.error;
        const next=readSharedReceipt(result.data,supabaseUrl);
        if (!next) {hide('Link inválido, expirado ou revogado. Solicite um novo comprovante à empresa.');return;}
        setState({receipt:next,loading:false,error:''});
        clearTimeout(expiry);
        expiry=setTimeout(()=>{if(active)hide('Este link expirou. Solicite um novo comprovante à empresa.');},Math.max(0,Date.parse(next.expira_em)-Date.parse(next.servidor_em)));
      } catch {
        if (active) hide('Não foi possível atualizar este comprovante. Confira a conexão; tentaremos novamente.');
      } finally {inFlight=false;}
      if (active) poll=setTimeout(refresh,15000);
    }
    function onVisible(){if(document.visibilityState==='visible'){hide('');void refresh();}}
    if (receiptShareTokenValid(token)) {void refresh();document.addEventListener('visibilitychange',onVisible);}
    return ()=>{active=false;controller.abort();clearTimeout(poll);clearTimeout(expiry);document.removeEventListener('visibilitychange',onVisible);robots.remove();referrer.remove();};
  },[token]);

  // Formatação de data e tempo
  const dataConclusao = receipt ? new Date(receipt.concluida_em) : null;
  const dataFormatada = dataConclusao
    ? dataConclusao.toLocaleDateString('pt-BR', { day: '2-digit', month: 'long', year: 'numeric' })
    : '';
  const horaFormatada = dataConclusao
    ? dataConclusao.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })
    : '';

  const tempoFormatado = receipt
    ? `${Math.floor(receipt.duracao_segundos / 60)} min ${receipt.duracao_segundos % 60}s`
    : '';

  return (
    <div className="min-h-screen bg-[#F4F5F8] text-[#0F1B2D] flex flex-col justify-between p-4 sm:p-6 md:p-8 font-sans antialiased">
      {/* Topo: Logo & Identidade */}
      <header className="max-w-md w-full mx-auto flex flex-wrap gap-3 items-center justify-between pb-6 border-b border-slate-200/80">
        <div className="min-w-0 flex-1 p-1">
          <p className="text-xs text-slate-500">Comprovante digital</p>
          <p data-company-identity className="mt-1 break-words text-xl font-bold">{receipt && !error ? receipt.empresa_nome : 'Empresa responsável'}</p>
        </div>
        {receipt && !error && <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11px] font-extrabold bg-emerald-50 text-emerald-800 border border-emerald-200 shadow-2xs">
          <CheckCircle2 className="w-3.5 h-3.5 text-emerald-600" />
          Registrado
        </span>}
      </header>

      {/* Conteúdo Central */}
      <main className="max-w-md w-full mx-auto my-6 flex-1">
        {loading && (
          <div className="bg-white border border-gray-300 rounded-2xl p-8 text-center shadow-card space-y-3">
            <Loader2 className="w-8 h-8 animate-spin text-terracotta-600 mx-auto" />
            <p className="text-sm font-semibold text-slate-700">Carregando dados do comprovante...</p>
            <p className="text-xs text-slate-400">Verificando autenticidade com o servidor</p>
          </div>
        )}

        {error && !loading && (
          <div role="alert" className="bg-white border border-gray-300 rounded-2xl p-6 text-center shadow-card space-y-3">
            <div className="w-12 h-12 rounded-full bg-red-50 text-red-600 flex items-center justify-center mx-auto">
              <AlertCircle className="w-6 h-6" />
            </div>
            <h2 className="text-base font-extrabold text-[#0F1B2D]">Comprovante Indisponível</h2>
            <p className="text-xs text-slate-500 leading-relaxed max-w-xs mx-auto">{error}</p>
            <div className="pt-2">
              <a
                href="/"
                className="inline-block text-xs font-bold text-terracotta-600 hover:text-terracotta-700 underline"
              >
                Voltar à página inicial
              </a>
            </div>
          </div>
        )}

        {receipt && !loading && (
          <div className="bg-white border border-gray-300 rounded-2xl shadow-card overflow-hidden">
            <p className="bg-slate-100 p-3 text-center text-sm font-semibold">{receipt.empresa_nome}</p>
            {/* Header do Card */}
            <div className="bg-[#0F1B2D] text-white p-5 text-center">
              <span className="text-[10px] uppercase font-bold tracking-widest text-terracotta-400">
                Comprovante do atendimento
              </span>
              <h1 className="text-xl font-black mt-1 tracking-tight">
                {receipt.destinatario_nome}
              </h1>
              {receipt.endereco && (
                <div className="text-xs text-slate-300 flex items-center justify-center gap-1.5 mt-1.5 px-4 font-medium">
                  <MapPin className="w-3.5 h-3.5 text-terracotta-400 flex-shrink-0" />
                  <span className="truncate">{receipt.endereco}</span>
                </div>
              )}
            </div>

            {/* Grid de Informações Detalhadas */}
            <div className="p-5 space-y-4 text-xs divide-y divide-slate-100">
              <div className="flex items-center justify-between pt-1">
                <span className="text-slate-500 flex items-center gap-2 font-medium">
                  <UserCheck className="w-4 h-4 text-slate-400" />
                  Recebedor
                </span>
                <span className="font-bold text-[#0F1B2D] text-right">
                  {receiptLabel(receipt.recebedor_tipo)}
                  {receipt.recebedor_nome ? ` · ${receipt.recebedor_nome}` : ''}
                </span>
              </div>

              <div className="flex items-center justify-between pt-3">
                <span className="text-slate-500 flex items-center gap-2 font-medium">
                  <Calendar className="w-4 h-4 text-slate-400" />
                  Data do atendimento
                </span>
                <span className="font-bold text-[#0F1B2D]">{dataFormatada}</span>
              </div>

              <div className="flex items-center justify-between pt-3">
                <span className="text-slate-500 flex items-center gap-2 font-medium">
                  <Clock className="w-4 h-4 text-slate-400" />
                  Horário de Conclusão
                </span>
                <span className="font-bold text-[#0F1B2D]">{horaFormatada}</span>
              </div>

              <div className="flex items-center justify-between pt-3">
                <span className="text-slate-500 flex items-center gap-2 font-medium">
                  <Clock className="w-4 h-4 text-slate-400" />
                  Tempo de Atendimento
                </span>
                <span className="font-bold text-[#0F1B2D]">{tempoFormatado}</span>
              </div>

              {receipt.observacao && (
                <div className="pt-3">
                  <span className="text-slate-500 flex items-center gap-2 font-medium mb-1">
                    <FileText className="w-4 h-4 text-slate-400" />
                    Observações
                  </span>
                  <p className="p-2.5 rounded-lg bg-slate-50 border border-slate-100 text-slate-700 italic">
                    "{receipt.observacao}"
                  </p>
                </div>
              )}
            </div>

            {/* Seção da Imagem de Evidência / Assinatura */}
            <div className="p-5 bg-slate-50/70 border-t border-slate-200">
              <div className="flex items-center justify-between mb-2.5">
                <span className="text-xs font-bold text-slate-700 uppercase tracking-wider">
                  Evidência / Assinatura Digital
                </span>
                {!mediaError && (receipt.foto_url || receipt.assinatura_url) && (
                  <button
                    type="button"
                    onClick={() => setZoomImage((receipt.foto_url || receipt.assinatura_url) || null)}
                    className="inline-flex items-center gap-1 text-[11px] font-bold text-terracotta-600 hover:text-terracotta-700"
                  >
                    <Maximize2 className="w-3 h-3" />
                    Ampliar
                  </button>
                )}
              </div>

              {mediaError ? <p role="alert" className="text-sm text-amber-800">Imagem indisponível. Solicite um novo link à empresa.</p> : (receipt.foto_url || receipt.assinatura_url) ? (
                <div 
                  onClick={() => setZoomImage((receipt.foto_url || receipt.assinatura_url) || null)}
                  className="relative rounded-xl overflow-hidden border border-gray-300 bg-white cursor-pointer group shadow-2xs hover:border-terracotta-500/50 transition-all"
                >
                  <img
                    src={(receipt.foto_url || receipt.assinatura_url) ?? undefined}
                    referrerPolicy="no-referrer"
                    onError={()=>{setMediaError(true);setZoomImage(null);}}
                    alt="Evidência fotográfica ou assinatura digital"
                    className="w-full max-h-60 object-contain p-2 mx-auto"
                  />
                  <div className="absolute inset-0 bg-black/0 group-hover:bg-black/10 transition-colors flex items-center justify-center pointer-events-none">
                    <span className="opacity-0 group-hover:opacity-100 bg-white/90 text-slate-700 text-[10px] font-bold px-2 py-1 rounded shadow transition-opacity">
                      Toque para ampliar
                    </span>
                  </div>
                </div>
              ) : (
                <div className="p-4 rounded-xl border border-dashed border-slate-300 bg-white text-center text-xs text-slate-400">
                  Sem evidência fotográfica anexada
                </div>
              )}
            </div>

            {/* Rodapé de Autenticidade */}
            <div className="p-3 bg-slate-100/90 border-t border-slate-200 text-center text-[10px] text-slate-500 font-mono">
              Link temporário · válido até {new Date(receipt.expira_em).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'})}
            </div>
          </div>
        )}
      </main>

      {/* Modal de Zoom da Evidência */}
      {zoomImage && (
        <div
          role="dialog"
          aria-modal="true"
          onClick={() => setZoomImage(null)}
          className="fixed inset-0 z-50 bg-black/80 flex items-center justify-center p-4 backdrop-blur-xs animate-fadeIn"
        >
          <div className="relative max-w-xl w-full bg-white rounded-2xl p-3 shadow-2xl" onClick={(e) => e.stopPropagation()}>
            <button
              type="button"
              onClick={() => setZoomImage(null)}
              aria-label="Fechar"
              className="absolute top-2 right-2 p-1.5 rounded-full bg-slate-100 hover:bg-slate-200 text-slate-700 transition-colors"
            >
              <X className="w-4 h-4" />
            </button>
            <img
              src={zoomImage}
              referrerPolicy="no-referrer"
              alt="Evidência em alta resolução"
              className="w-full max-h-[80vh] object-contain rounded-xl mt-6"
            />
          </div>
        </div>
      )}

      {/* Footer Geral */}
      <footer className="max-w-md w-full mx-auto text-center pt-4 border-t border-slate-200/80 text-[11px] text-slate-400">
        <p>Comprovante gerado digitalmente pela plataforma <strong>EntregaCondo</strong>.</p>
        <p className="mt-0.5">Todos os direitos reservados • entregacondo.com.br</p>
      </footer>
    </div>
  );
};
