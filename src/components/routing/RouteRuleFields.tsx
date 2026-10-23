import {useEffect, useId, useRef, useState} from 'react';
import type {PontoParada} from '../../types/logistics';
import {emptyDraftRule, validateDraftRule, type DraftRule} from '../../features/routes/services/routeRules';

interface Props { value: DraftRule; onChange: (value: DraftRule) => void; type: string; stops: PontoParada[]; exclude?: string }
const inputClass='mt-1 w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm';
export function RouteRuleFields({value,onChange,type,stops,exclude}: Props) {
  const id=useId();
  const collections=stops.filter(s=>s.tipoTarefa==='coleta' && s.id!==exclude);
  return <div className="space-y-3 text-sm">
    <p className="text-xs text-slate-500">Preencha somente quando necessário. Horários de Brasília; a previsão considera deslocamento, atendimento e espera.</p>
    <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
      <label htmlFor={`${id}-date`}>Dia do atendimento<input id={`${id}-date`} name="janela_data_ec" type="date" className={inputClass} value={value.date} onChange={e=>onChange({...value,date:e.target.value})}/></label>
      <label htmlFor={`${id}-start`}>A partir de<input id={`${id}-start`} name="janela_inicio_ec" type="time" className={inputClass} value={value.start} onChange={e=>onChange({...value,start:e.target.value})}/></label>
      <label htmlFor={`${id}-end`}>Até<input id={`${id}-end`} name="janela_fim_ec" type="time" className={inputClass} value={value.end} onChange={e=>onChange({...value,end:e.target.value})}/></label>
    </div>
    {(value.date || value.start || value.end) && <label className="block" htmlFor={`${id}-minutes`}>Atendimento previsto no local (minutos)
      <input id={`${id}-minutes`} type="number" min="0" max="240" step="1" className={inputClass} value={value.minutes} onChange={e=>onChange({...value,minutes:Number(e.target.value)})}/>
      <span className="text-xs text-slate-500">O atendimento previsto deve caber no intervalo escolhido. A estimativa não garante pontualidade.</span>
    </label>}
    {type==='entrega' && <label className="block" htmlFor={`${id}-collection`}>Esta entrega depende de uma coleta?
      <select id={`${id}-collection`} name="coleta_origem_ec" className={inputClass} value={value.collection} onChange={e=>onChange({...value,collection:e.target.value})}>
        <option value="">Não depende de coleta</option>
        {collections.map(s=><option key={s.id} value={s.id}>{s.nomeLocal || s.destinatario} · {s.codigoRastreio}</option>)}
      </select>
      <span className="text-xs text-slate-500">Adicione a coleta a este rascunho primeiro. A entrega será liberada após a coleta ser concluída e sincronizada.</span>
    </label>}
    {(value.date || value.start || value.end || value.collection) && <button type="button" className="text-xs font-semibold text-slate-600 underline" onClick={()=>onChange(emptyDraftRule(value.minutes))}>Limpar condições opcionais</button>}
  </div>;
}

export function RouteRuleEditor({stop,stops,onSave,onClose}: {stop:PontoParada;stops:PontoParada[];onSave:(value:DraftRule)=>void;onClose:()=>void}) {
  const dialog=useRef<HTMLDialogElement>(null);
  const [value,setValue]=useState<DraftRule>(()=>({date:stop.janelaData ?? '',start:stop.janelaInicio ?? '',end:stop.janelaFim ?? '',collection:stop.coletaOrigemId ?? '',minutes:stop.tempoMedioAtendimentoMinutos}));
  const [error,setError]=useState('');
  useEffect(()=>{const element=dialog.current;element?.showModal();return ()=>element?.close();},[]);
  return <dialog ref={dialog} onCancel={onClose} aria-labelledby="rule-editor-title" className="w-[min(94vw,620px)] max-h-[85vh] rounded-2xl p-6 text-slate-800 shadow-xl backdrop:bg-black/40">
    <h2 id="rule-editor-title" className="mb-1 text-lg font-bold">Condições do pedido</h2>
    <p className="mb-4 text-sm text-slate-600">{stop.destinatario}</p>
    <form onSubmit={event=>{event.preventDefault();try{validateDraftRule(value,stop.tipoTarefa ?? 'entrega',stops);onSave(value);}catch(error){setError((error as Error).message);}}}>
      <RouteRuleFields value={value} onChange={setValue} type={stop.tipoTarefa ?? 'entrega'} stops={stops} exclude={stop.id}/>
      {error && <p role="alert" className="mt-3 text-sm text-red-700">{error}</p>}
      <div className="mt-5 flex justify-end gap-3"><button type="button" onClick={onClose} className="rounded-lg border px-4 py-2">Voltar</button><button type="submit" className="rounded-lg bg-blue-700 px-4 py-2 text-white">Salvar condições</button></div>
    </form>
  </dialog>;
}
