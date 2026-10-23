import type { PontoParada } from '../../../types/logistics';
import type { RouteRule } from './routeSchedule';

export const ROUTE_TIME_ZONE = 'America/Sao_Paulo';
export interface DraftRule { date: string; start: string; end: string; collection: string; minutes: number }
export const emptyDraftRule = (minutes = 11): DraftRule => ({date:'',start:'',end:'',collection:'',minutes});
const formatter = new Intl.DateTimeFormat('en-CA',{timeZone:ROUTE_TIME_ZONE,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'});
export function planningNow(): string {
  const p=Object.fromEntries(formatter.formatToParts(new Date()).map(p=>[p.type,p.value]));
  return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}`;
}
export function ruleDateTime(date: string, time: string): number {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !/^([01]\d|2[0-3]):[0-5]\d$/.test(time)) throw new Error('Informe data e horários válidos.');
  const [y,m,d] = date.split('-').map(Number), [h,min] = time.split(':').map(Number);
  const target=Date.UTC(y,m-1,d,h,min); let guess=target;
  for(let i=0;i<3;i++) {
    const p=Object.fromEntries(formatter.formatToParts(new Date(guess)).map(p=>[p.type,p.value]));
    const observed=Date.UTC(+p.year,+p.month-1,+p.day,+p.hour,+p.minute,+p.second);
    guess+=target-observed;
  }
  const p=Object.fromEntries(formatter.formatToParts(new Date(guess)).map(p=>[p.type,p.value]));
  if (`${p.year}-${p.month}-${p.day}`!==date || `${p.hour}:${p.minute}`!==time) throw new Error('Data ou horário inválido no fuso de Brasília.');
  return guess;
}
export function validateDraftRule(rule: DraftRule, type: string, stops: PontoParada[]): void {
  if (rule.start || rule.end || rule.date) {
    if (!rule.date || !rule.start || !rule.end) throw new Error('Preencha a data, o horário inicial e o final, ou deixe os três vazios.');
    if (ruleDateTime(rule.date,rule.start)>=ruleDateTime(rule.date,rule.end)) throw new Error('O horário final deve ser depois do inicial, no mesmo dia.');
    if ((ruleDateTime(rule.date,rule.end)-ruleDateTime(rule.date,rule.start))/60000 < rule.minutes) throw new Error('O tempo previsto de atendimento não cabe na faixa de horário.');
  }
  if (!Number.isInteger(rule.minutes) || rule.minutes<0 || rule.minutes>240) throw new Error('Informe um atendimento previsto entre 0 e 240 minutos.');
  if (rule.collection && (type!=='entrega' || !stops.some(s=>s.id===rule.collection && s.tipoTarefa==='coleta'))) throw new Error('Vincule a entrega a uma coleta presente neste rascunho.');
}
export function hasRouteRules(stops: PontoParada[]): boolean { return stops.some(s=>s.janelaData || s.coletaOrigemId); }
export function draftToRule(stop: PontoParada): RouteRule {
  return {id:stop.id,after:stop.coletaOrigemId,
    start: stop.janelaData ? ruleDateTime(stop.janelaData,stop.janelaInicio ?? ''):null,
    end: stop.janelaData ? ruleDateTime(stop.janelaData,stop.janelaFim ?? ''):null,
    serviceSeconds:(stop.tempoMedioAtendimentoMinutos || 0)*60};
}
