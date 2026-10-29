import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import EmbeddedPostgres from 'embedded-postgres';
import { trialConcurrency, legacyPolicyCleanup } from './subscription_regressions.js';
import { concurrencyRegressions, compareLiveCatalogs, migrationSafetyRegressions } from './database_regressions.js';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const read=(p)=>fs.readFileSync(path.join(root,p),'utf8');
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'entregacondo-pg-tests-'));
const port=await new Promise((resolve,reject)=>{
 const server=net.createServer(); server.once('error',reject);
 server.listen(0,'127.0.0.1',()=>{const p=server.address().port;server.close(()=>resolve(p));});
});
const logs=[];
const cluster=new EmbeddedPostgres({
 databaseDir:path.join(temp,'db'),user:'postgres',password:crypto.randomBytes(24).toString('hex'),
 port,persistent:true,initdbFlags:['--locale=C','--encoding=UTF8'],
 postgresFlags:['-c','listen_addresses=127.0.0.1','-c','max_connections=20'],
 onLog:(m)=>logs.push(String(m)),onError:(m)=>logs.push(String(m))
});
let failed=false;
const databases=new Map();
const clients=[];
async function client(database){
 const c=cluster.getPgClient(database,'127.0.0.1');await c.connect();clients.push(c);return c;
}
try {
 await cluster.initialise(); await cluster.start();
 console.log('PostgreSQL 17 iniciado apenas em 127.0.0.1, em diretório temporário.');
 for(const name of ['ec_fresh','ec_upgrade']){
   await cluster.createDatabase(name);
   const db=await client(name); await db.query(read('supabase/tests/local_bootstrap.sql'));
   if(name==='ec_fresh')await db.query(read('supabase/schema.sql'));
   else for(const f of fs.readdirSync(path.join(root,'supabase/migrations')).filter(f=>f.endsWith('.sql')).sort()){
     try{await db.query(read('supabase/migrations/'+f));}
     catch(e){throw new Error('Migração '+f+': '+e.message,{cause:e});}
   }
   console.log(name+': instalação SQL executada.');
   databases.set(name,db);
   await legacyPolicyCleanup(db,read);
   console.log(name+': legacy permissive policies removed; company city update remains scoped.');
   await db.query(read('supabase/tests/regression_fixtures.sql'));
   const trial=await db.query(read('supabase/tests/company_trial_tests.sql'));
   const trialSummary=trial.find(r=>r.fields?.some(f=>f.name==='trial_passed'));
   if(!trialSummary || +trialSummary.rows[0].trial_passed<20)throw new Error('Trial suite incomplete.');
   console.log(name+': '+trialSummary.rows[0].trial_passed+' verificações de cadastro, isolamento e teste grátis passaram.');
   await db.query(read('supabase/tests/trial_registration_tests.sql'));
   console.log(name+': cadastro CPF/CNPJ, duplicação, privacidade e exclusão passaram.');
   await db.query(read('supabase/tests/customer_tracking_tests.sql'));
   console.log(name+': cenários de acompanhamento, privacidade e preservação passaram.');
   await db.query(read('supabase/tests/release_compatibility_tests.sql'));
   console.log(name+': 12 verificações da view, helper e coordenadas passaram.');
   const sharing=await db.query(read('supabase/tests/receipt_sharing_tests.sql'));
   const sharingSummary=sharing.find(r=>r.fields?.some(f=>f.name==='receipt_sharing_passed'));
   if(!sharingSummary || +sharingSummary.rows[0].receipt_sharing_passed<25)throw new Error('Suíte de compartilhamento incompleta.');
   console.log(name+': '+sharingSummary.rows[0].receipt_sharing_passed+' verificações de compartilhamento privado passaram.');
   if(process.argv.includes('--tracking-only'))continue;
   const planning=await db.query(read('supabase/tests/route_rules_tests.sql'));
   const planningSummary=planning.find(r=>r.fields?.some(f=>f.name==='planning_passed'));
   if(!planningSummary || +planningSummary.rows[0].planning_passed<40) throw new Error('Suíte de regras incompleta.');
   console.log(name+': '+planningSummary.rows[0].planning_passed+' verificações de regras opcionais passaram.');
   if(process.argv.includes('--planning-only')) continue;
   await db.query(read('supabase/tests/driver_order_inbox_tests.sql'));
   console.log(name+': aceitação, retirada e isolamento de pedidos passaram.');
   const tests=await db.query(read('supabase/tests/security_and_approval_tests.sql'));
   const summary=(Array.isArray(tests)?tests:[tests]).find(r=>r.fields?.some(f=>f.name==='passed'));
   if(!summary || summary.rows[0].passed < 35) throw new Error('Suíte incompleta.');
   console.log(name+': '+summary.rows[0].passed+' regressões SQL passaram.');
   const push=await db.query(read('supabase/tests/push_notification_tests.sql'));
   const pushSummary=(Array.isArray(push)?push:[push]).find(r=>r.fields?.some(f=>f.name==='push_passed'));
   console.log(name+': '+pushSummary.rows[0].push_passed+' verificações de notificações passaram.');
 }

 if(process.argv.includes('--planning-only')) {
  for(const name of ['ec_fresh','ec_upgrade']){
    const cases=await concurrencyRegressions(databases.get(name),()=>client(name));
    console.log(name+': '+cases.length+' regressões existentes com conexões independentes passaram.');
  }
  console.log('Regras opcionais validadas em instalação nova e atualização.');
 } else if(process.argv.includes('--tracking-only')) { console.log('Acompanhamento validado em instalação nova e atualização.'); } else {
 const names=[...new Set(fs.readdirSync(path.join(root,'supabase/functions-sql')).filter(f=>f.endsWith('.sql')).map(f=>f.slice(0,-4)).concat(['atualizar_meu_nome_motorista','fn_usuario_e_gestor_empresa','fn_usuario_e_admin_empresa','fn_motorista_id_do_usuario','registrar_dispositivo_push','desativar_dispositivo_push','fn_enfileirar_push_servicos','reivindicar_push_envios','finalizar_push_envio','fn_acordar_push_worker','fn_acordar_push_apos_fila','fn_safe_uuid','criar_compartilhamento_comprovante','obter_comprovante_compartilhado','revogar_compartilhamento_comprovante','obter_capacidades_rotas','preparar_aviso_cliente','obter_acompanhamento_cliente','configurar_nome_empresa','iniciar_teste_empresa','registrar_teste_empresa','documento_valido','obter_minha_assinatura','preparar_checkout_assinatura','vincular_checkout_assinatura','registrar_pagamento_assinatura','obter_contexto_pagamento_assinatura']))];
 const catalog=await compareLiveCatalogs(databases.get('ec_fresh'),databases.get('ec_upgrade'),names);
 console.log('Catálogos reais equivalentes: '+catalog.functions+' funções, '+catalog.policies+' políticas, '+catalog.constraints+' constraints da fila.');
 for(const name of ['ec_fresh','ec_upgrade']){
  const cases=await concurrencyRegressions(databases.get(name),()=>client(name));
  console.log(name+': '+cases.length+' cenários com conexões independentes passaram.');
  const commercial=await trialConcurrency(databases.get(name),()=>client(name));
  console.log(name+': '+commercial+' cenários concorrentes de teste grátis, motoristas e checkout passaram.');
 }
 const migrations=fs.readdirSync(path.join(root,'supabase/migrations')).filter(f=>f.endsWith('.sql')).sort();
 const safety=await migrationSafetyRegressions({
   createDatabase:(name)=>cluster.createDatabase(name),connect:client,read,migrations
 });
 console.log(safety.length+' verificações de preservação e falha segura de migração passaram.');
 }
} catch(e){
 failed=true; console.error(e.message); console.error(e.where || e.detail || "");
 if(e.cause)console.error('SQL:',e.cause.where||e.cause.detail||e.cause.position||e.cause.message);
 if(!clients.length) console.error(logs.slice(-8).join('\n'));
 process.exitCode=1;
} finally{
 for(const c of clients)await c.end().catch(()=>{});
 await cluster.stop().catch(()=>{});
 const resolved=path.resolve(temp);
 if(path.dirname(resolved)===path.resolve(os.tmpdir()) && path.basename(resolved).startsWith('entregacondo-pg-tests-')){
   fs.rmSync(resolved,{recursive:true,force:true,maxRetries:10,retryDelay:200});
 }
}
if(failed) process.exit(1);
