import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, '..');

const MODULES_DIR = path.join(rootDir, 'supabase', 'modules-sql');
const FUNCTIONS_DIR = path.join(rootDir, 'supabase', 'functions-sql');
const OUTPUT_FILE = path.join(rootDir, 'supabase', 'schema.sql');

const FILE_ORDER = [
  // 1. Tabelas estruturais e Helpers de Autorização
  path.join(MODULES_DIR, '01_tables_core.sql'),
  path.join(MODULES_DIR, '01b_helpers.sql'),
  path.join(MODULES_DIR, '02_tables_vehicles.sql'),
  path.join(MODULES_DIR, '03_tables_logistics.sql'),

  // 2. Funções de negócio (RPCs)
  path.join(FUNCTIONS_DIR, 'fn_validar_completude_veiculo.sql'),
  path.join(FUNCTIONS_DIR, 'solicitar_acesso_empresa.sql'),
  path.join(FUNCTIONS_DIR, 'aprovar_solicitacao_motorista.sql'),
  path.join(FUNCTIONS_DIR, 'rejeitar_solicitacao_acesso.sql'),
  path.join(FUNCTIONS_DIR, 'suspender_acesso_membro.sql'),
  path.join(FUNCTIONS_DIR, 'reativar_acesso_membro.sql'),
  path.join(FUNCTIONS_DIR, 'alterar_papel_membro.sql'),
  path.join(FUNCTIONS_DIR, 'cadastrar_meu_veiculo.sql'),
  path.join(FUNCTIONS_DIR, 'anexar_documento_veiculo.sql'),
  path.join(FUNCTIONS_DIR, 'remover_documento_veiculo.sql'),
  path.join(FUNCTIONS_DIR, 'analisar_veiculo_motorista.sql'),
  path.join(FUNCTIONS_DIR, 'despachar_rota_transacional.sql'),
  path.join(FUNCTIONS_DIR, 'iniciar_rota.sql'),
  path.join(FUNCTIONS_DIR, 'concluir_rota.sql'),
  path.join(FUNCTIONS_DIR, 'registrar_conclusao_entrega.sql'),
  path.join(FUNCTIONS_DIR, 'obter_meu_status_acesso.sql'),
  path.join(FUNCTIONS_DIR, 'sincronizar_meu_perfil.sql'),
  path.join(FUNCTIONS_DIR, 'bootstrap_primeiro_gestor.sql'),

  // 3. Storage, Segurança e Grants
  path.join(MODULES_DIR, '04_storage.sql'),
  path.join(MODULES_DIR, '05_rls_policies.sql'),
  path.join(MODULES_DIR, '06_grants.sql'),
];

function buildSchema() {
  console.log('Compilando schema.sql a partir dos módulos SQL...');

  let output = `-- ==============================================================================
-- ENTREGA CONDO - MODELAGEM DE DADOS DO BANCO SUPABASE (GERADO DETERMINISTICAMENTE)
-- Gerado por: scripts/build_schema.js
-- Fonte: supabase/modules-sql/ e supabase/functions-sql/
-- Não edite este arquivo manualmente. Edite os módulos individuais correspondentes.
-- ==============================================================================

`;

  for (const filePath of FILE_ORDER) {
    if (!fs.existsSync(filePath)) {
      console.error(`Erro: Arquivo não encontrado: ${filePath}`);
      process.exit(1);
    }

    const relName = path.relative(rootDir, filePath).replace(/\\/g, '/');
    const content = fs.readFileSync(filePath, 'utf8').trim();

    output += `\n-- ------------------------------------------------------------------------------\n`;
    output += `-- MÓDULO: ${relName}\n`;
    output += `-- ------------------------------------------------------------------------------\n\n`;
    output += content + '\n';
  }

  // Realtime publication block
  output += `
-- ------------------------------------------------------------------------------
-- PUBLICAÇÃO REALTIME
-- ------------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.empresa_membros;
        ALTER PUBLICATION supabase_realtime ADD TABLE public.solicitacoes_acesso;
        ALTER PUBLICATION supabase_realtime ADD TABLE public.veiculos_motoristas;
        ALTER PUBLICATION supabase_realtime ADD TABLE public.veiculos_documentos;
        ALTER PUBLICATION supabase_realtime ADD TABLE public.rotas_planejadas;
        ALTER PUBLICATION supabase_realtime ADD TABLE public.entregas;
    END IF;
EXCEPTION WHEN OTHERS THEN
    NULL;
END $$;
`;

  // Bootstrap seed
  output += `
-- ------------------------------------------------------------------------------
-- DADOS INICIAIS BASE (EMPRESA MATRIZ)
-- ------------------------------------------------------------------------------
INSERT INTO public.empresas (id, nome, cnpj, codigo_convite, cidade, uf, ativa)
VALUES (
    '11111111-1111-1111-1111-111111111111',
    'EntregaCondo Matriz (Florianópolis)',
    '00.000.000/0001-00',
    'EC-FLN-01',
    'Florianópolis',
    'SC',
    TRUE
)
ON CONFLICT (codigo_convite) DO NOTHING;
`;

  fs.writeFileSync(OUTPUT_FILE, output, 'utf8');
  console.log(`schema.sql gerado com sucesso em: ${OUTPUT_FILE} (${output.length} bytes)`);
}

buildSchema();
