export const FIREBASE_PROJECT = 'entregacondo-push-2026';
export const CHANNEL = 'entregacondo_rotas_voz_v2';
export type PushJob = {id:string;claim_token:string;token:string;rota_id:string;tipo:'nova_rota'|'nova_coleta';quantidade:number;expires_at:string};
export type SendResult = {result:'aceito'|'repetir'|'invalido'|'falhou';code?:string};
export function fcmMessage(job:PushJob,now=Date.now()) {
 const seconds=Math.max(0,Math.min(86400,Math.floor((Date.parse(job.expires_at)-now)/1000)));
 if(!Number.isFinite(seconds)||seconds<=0)throw new Error('EXPIRED');
 return {message:{token:job.token,notification:{title:job.tipo==='nova_coleta'?'Nova coleta na sua rota':'Nova rota recebida',body:job.tipo==='nova_coleta'?`${job.quantidade} coleta(s) adicionada(s). Abra o EntregaCondo para conferir.`:`Você recebeu uma rota com ${job.quantidade} serviço(s). Toque para conferir.`},data:{route_id:job.rota_id,event_id:job.id,type:job.tipo},android:{priority:'high',ttl:`${seconds}s`,notification:{channel_id:job.tipo==='nova_coleta'?'entregacondo_coletas_voz_v2':CHANNEL,sound:job.tipo==='nova_coleta'?'nova_coleta':'nova_rota',tag:job.id,visibility:'PRIVATE'}}}};
}
export async function sendFcm(job:PushJob,accessToken:string,request:typeof fetch=fetch):Promise<SendResult>{
 const response=await request(`https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT}/messages:send`,{method:'POST',headers:{Authorization:`Bearer ${accessToken}`,'Content-Type':'application/json'},body:JSON.stringify(fcmMessage(job)),signal:AbortSignal.timeout(15000)});
 if(response.ok)return {result:'aceito'};
 const body=await response.json().catch(()=>({}));
 const code=body.error?.details?.find((d:{'@type'?:string})=>d['@type']==='type.googleapis.com/google.firebase.fcm.v1.FcmError')?.errorCode;
 if(code==='UNREGISTERED')return {result:'invalido',code};
 if(response.status===429||response.status>=500||response.status===401)return {result:'repetir',code:code||`HTTP_${response.status}`};
 // Generic INVALID_ARGUMENT can be a bad payload, not an invalid device token.
 return {result:'falhou',code:code||`HTTP_${response.status}`};
}
export type ServiceAccount = {project_id:string;client_email:string;private_key:string};
const b64=(value:Uint8Array)=>btoa(String.fromCharCode(...value)).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');
const encode=(value:unknown)=>b64(new TextEncoder().encode(JSON.stringify(value)));
export function parseAccount(raw:string):ServiceAccount {
 const account=JSON.parse(raw);
 if(account.project_id!==FIREBASE_PROJECT||typeof account.client_email!=='string'||!account.client_email.endsWith(`@${FIREBASE_PROJECT}.iam.gserviceaccount.com`)||!account.private_key?.includes('BEGIN PRIVATE KEY'))throw Error('FIREBASE_CONFIGURATION_INVALID');
 return account;
}
export async function googleAccessToken(account:ServiceAccount,request:typeof fetch=fetch):Promise<string>{
 const pem=account.private_key.replace(/-----[^-]+-----/g,'').replace(/\s/g,'');
 const key=await crypto.subtle.importKey('pkcs8',Uint8Array.from(atob(pem),c=>c.charCodeAt(0)),{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);
 const now=Math.floor(Date.now()/1000),unsigned=`${encode({alg:'RS256',typ:'JWT'})}.${encode({iss:account.client_email,scope:'https://www.googleapis.com/auth/firebase.messaging',aud:'https://oauth2.googleapis.com/token',iat:now,exp:now+3600})}`;
 const signature=await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,new TextEncoder().encode(unsigned));
 const response=await request('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion:`${unsigned}.${b64(new Uint8Array(signature))}`}),signal:AbortSignal.timeout(15000)});
 const data=await response.json();if(!response.ok||typeof data.access_token!=='string')throw Error('FIREBASE_AUTH_FAILED');return data.access_token;
}
