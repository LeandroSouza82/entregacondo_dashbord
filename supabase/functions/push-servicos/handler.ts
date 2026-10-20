import {sendFcm,type PushJob,type SendResult} from './fcm.ts';
export interface PushDependencies {secret:string;accessToken:()=>Promise<string>;claim:()=>Promise<PushJob[]>;finish:(job:PushJob,result:SendResult)=>Promise<boolean>;send?:typeof sendFcm}
async function matches(a:string,b:string){
 const digest=async(value:string)=>new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)));
 const [x,y]=await Promise.all([digest(a),digest(b)]);let difference=0;for(let i=0;i<x.length;i++)difference|=x[i]^y[i];return difference===0;
}
export function createPushHandler(deps:PushDependencies){return async(request:Request):Promise<Response>=>{
 if(request.method!=='POST')return new Response('Method not allowed',{status:405});
 if(deps.secret.length<32)return Response.json({error:'PUSH_NOT_CONFIGURED'},{status:503});
 if(!await matches(request.headers.get('x-push-worker-secret')||'',deps.secret))return new Response('Unauthorized',{status:401});
 try {
  const token=await deps.accessToken(); // Never lease jobs until Firebase credentials work.
  const jobs=await deps.claim();let accepted=0,failed=0;
  for(let offset=0;offset<jobs.length;offset+=5)await Promise.all(jobs.slice(offset,offset+5).map(async(job)=>{
   let result:SendResult;
   try{result=await (deps.send||sendFcm)(job,token);}catch(e){result=e instanceof Error&&e.message==='EXPIRED'?{result:'falhou',code:'EXPIRED'}:{result:'repetir',code:'NETWORK_ERROR'};}
   if(await deps.finish(job,result)&&result.result==='aceito')accepted++;else failed++;
  }));
  return Response.json({processed:jobs.length,accepted,retry_or_failed:failed});
 } catch {return Response.json({error:'PUSH_WORKER_UNAVAILABLE'},{status:503});}
};}
