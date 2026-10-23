// Isolated regression database; never connects to a Supabase project.
// Install @electric-sql/pglite in a temporary directory and set PGLITE_MODULE
// to its dist/index.js, or install it locally without saving dependencies.
import { readFileSync, readdirSync } from 'node:fs';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const root = new URL('../', import.meta.url);
const migrations = new URL('supabase/migrations/', root);
const migration = readdirSync(migrations).find(n => n.endsWith('_align_delivery_completion_statistics.sql'));
assert.ok(migration);
const sql = readFileSync(new URL(migration, migrations), 'utf8');
const db = new PGlite();
const address = '10000000-0000-0000-0000-000000000001';
const driver = '20000000-0000-0000-0000-000000000001';
const company = '30000000-0000-0000-0000-000000000001';
const user = '40000000-0000-0000-0000-000000000001';
const stop = n => `50000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
try {
  await db.exec(`
    create role anon; create role authenticated;
    create schema auth;
    create function auth.uid() returns uuid language sql as
      $$ select '${user}'::uuid $$;
    create function public.fn_usuario_pode_operar_motorista(uuid,uuid)
      returns boolean language sql as $$ select true $$;
    create table public.clientes_enderecos (id uuid primary key);
    create table public.motoristas (id uuid,empresa_id uuid,user_id uuid);
    create table public.entregas (
      id uuid primary key,empresa_id uuid,motorista_id uuid,
      cliente_endereco_id uuid,status varchar(30),data_hora_entrega timestamptz,
      updated_at timestamptz);
    create table public.historico_atendimentos (
      id uuid default gen_random_uuid(),entrega_id uuid,cliente_endereco_id uuid,
      motorista_id uuid,tempo_portaria_espera_minutos numeric,
      tempo_deslocamento_interno_minutos numeric,tempo_total_minutos numeric,
      data_hora_chegada timestamptz,data_hora_conclusao timestamptz,
      sucesso boolean,motivo_falha text);
    insert into clientes_enderecos values ('${address}');
    insert into motoristas values ('${driver}','${company}','${user}');
    insert into historico_atendimentos (cliente_endereco_id,tempo_total_minutos)
      values ('${address}',20);
  `);
  await db.exec(sql);
  let row = (await db.query('select * from clientes_enderecos')).rows[0];
  assert.equal(Number(row.tempo_medio_minutos), 20);
  assert.equal(row.total_entregas_realizadas, 1);
  // Reruns preserve values already present in an installation.
  await db.exec('update clientes_enderecos set tempo_medio_minutos=25');
  await db.exec(sql);
  row = (await db.query('select * from clientes_enderecos')).rows[0];
  assert.equal(Number(row.tempo_medio_minutos), 25);
  for (let n = 1; n <= 3; n++) {
    await db.query('insert into entregas values ($1,$2,$3,$4,$5,null,null)',
      [stop(n), company, driver, address, 'em_transito']);
  }
  const complete = async (n, success, reason = null) =>
    (await db.query(`select registrar_conclusao_entrega(
      $1::uuid,$2::boolean,$3::text,0,0,
      '2026-10-19T10:00:00Z','2026-10-19T10:10:00Z') as result`,
      [stop(n), success, reason])).rows[0].result;
  assert.equal((await complete(1,true)).sucesso, true);
  row = (await db.query('select * from clientes_enderecos')).rows[0];
  assert.equal(row.total_entregas_realizadas, 2);
  assert.equal(Number(row.tempo_medio_minutos), 17.5);
  assert.equal((await complete(1,true)).codigo, 'ENTREGA_JA_REGISTRADA');
  assert.equal((await db.query('select count(*)::int as n from historico_atendimentos')).rows[0].n, 2);
  assert.equal((await complete(1,false,'Ausente')).codigo, 'TRANSICAO_INVALIDA');
  assert.equal((await complete(2,false,'   ')).codigo, 'MOTIVO_OBRIGATORIO');
  assert.equal((await db.query('select status from entregas where id=$1',[stop(2)])).rows[0].status, 'em_transito');
  assert.equal((await complete(2,false,'Cliente ausente')).sucesso, true);
  assert.equal((await db.query('select motivo_falha from historico_atendimentos where entrega_id=$1',[stop(2)])).rows[0].motivo_falha, 'Cliente ausente');
  await db.exec(`create or replace function public.fn_usuario_pode_operar_motorista(uuid,uuid)
    returns boolean language sql as $$ select false $$;`);
  assert.equal((await complete(3,true)).codigo, 'ACESSO_NEGADO');
  assert.equal((await db.query('select status from entregas where id=$1',[stop(3)])).rows[0].status, 'em_transito');
  console.log('PASS: missing columns, history backfill, rerun preservation, completion, retry, conflicting outcome, required reason, failure history and access denial.');
} catch (error) {
  console.error(Object.fromEntries(Object.entries(error).filter(([k]) => !['query','params','queryOptions'].includes(k))));
  process.exitCode = 1;
} finally {
  await db.close();
}
