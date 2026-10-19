import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const read=(p)=>fs.readFileSync(path.join(root,p),'utf8');
const file='supabase/migrations/20261018214102_secure_claims_and_operational_authorization.sql';
const table=read('supabase/modules-sql/04_storage.sql').match(/CREATE TABLE IF NOT EXISTS public.storage_limpeza_fila[\s\S]*?\n\);/)[0];
let sql='-- Gerado por scripts/build_security_migration.js a partir dos módulos canônicos.\nBEGIN;\n'+table+'\n'+
  'LOCK TABLE public.storage_limpeza_fila IN ACCESS EXCLUSIVE MODE;\n'+
  'ALTER TABLE public.storage_limpeza_fila ADD COLUMN IF NOT EXISTS claim_token UUID;\n'+
  'ALTER TABLE public.storage_limpeza_fila ADD COLUMN IF NOT EXISTS claimed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;\n'+
  'ALTER TABLE public.storage_limpeza_fila ADD COLUMN IF NOT EXISTS lease_expires_at TIMESTAMPTZ;\n'+
  read('supabase/modules-sql/04a_storage_constraints.sql')+'\n'+
  "UPDATE public.storage_limpeza_fila SET status = CASE WHEN tentativas >= max_tentativas THEN 'falhou' ELSE 'pendente' END, ultimo_erro = 'Tentativa legada sem token; recuperação exigida.', lease_expires_at = NULL WHERE status = 'em_processamento' AND (claim_token IS NULL OR lease_expires_at IS NULL);\n"+
  "DO $$ BEGIN IF EXISTS (SELECT 1 FROM public.veiculos_documentos GROUP BY storage_path HAVING count(*) > 1) THEN RAISE EXCEPTION 'Evidências legadas compartilham caminho; reconciliação necessária.'; END IF; END $$;\n"+
  "INSERT INTO public.storage_limpeza_fila (bucket_id,storage_path,empresa_id,user_id,motivo,status) SELECT 'veiculos-documentos',storage_path,empresa_id,user_id,'vinculo_legado','vinculado' FROM public.veiculos_documentos ON CONFLICT (storage_path) DO NOTHING;\n"+
  "DO $$ BEGIN IF EXISTS (SELECT 1 FROM public.veiculos_documentos vd JOIN public.storage_limpeza_fila f ON f.storage_path=vd.storage_path WHERE f.empresa_id IS DISTINCT FROM vd.empresa_id OR f.user_id IS DISTINCT FROM vd.user_id OR f.status NOT IN ('reservado','vinculado')) THEN RAISE EXCEPTION 'Vínculo legado conflita com proprietário, empresa ou descarte da evidência.'; END IF; END $$;\n"+
  "UPDATE public.storage_limpeza_fila f SET status='vinculado' WHERE f.status='reservado' AND EXISTS (SELECT 1 FROM public.veiculos_documentos vd WHERE vd.storage_path=f.storage_path);\n";
const currentPolicies=new Set();
const policyPattern=/CREATE\s+POLICY\s+"([^"]+)"\s+ON\s+([a-zA-Z0-9_.]+)/gi;
for(const p of ['04_storage.sql','05_rls_policies.sql']) for(const m of read('supabase/modules-sql/'+p).matchAll(policyPattern))currentPolicies.add(m[2]+'::'+m[1]);
const legacyPolicies=new Map();
for(const f of fs.readdirSync(path.join(root,'supabase/migrations')).filter(f=>f.endsWith('.sql')&&!file.endsWith(f))){
 for(const m of read('supabase/migrations/'+f).matchAll(policyPattern))if(!currentPolicies.has(m[2]+'::'+m[1]))legacyPolicies.set(m[2]+'::'+m[1],m);
}
for(const m of legacyPolicies.values())sql+='DROP POLICY IF EXISTS "'+m[1].replaceAll('"','""')+'" ON '+m[2]+';\n';
sql+=read('supabase/modules-sql/02a_vehicle_upgrade.sql')+'\n'+read('supabase/modules-sql/04_storage.sql')+'\n'+read('supabase/modules-sql/01b_helpers.sql')+'\n';
const first=['fn_validar_completude_veiculo.sql','fn_usuario_pode_operar_motorista.sql'];
const files=[...first,...fs.readdirSync(path.join(root,'supabase/functions-sql')).filter(f=>f.endsWith('.sql')&&!first.includes(f)).sort()];
for(const f of files)sql+='\n-- functions-sql/'+f+'\n'+read('supabase/functions-sql/'+f)+'\n';
sql+=read('supabase/modules-sql/05_rls_policies.sql')+'\n'+read('supabase/modules-sql/06_grants.sql')+'\nCOMMIT;\n';
fs.writeFileSync(path.join(root,file),sql);
console.log('Migração incremental gerada: '+file);
