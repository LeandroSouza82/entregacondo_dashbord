import assert from 'node:assert/strict';

const COMPANY='11111111-1111-1111-1111-111111111111';
const DRIVER='cccccccc-cccc-cccc-cccc-cccccccccccc';
const MANAGER='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const sleep=(ms)=>new Promise(resolve=>setTimeout(resolve,ms));
async function actor(client,user){
 await client.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[user]);
 await client.query('SET ROLE authenticated');
 return client;
}
async function rpc(client,name,args=[]){
 const marks=args.map((_,i)=>'$'+(i+1)).join(',');
 return client.query('SELECT * FROM public.'+name+'('+marks+')',args);
}
async function reservation(client,type='foto_veiculo',angle='frente'){
 const r=await client.query("SELECT public.reservar_upload_evidencia($1,$2,$3,$4) AS r",
  [COMPANY,type,type==='crlv'?'crlv.pdf':'foto.jpg',type==='foto_veiculo'?angle:null]);
 assert.equal(r.rows[0].r.sucesso,true);
 return r.rows[0].r;
}
async function metadata(admin,r){
 await admin.query("INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('veiculos-documentos',$1,$2)",
  [r.storage_path,JSON.stringify({size:500,mimetype:r.storage_path.endsWith('.pdf')?'application/pdf':'image/jpeg'})]);
}
async function waitForLock(admin,pid){
 const deadline=Date.now()+3000;
 while(Date.now()<deadline){
  const state=await admin.query('SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1',[pid]);
  if(state.rows[0]?.wait_event_type==='Lock')return;
  await sleep(20);
 }
 throw Error('A segunda conexão não aguardou o lock esperado.');
}
export async function concurrencyRegressions(admin,connect){
 const a=await actor(await connect(),DRIVER), b=await actor(await connect(),DRIVER);
 const manager=await actor(await connect(),MANAGER);
 const car=(await admin.query('SELECT id FROM public.veiculos_motoristas WHERE user_id=$1',[DRIVER])).rows[0].id;
 const pidB=(await b.query('SELECT pg_backend_pid() AS id')).rows[0].id;
 const reports=[];
 try{
  // Transações independentes, não uma sequência de chamadas na mesma conexão.
  const first=await reservation(a); await metadata(admin,first);
  await a.query('BEGIN'); await b.query('BEGIN');
  const attached=await a.query("SELECT public.anexar_documento_veiculo($1,'foto_veiculo','frente.jpg',$2,500,'frente') AS r",[car,first.storage_path]);
  assert.equal(attached.rows[0].r.sucesso,true);
  const pendingDiscard=b.query('SELECT public.descartar_evidencia_temporaria($1) AS r',[first.storage_path]);
  await waitForLock(admin,pidB);
  await a.query('COMMIT');
  assert.equal((await pendingDiscard).rows[0].r.codigo,'ARQUIVO_VINCULADO');
  await b.query('COMMIT');
  reports.push('anexação vence descarte concorrente');

  const second=await reservation(a,'foto_veiculo','lado_direito'); await metadata(admin,second);
  await a.query('BEGIN'); await b.query('BEGIN');
  assert.equal((await a.query('SELECT public.descartar_evidencia_temporaria($1) AS r',[second.storage_path])).rows[0].r.sucesso,true);
  const pendingAttach=b.query("SELECT public.anexar_documento_veiculo($1,'foto_veiculo','lado.jpg',$2,500,'lado_direito') AS r",[car,second.storage_path]);
  await waitForLock(admin,pidB);
  await a.query('COMMIT');
  assert.equal((await pendingAttach).rows[0].r.codigo,'ARQUIVO_EM_LIMPEZA');
  await b.query('COMMIT');
  reports.push('descarte vence anexação concorrente');

  const third=await reservation(a,'complementar');
  await a.query('SELECT public.descartar_evidencia_temporaria($1)',[third.storage_path]);
  await a.query('BEGIN');
  const firstClaim=(await rpc(a,'reivindicar_itens_limpeza_storage',[1,second.fila_id])).rows[0];
  assert.ok(firstClaim.claim_token);
  assert.equal((await rpc(b,'reivindicar_itens_limpeza_storage',[1,second.fila_id])).rowCount,0);
  const otherClaim=(await rpc(b,'reivindicar_itens_limpeza_storage',[1,third.fila_id])).rows[0];
  assert.notEqual(otherClaim.id,firstClaim.id);
  await a.query('COMMIT');
  reports.push('SKIP LOCKED evita dois processadores para o mesmo item');

  await admin.query("UPDATE public.storage_limpeza_fila SET lease_expires_at=clock_timestamp()-interval '1 second' WHERE id=$1",[firstClaim.id]);
  const recovered=(await rpc(b,'reivindicar_itens_limpeza_storage',[1,firstClaim.id])).rows[0];
  assert.notEqual(recovered.claim_token,firstClaim.claim_token);
  const stale=await a.query('SELECT public.registrar_limpeza_storage_executada($1,$2,false,$3) AS r',[firstClaim.id,firstClaim.claim_token,'retorno anterior']);
  assert.equal(stale.rows[0].r.codigo,'CLAIM_INVALIDO');
  assert.equal((await admin.query('SELECT claim_token FROM public.storage_limpeza_fila WHERE id=$1',[firstClaim.id])).rows[0].claim_token,recovered.claim_token);
  reports.push('resposta de lease anterior não altera tentativa recuperada');

  // Aprovação e remoção disputam o mesmo veículo.
  for(const angle of ['lado_direito','lado_esquerdo','traseira']){
   const r=await reservation(a,'foto_veiculo',angle); await metadata(admin,r);
   const result=await a.query("SELECT public.anexar_documento_veiculo($1,'foto_veiculo','foto.jpg',$2,500,$3) AS r",[car,r.storage_path,angle]);
   assert.equal(result.rows[0].r.sucesso,true);
  }
  const document=await reservation(a,'crlv'); await metadata(admin,document);
  assert.equal((await a.query("SELECT public.anexar_documento_veiculo($1,'crlv','crlv.pdf',$2,500) AS r",[car,document.storage_path])).rows[0].r.sucesso,true);
  const rev=(await admin.query('SELECT revisao FROM public.veiculos_motoristas WHERE id=$1',[car])).rows[0].revisao;
  const front=(await admin.query("SELECT id FROM public.veiculos_documentos WHERE veiculo_id=$1 AND angulo_foto='frente'",[car])).rows[0].id;
  await manager.query('BEGIN'); await b.query('BEGIN');
  assert.equal((await manager.query('SELECT public.analisar_veiculo_motorista($1,true,$2) AS r',[car,rev])).rows[0].r.sucesso,true);
  const pendingRemoval=b.query('SELECT public.remover_documento_veiculo($1) AS r',[front]);
  await waitForLock(admin,pidB);
  await manager.query('COMMIT');
  assert.equal((await pendingRemoval).rows[0].r.sucesso,true);
  await b.query('COMMIT');
  assert.equal((await admin.query('SELECT status_analise FROM public.veiculos_motoristas WHERE id=$1',[car])).rows[0].status_analise,'pendente');
  reports.push('remoção concorrente invalida aprovação recém-concluída');
  // Restore complete approved evidence for collection tests in this disposable database.
  const restored=await reservation(a);await metadata(admin,restored);
  assert.equal((await a.query("SELECT public.anexar_documento_veiculo($1,'foto_veiculo','frente.jpg',$2,500,'frente') AS r",[car,restored.storage_path])).rows[0].r.sucesso,true);
  const restoredRevision=(await admin.query('SELECT revisao FROM public.veiculos_motoristas WHERE id=$1',[car])).rows[0].revisao;
  assert.equal((await manager.query('SELECT public.analisar_veiculo_motorista($1,true,$2) AS r',[car,restoredRevision])).rows[0].r.sucesso,true);
  const secondManager=await actor(await connect(),MANAGER);
  try {
   const driverId='c1000000-0000-0000-0000-000000000001';
   await admin.query("UPDATE public.motoristas SET latitude_atual=-27.5,longitude_atual=-48.5,localizacao_atualizada_em=now() WHERE id=$1",[driverId]);
   const address=(await admin.query("INSERT INTO public.clientes_enderecos(empresa_id,nome_identificador,endereco_completo,numero,bairro,cidade,cep,latitude,longitude) VALUES($1,'Concorrência','Rua teste','10','Centro','Teste','00000-000',-27.51,-48.51) RETURNING id",[COMPANY])).rows[0].id;
   const route=(await admin.query("INSERT INTO public.rotas_planejadas(empresa_id,motorista_id,status,idempotency_key,distancia_original_km,tempo_original_minutos,distancia_otimizada_km,tempo_otimizado_minutos,percentual_economia_km,percentual_economia_tempo,ordem_paradas_json) VALUES($1,$2,'em_execucao','CONCURRENT-ACTIVE',5,10,5,10,0,0,'[]') RETURNING id",[COMPANY,driverId])).rows[0].id;
   const old=(await admin.query("INSERT INTO public.entregas(empresa_id,rota_id,motorista_id,cliente_endereco_id,codigo_rastreio,destinatario_nome,status,ordem_na_rota) VALUES($1,$2,$3,$4,'CONCURRENT-OLD','Existing','atribuida',1) RETURNING id",[COMPANY,route,driverId,address])).rows[0].id;
   const payload={empresa_id:COMPANY,motorista_id:driverId,idempotency_key:'CONCURRENT-SAME',paradas:[{cliente_endereco_id:address,tipo_tarefa:'coleta',destinatario_nome:'Collection'}]};
   async function snapshot(){return (await admin.query("SELECT jsonb_agg(jsonb_build_object('id',id,'status',status,'ordem_na_rota',ordem_na_rota,'chegada_em',chegada_em) ORDER BY ordem_na_rota) AS r FROM public.entregas WHERE rota_id=$1",[route])).rows[0].r;}
   const plan={rota_id:route,origem:{lat:-27.5,lng:-48.5},snapshot:await snapshot(),ordem:['nova:0',old],metricas:{fonte:'mapbox_directions_restante',distancia_km:5,tempo_minutos:10}};
   const pidSecond=(await secondManager.query('SELECT pg_backend_pid() AS id')).rows[0].id;
   await manager.query('BEGIN');await secondManager.query('BEGIN');
   const first=(await manager.query('SELECT public.enviar_servicos_motorista($1,$2) AS r',[payload,plan])).rows[0].r;
   assert.equal(first.sucesso,true,JSON.stringify(first));
   const duplicate=secondManager.query('SELECT public.enviar_servicos_motorista($1,$2) AS r',[payload,plan]);
   await waitForLock(admin,pidSecond);await manager.query('COMMIT');
   assert.equal((await duplicate).rows[0].r.idempotente,true);await secondManager.query('COMMIT');
   assert.equal((await admin.query('SELECT count(*)::int AS n FROM public.entregas WHERE rota_id=$1',[route])).rows[0].n,2);
   reports.push('envio concorrente da mesma coleta é idempotente entre conexões');
   plan.snapshot=await snapshot();plan.ordem=['nova:0',...plan.snapshot.map(t=>t.id)];
   await manager.query('BEGIN');await secondManager.query('BEGIN');
   assert.equal((await manager.query('SELECT public.enviar_servicos_motorista($1,$2) AS r',[{...payload,idempotency_key:'CONCURRENT-FIRST'},plan])).rows[0].r.sucesso,true);
   const stale=secondManager.query('SELECT public.enviar_servicos_motorista($1,$2) AS r',[{...payload,idempotency_key:'CONCURRENT-SECOND'},plan]);
   await waitForLock(admin,pidSecond);await manager.query('COMMIT');
   assert.equal((await stale).rows[0].r.codigo,'PLANO_DESATUALIZADO');await secondManager.query('COMMIT');
   assert.equal((await admin.query('SELECT count(*)::int AS n FROM public.entregas WHERE rota_id=$1',[route])).rows[0].n,3);
   reports.push('coletas simultâneas distintas exigem recálculo sem perder serviços');
  } finally {await secondManager.query('ROLLBACK');}

 }finally{
  for(const c of [a,b,manager])await c.query('ROLLBACK').catch(()=>{});
 }
 return reports;
}
export async function compareLiveCatalogs(fresh,upgraded,names){
 async function snapshot(db){
  const functions=await db.query(
   "SELECT p.proname,oidvectortypes(p.proargtypes) AS args,pg_get_functiondef(p.oid) AS definition,"+
   "has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute "+
   "FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname=ANY($1) ORDER BY p.proname,args",[names]);
  const policies=await db.query("SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check FROM pg_policies WHERE schemaname='public' OR (schemaname='storage' AND tablename='objects') ORDER BY schemaname,tablename,policyname");
  const constraints=await db.query("SELECT c.conname,pg_get_constraintdef(c.oid) AS definition FROM pg_constraint c WHERE c.conrelid='public.storage_limpeza_fila'::regclass ORDER BY c.conname");
  return {functions:functions.rows.map(row=>({...row,definition:row.definition.replace(/\r\n/g,'\n')})),policies:policies.rows,constraints:constraints.rows};
 }
 const a=await snapshot(fresh),b=await snapshot(upgraded);
 assert.deepEqual(b.functions,a.functions,'RPCs e privilégios divergem entre instalação nova e atualização');
 assert.deepEqual(b.policies,a.policies,'Políticas efetivas divergem entre instalação nova e atualização');
 assert.deepEqual(b.constraints,a.constraints,'Constraints da fila divergem entre instalação nova e atualização');
 return {functions:a.functions.length,policies:a.policies.length,constraints:a.constraints.length};
}
export async function migrationSafetyRegressions({createDatabase,connect,read,migrations}){
 const targetIndex=migrations.findIndex(f=>f.endsWith('_secure_claims_and_operational_authorization.sql'));
 if(targetIndex<0) throw new Error('Migração de segurança ausente.');
 const last=migrations[targetIndex];
 const earlier=migrations.slice(0,targetIndex);
 const reports=[];
 async function database(name,fresh){
  await createDatabase(name);
  const db=await connect(name);
  await db.query(read('supabase/tests/local_bootstrap.sql'));
  if(fresh)await db.query(read('supabase/schema.sql'));
  else for(const file of earlier)await db.query(read('supabase/migrations/'+file));
  return db;
 }
 // Um veículo e uma foto legados precisam manter conteúdo, IDs e empresa.
 const legacy=await database('ec_legacy_data',false);
 const uid='77777777-7777-7777-7777-777777777777';
 const company='77777777-0000-0000-0000-000000000001';
 const car='77777777-0000-0000-0000-000000000002';
 const storagePath=company+'/'+uid+'/preservada.jpg';
 await legacy.query("INSERT INTO public.empresas(id,nome,codigo_convite) VALUES($1,'Legada','LEGACY-TEST')",[company]);
 await legacy.query("INSERT INTO auth.users(id,email,raw_user_meta_data,role,aud) VALUES($1,'legacy@example.test','{\"nome\":\"Legado\"}','authenticated','authenticated')",[uid]);
 await legacy.query("INSERT INTO public.veiculos_motoristas(id,empresa_id,user_id,tipo_veiculo,marca,modelo,placa,status_aprovacao) VALUES($1,$2,$3,'carro','Marca preservada','Modelo preservado','LEG1A23','pendente')",[car,company,uid]);
 await legacy.query("INSERT INTO public.veiculos_documentos(veiculo_id,empresa_id,user_id,tipo_documento,angulo_foto,nome_arquivo,storage_path,mime_type,tamanho_bytes) VALUES($1,$2,$3,'foto_veiculo','frente','preservada.jpg',$4,'image/jpeg',500)",[car,company,uid,storagePath]);
 await legacy.query(read('supabase/migrations/'+last));
 assert.deepEqual((await legacy.query('SELECT id,empresa_id,user_id,marca,modelo,placa,status_analise FROM public.veiculos_motoristas WHERE id=$1',[car])).rows[0],
  {id:car,empresa_id:company,user_id:uid,marca:'Marca preservada',modelo:'Modelo preservado',placa:'LEG1A23',status_analise:'pendente'});
 assert.equal((await legacy.query('SELECT status FROM public.storage_limpeza_fila WHERE storage_path=$1',[storagePath])).rows[0].status,'vinculado');
 assert.equal((await legacy.query('SELECT count(*)::int AS n FROM public.veiculos_documentos WHERE veiculo_id=$1',[car])).rows[0].n,1);
 // A mesma migração pode ser repetida sem duplicar vínculo nem apagar evidência.
 await legacy.query(read('supabase/migrations/'+last));
 assert.equal((await legacy.query('SELECT count(*)::int AS n FROM public.storage_limpeza_fila WHERE storage_path=$1',[storagePath])).rows[0].n,1);
 reports.push('migração preserva veículo e evidência legados e pode ser repetida');

 const duplicate=await database('ec_invalid_queue',true);
 await duplicate.query(read('supabase/tests/regression_fixtures.sql'));
 await duplicate.query('ALTER TABLE public.storage_limpeza_fila DROP CONSTRAINT storage_limpeza_fila_storage_path_key');
 await duplicate.query("INSERT INTO public.storage_limpeza_fila(storage_path,empresa_id,user_id,motivo) SELECT 'duplicate-test',$1,$2,'teste' FROM generate_series(1,2)",[COMPANY,DRIVER]);
 let rejected=false;
 try{await duplicate.query(read('supabase/migrations/'+last));}catch(e){
  rejected=/Caminhos duplicados/.test(e.message); await duplicate.query('ROLLBACK');
 }
 assert.equal(rejected,true,'migração deve recusar caminhos duplicados');
 assert.equal((await duplicate.query("SELECT count(*)::int AS n FROM public.storage_limpeza_fila WHERE storage_path='duplicate-test'")).rows[0].n,2);
 reports.push('migração falha de forma explícita e preserva caminhos duplicados');

 await createDatabase('ec_orphans');
 const orphans=await connect('ec_orphans');
 await orphans.query(read('supabase/tests/local_bootstrap.sql'));
 for(const f of migrations.slice(0,2))await orphans.query(read('supabase/migrations/'+f));
 const id=(await orphans.query("INSERT INTO public.motoristas(nome,telefone,veiculo_modelo,veiculo_placa,empresa_id) VALUES('Órfão teste','000','Legado','LEG1A24',null) RETURNING id")).rows[0].id;
 rejected=false;
 try{await orphans.query(read('supabase/migrations/'+migrations[2]));}catch(e){
  rejected=/sem empresa/.test(e.message);await orphans.query('ROLLBACK');
 }
 assert.equal(rejected,true,'órfão deve exigir reconciliação');
 assert.equal((await orphans.query('SELECT count(*)::int AS n FROM public.motoristas WHERE id=$1 AND empresa_id IS NULL',[id])).rows[0].n,1);
 reports.push('migração anterior recusa órfãos sem excluir nem mover registros');
 return reports;
}