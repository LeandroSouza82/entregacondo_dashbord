import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import EmbeddedPostgres from 'embedded-postgres';
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
   await db.query(read('supabase/tests/regression_fixtures.sql'));
   const tests=await db.query(read('supabase/tests/security_and_approval_tests.sql'));
   const summary=(Array.isArray(tests)?tests:[tests]).find(r=>r.fields?.some(f=>f.name==='passed'));
   if(!summary || summary.rows[0].passed < 35) throw new Error('Suíte incompleta.');
   console.log(name+': '+summary.rows[0].passed+' regressões SQL passaram.');
 }

 const names=[...new Set(fs.readdirSync(path.join(root,'supabase/functions-sql')).filter(f=>f.endsWith('.sql')).map(f=>f.slice(0,-4)).concat(['fn_usuario_e_gestor_empresa','fn_usuario_e_admin_empresa','fn_motorista_id_do_usuario']))];
 const catalog=await compareLiveCatalogs(databases.get('ec_fresh'),databases.get('ec_upgrade'),names);
 console.log('Catálogos reais equivalentes: '+catalog.functions+' funções, '+catalog.policies+' políticas, '+catalog.constraints+' constraints da fila.');
 for(const name of ['ec_fresh','ec_upgrade']){
  const cases=await concurrencyRegressions(databases.get(name),()=>client(name));
  console.log(name+': '+cases.length+' cenários com conexões independentes passaram.');
 }
 const migrations=fs.readdirSync(path.join(root,'supabase/migrations')).filter(f=>f.endsWith('.sql')).sort();
 const safety=await migrationSafetyRegressions({
   createDatabase:(name)=>cluster.createDatabase(name),connect:client,read,migrations
 });
 console.log(safety.length+' verificações de preservação e falha segura de migração passaram.');
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
