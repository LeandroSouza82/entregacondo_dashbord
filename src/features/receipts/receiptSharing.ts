import type {SupabaseClient} from '@supabase/supabase-js';
import type {Database} from '../../types/database';

export interface SharedReceipt {
  sucesso: true;
  entrega_id: string;
  destinatario_nome: string;
  endereco?: string | null;
  empresa_nome: string;
  recebedor_tipo: string;
  recebedor_nome?: string | null;
  observacao?: string | null;
  foto_url?: string | null;
  assinatura_url?: string | null;
  concluida_em: string;
  duracao_segundos: number;
  expira_em: string;
  servidor_em: string;
}
type Receipt = Database['public']['Tables']['entrega_comprovantes']['Row'];
export const receiptShareTokenValid = (token: string): boolean => /^[0-9a-f]{64}$/.test(token);

export function createReceiptShareToken(): string {
  return [...crypto.getRandomValues(new Uint8Array(32))].map(b=>b.toString(16).padStart(2,'0')).join('');
}

/** Accept only signed private objects on this project's Storage API. */
export function safeReceiptMedia(value: unknown, apiUrl: string): string | null {
  if (typeof value!=='string') return null;
  try {
    const url=new URL(value), api=new URL(apiUrl);
    if (url.protocol!=='https:' || url.origin!==api.origin || url.username || url.password || url.hash
      || !url.pathname.startsWith('/storage/v1/object/sign/entregas-comprovantes/')
      || !/^[A-Za-z0-9_.-]+$/.test(url.searchParams.get('token') || '')) return null;
    return url.href;
  } catch { return null; }
}

export function readSharedReceipt(raw: unknown, apiUrl: string): SharedReceipt | null {
  if (!raw || typeof raw!=='object') return null;
  const r=raw as Partial<SharedReceipt>;
  if (r.sucesso!==true || typeof r.entrega_id!=='string' || typeof r.destinatario_nome!=='string'
    || typeof r.empresa_nome!=='string' || typeof r.recebedor_tipo!=='string'
    || !Number.isFinite(r.duracao_segundos) || r.duracao_segundos!<0
    || !Number.isFinite(Date.parse(r.concluida_em || ''))
    || !Number.isFinite(Date.parse(r.expira_em || '')) || !Number.isFinite(Date.parse(r.servidor_em || ''))
    || Date.parse(r.expira_em!)<=Date.parse(r.servidor_em!)) return null;
  return {...r, foto_url:safeReceiptMedia(r.foto_url,apiUrl),assinatura_url:safeReceiptMedia(r.assinatura_url,apiUrl)} as SharedReceipt;
}

async function bounded<T>(operation:PromiseLike<T>,milliseconds:number):Promise<T> {
  let timer:ReturnType<typeof setTimeout>|undefined;
  try {return await Promise.race([Promise.resolve(operation),new Promise<never>((_,reject)=>{timer=setTimeout(()=>reject(new Error('A conexão demorou demais. Tente novamente.')),milliseconds);})]);}
  finally {clearTimeout(timer);}
}

/** Sharing requires authorized signing; the public reader never signs or lists assets. */
export async function shareReceipt(client: SupabaseClient<Database>, receipt: Receipt, pageUrl: string, apiUrl: string): Promise<{url:string;expiresAt:string}> {
  const page=new URL(pageUrl);
  if (page.protocol!=='https:' && !(page.protocol==='http:' && ['localhost','127.0.0.1'].includes(page.hostname))) {
    throw new Error('O compartilhamento precisa do endereço HTTPS do dashboard.');
  }
  const initial=await client.auth.getSession();
  const owner=initial.data.session?.user.id;
  if (!owner) throw new Error('Entre novamente para compartilhar.');
  async function sign(path: string | null): Promise<string | null> {
    if (!path) return null;
    if (path.split('/')[0]!==receipt.empresa_id || path.split('/')[2]!==receipt.entrega_id) throw new Error('Imagem fora deste comprovante.');
    const result=await bounded(client.storage.from('entregas-comprovantes').createSignedUrl(path,3600),15000);
    const url=safeReceiptMedia(result.data?.signedUrl,apiUrl);
    if (result.error || !url) throw new Error('Não foi possível preparar a imagem do comprovante.');
    return url;
  }
  const started=Date.now();
  const [photo,signature]=await Promise.all([sign(receipt.foto_path),sign(receipt.assinatura_path)]);
  if (Date.now()-started>120000) throw new Error('A preparação demorou demais. Tente novamente.');
  if ((await client.auth.getSession()).data.session?.user.id!==owner) throw new Error('A conta mudou. Entre novamente.');
  const token=createReceiptShareToken();
  const controller=new AbortController();
  const timeout=setTimeout(()=>controller.abort(),15000);
  let result;
  try { result=await client.rpc('criar_compartilhamento_comprovante',{p_entrega_id:receipt.entrega_id,p_token:token,p_foto_url:photo,p_assinatura_url:signature}).abortSignal(controller.signal); }
  finally {clearTimeout(timeout);}
  if ((await client.auth.getSession()).data.session?.user.id!==owner) throw new Error('A conta mudou. Entre novamente.');
  const value=result.data as {sucesso?:boolean;expira_em?:string}|null;
  if (result.error || value?.sucesso!==true || !Number.isFinite(Date.parse(value.expira_em || ''))) {
    throw new Error('Não foi possível criar o link. Confira a atualização do banco e tente novamente.');
  }
  page.search='';page.hash=`/comprovante/${token}`;
  return {url:page.href,expiresAt:value!.expira_em!};
}
