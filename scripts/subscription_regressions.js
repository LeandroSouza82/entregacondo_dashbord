import assert from 'node:assert/strict';
export async function trialConcurrency(db, connect) {
 const user='ab000000-0000-0000-0000-000000000099';
 await db.query("insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values($1,'concurrent-trial@example.test',now(),'{\"empresa_nome\":\"Concurrent Company\"}')",[user]);
 const left=await connect(),right=await connect();
 for(const c of [left,right])await c.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);
 const results=await Promise.all([left.query('select public.iniciar_teste_empresa() as result'),right.query('select public.iniciar_teste_empresa() as result')]);
 const company=results[0].rows[0].result.empresa_id;
 assert.equal(results[1].rows[0].result.empresa_id,company);
 assert.equal((await db.query('select count(*)::int as n from ec_private.assinaturas_empresas where titular_id=$1',[user])).rows[0].n,1);
 for(let i=1;i<=2;i++)await db.query("insert into public.motoristas(empresa_id,nome,telefone,veiculo_modelo,veiculo_placa) values($1,'Driver','000','Test',$2)",[company,'CONCURRENT-'+i]);
 const drivers=await Promise.allSettled([left.query("insert into public.motoristas(empresa_id,nome,telefone,veiculo_modelo,veiculo_placa) values($1,'Driver','000','Test','CONCURRENT-3')",[company]),right.query("insert into public.motoristas(empresa_id,nome,telefone,veiculo_modelo,veiculo_placa) values($1,'Driver','000','Test','CONCURRENT-4')",[company])]);
 assert.equal(drivers.filter(r=>r.status==='fulfilled').length,1);assert.equal(drivers.filter(r=>r.status==='rejected'&&r.reason.code==='23514').length,1);
 assert.equal((await db.query('select count(*)::int as n from public.motoristas where empresa_id=$1 and ativo',[company])).rows[0].n,3);
 await db.query("update ec_private.assinaturas_empresas set teste_inicio=now()-interval '31 days',teste_fim=now()-interval '1 day' where empresa_id=$1",[company]);
 for(const c of [left,right])await c.query('set role authenticated');
 const checkouts=await Promise.all([left.query('select public.preparar_checkout_assinatura($1) as result',[company]),right.query('select public.preparar_checkout_assinatura($1) as result',[company])]);
 assert.equal(checkouts[0].rows[0].result.id,checkouts[1].rows[0].result.id);
 for(const c of [left,right]){await c.query('reset role');await c.query("select set_config('request.jwt.claim.sub','',false)");}
 return 3;
}

export async function legacyPolicyCleanup(db, read) {
 const policies = [
  ['empresas','Acesso empresas'],['empresa_membros','Acesso membros'],
  ['perfis_usuarios','Acesso perfis'],['motoristas','Acesso total a motoristas para membros da empresa'],
  ['entregas','Acesso a entregas para autenticados'],['rotas_planejadas','Acesso a rotas para autenticados'],
  ['clientes_enderecos','Acesso a clientes enderecos para autenticados'],['clientes_enderecos','Permitir exclusao de enderecos'],
 ];
 await db.query('BEGIN');
 try {
  for (const [table,name] of policies) {
   await db.query(`CREATE POLICY "${name}" ON public.${table} FOR ALL TO authenticated USING(true) WITH CHECK(true)`);
   await db.query(`GRANT ALL ON public.${table} TO authenticated`);
  }
  const user='ad000000-0000-0000-0000-000000000001';
  const own='ad000000-0000-0000-0000-000000000002';
  const foreign='ad000000-0000-0000-0000-000000000003';
  await db.query("INSERT INTO auth.users(id,email,email_confirmed_at) VALUES($1,'legacy-policy@example.test',now())",[user]);
  await db.query("INSERT INTO public.empresas(id,nome,codigo_convite) VALUES($1,'Own Company','LEGACY-OWN'),($2,'Foreign Company','LEGACY-FOREIGN')",[own,foreign]);
  await db.query("INSERT INTO public.empresa_membros(empresa_id,user_id,papel,status) VALUES($1,$2,'admin','aprovado')",[own,user]);
  await db.query("SELECT set_config('request.jwt.claim.sub',$1,true)",[user]);
  await db.query('SET LOCAL ROLE authenticated');
  assert.equal((await db.query('SELECT count(*)::int n FROM public.empresas WHERE id=$1',[foreign])).rows[0].n,1);
  await db.query('RESET ROLE');
  await db.query("GRANT EXECUTE ON FUNCTION public.bootstrap_primeiro_gestor(text,text,text) TO authenticated");
  await db.query(read('supabase/modules-sql/11_company_trial.sql'));
  assert.equal((await db.query("SELECT has_function_privilege('authenticated','public.bootstrap_primeiro_gestor(text,text,text)','EXECUTE') allowed")).rows[0].allowed,false);
  for (const [table,name] of policies) {
   assert.equal((await db.query('SELECT count(*)::int n FROM pg_policies WHERE schemaname=$1 AND tablename=$2 AND policyname=$3',['public',table,name])).rows[0].n,0);
   assert.equal((await db.query("SELECT has_table_privilege('authenticated',$1,'INSERT') allowed",['public.'+table])).rows[0].allowed,false);
  }
  await db.query('SET LOCAL ROLE authenticated');
  assert.equal((await db.query('SELECT count(*)::int n FROM public.empresas')).rows[0].n,1);
  assert.equal((await db.query("UPDATE public.empresas SET cidade='Own City' WHERE id=$1 RETURNING id",[own])).rowCount,1);
  assert.equal((await db.query("UPDATE public.empresas SET cidade='Foreign City' WHERE id=$1 RETURNING id",[foreign])).rowCount,0);
  assert.equal((await db.query("SELECT has_column_privilege('authenticated','public.empresas','nome','UPDATE') allowed")).rows[0].allowed,false);
 } finally { await db.query('ROLLBACK'); }
}
