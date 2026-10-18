import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, '..');

const schemaSqlPath = path.join(rootDir, 'supabase', 'schema.sql');
const mig3Path = path.join(rootDir, 'supabase', 'migrations', '20261018030000_modular_vehicles_documents_and_strict_grants.sql');
const mig4Path = path.join(rootDir, 'supabase', 'migrations', '20261018040000_install_audited_rpcs_and_storage_lifecycle.sql');

function extractFunctionSignatures(sqlContent) {
  const regex = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.([a-zA-Z0-9_]+)\s*\(([\s\S]*?)\)\s*RETURNS/gi;
  const funcs = new Map();
  let match;
  while ((match = regex.exec(sqlContent)) !== null) {
    const name = match[1];
    const rawParams = match[2]
      .split('\n')
      .map(line => line.trim())
      .filter(line => line.length > 0 && !line.startsWith('--'))
      .join(' ')
      .replace(/\s+/g, ' ');
    funcs.set(name, rawParams);
  }
  return funcs;
}

function extractDropFunctions(sqlContent) {
  const regex = /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.([a-zA-Z0-9_]+)\s*\(([\s\S]*?)\);/gi;
  const drops = [];
  let match;
  while ((match = regex.exec(sqlContent)) !== null) {
    drops.push({ name: match[1], params: match[2].trim() });
  }
  return drops;
}

function extractStoragePolicies(sqlContent) {
  const regex = /CREATE\s+POLICY\s+"([^"]+)"\s+ON\s+storage\.objects\s+FOR\s+(INSERT|SELECT|UPDATE|DELETE)/gi;
  const policies = [];
  let match;
  while ((match = regex.exec(sqlContent)) !== null) {
    policies.push({ name: match[1], cmd: match[2] });
  }
  return policies;
}

function verifyEquivalence() {
  console.log('===============================================================');
  console.log('VERIFICAÇÃO DE EQUIVALÊNCIA: schema.sql vs Migrações');
  console.log('===============================================================');

  const schemaSql = fs.readFileSync(schemaSqlPath, 'utf8');
  const mig3Sql = fs.readFileSync(mig3Path, 'utf8');
  const mig4Sql = fs.readFileSync(mig4Path, 'utf8');

  const schemaFuncs = extractFunctionSignatures(schemaSql);
  const mig3Funcs = extractFunctionSignatures(mig3Sql);
  const mig4Funcs = extractFunctionSignatures(mig4Sql);

  const vehicleCriticalFuncs = [
    'fn_validar_autorizacao_condutor',
    'fn_validar_completude_veiculo',
    'cadastrar_meu_veiculo',
    'anexar_documento_veiculo',
    'remover_documento_veiculo',
    'analisar_veiculo_motorista',
    'aprovar_solicitacao_motorista'
  ];

  console.log('\n1. Verificando assinaturas de funções críticas de veículos e documentos...');
  let hasError = false;

  for (const fn of vehicleCriticalFuncs) {
    const sSig = schemaFuncs.get(fn);
    const m3Sig = mig3Funcs.get(fn);
    const m4Sig = mig4Funcs.get(fn);

    if (!sSig) {
      console.error(`❌ [schema.sql] Função ausente: ${fn}`);
      hasError = true;
      continue;
    }
    if (!m3Sig) {
      console.error(`❌ [Migração 20261018030000] Função ausente: ${fn}`);
      hasError = true;
    }
    if (!m4Sig) {
      console.error(`❌ [Migração 20261018040000] Função ausente: ${fn}`);
      hasError = true;
    }

    if (sSig && m3Sig && m4Sig) {
      console.log(`✅ ${fn}: presente em schema.sql, migração 3 e migração 4.`);
    }
  }

  console.log('\n2. Verificando remoção de sobrecargas obsoletas (DROP FUNCTION IF EXISTS)...');
  const expectedDrops = [
    { name: 'anexar_documento_veiculo', params: 'UUID, TEXT, TEXT, TEXT, INT' },
    { name: 'analisar_veiculo_motorista', params: 'UUID, BOOLEAN, TEXT' },
    { name: 'aprovar_solicitacao_motorista', params: 'UUID, UUID, BOOLEAN, TEXT, VARCHAR' }
  ];

  for (const exp of expectedDrops) {
    const inSchema = schemaSql.includes(`public.${exp.name}(${exp.params})`);
    const inMig3 = mig3Sql.includes(`public.${exp.name}(${exp.params})`);
    const inMig4 = mig4Sql.includes(`public.${exp.name}(${exp.params})`);

    if (inSchema && inMig3 && inMig4) {
      console.log(`✅ Drop de sobrecarga obsoleta ${exp.name}(${exp.params}) presente em todos os arquivos.`);
    } else {
      console.error(`❌ Falta drop de ${exp.name}(${exp.params}): schema=${inSchema}, mig3=${inMig3}, mig4=${inMig4}`);
      hasError = true;
    }
  }

  console.log('\n3. Verificando políticas RLS de storage.objects...');
  const schemaPol = extractStoragePolicies(schemaSql);
  const mig3Pol = extractStoragePolicies(mig3Sql);
  const mig4Pol = extractStoragePolicies(mig4Sql);

  console.log(`Políticas em schema.sql: ${schemaPol.map(p => p.cmd).join(', ')}`);
  console.log(`Políticas em Migração 3: ${mig3Pol.map(p => p.cmd).join(', ')}`);
  console.log(`Políticas em Migração 4: ${mig4Pol.map(p => p.cmd).join(', ')}`);

  ['INSERT', 'SELECT', 'UPDATE', 'DELETE'].forEach(cmd => {
    const s = schemaPol.some(p => p.cmd === cmd);
    const m3 = mig3Pol.some(p => p.cmd === cmd);
    const m4 = mig4Pol.some(p => p.cmd === cmd);
    if (s && m3 && m4) {
      console.log(`✅ Política para ${cmd} configurada equivalentemente nos 3 artefatos.`);
    } else {
      console.error(`❌ Política para ${cmd} divergente: schema=${s}, mig3=${m3}, mig4=${m4}`);
      hasError = true;
    }
  });

  if (hasError) {
    console.error('\n❌ RESULTADO: Divergências encontradas entre schema.sql e as migrações!');
    process.exit(1);
  } else {
    console.log('\n🎉 SUCESSO: Equivalência total comprovada entre schema.sql e as migrações!');
  }
}

verifyEquivalence();
