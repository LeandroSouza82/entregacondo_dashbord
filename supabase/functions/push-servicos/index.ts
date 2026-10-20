import {createClient} from 'npm:@supabase/supabase-js@2.118.0';
import {createPushHandler} from './handler.ts';
import {parseAccount,googleAccessToken} from './fcm.ts';
const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
let cached:{token:string;until:number}|undefined;
Deno.serve(createPushHandler({
 secret:Deno.env.get('PUSH_WORKER_SECRET')||'',
 accessToken:async()=>{
  if(cached&&cached.until>Date.now())return cached.token;
  const token=await googleAccessToken(parseAccount(Deno.env.get('FIREBASE_SERVICE_ACCOUNT')||''));cached={token,until:Date.now()+50*60*1000};return token;
 },
 claim:async()=>{const {data,error}=await client.rpc('reivindicar_push_envios',{p_limite:10});if(error)throw error;return data||[];},
 finish:async(job,result)=>{const {data,error}=await client.rpc('finalizar_push_envio',{p_id:job.id,p_claim:job.claim_token,p_resultado:result.result,p_erro:result.code||null});if(error)throw error;return data===true;},
}));
