import { requireCompanyId } from '../../../lib/company';
import { supabase, isSupabaseConfigured } from '../../../lib/supabase';
import type { SolicitacaoAcessoItem, MotoristaFrotaItem } from '../types/accessApproval';
import type { VeiculoDeclarado } from '../../vehicles/types/vehicle';
import type { DocumentoVeiculoItem } from '../../vehicle-documents/types/vehicleDocument';

export interface ResultadoConsultaSolicitacoes {
  solicitacoes: SolicitacaoAcessoItem[];
  motoristas: MotoristaFrotaItem[];
}

export async function obterSolicitacoesAcesso(): Promise<ResultadoConsultaSolicitacoes> {
  if (!isSupabaseConfigured) {
    throw new Error('Supabase não configurado. Verifique as variáveis de ambiente.');
  }

  const companyId = await requireCompanyId();
  const company = await supabase.from('empresas').select('nome').eq('id', companyId).single();
  if (company.error) throw new Error(company.error.message);
  // 1. Busca solicitações de acesso
  const { data: solData, error: solErr } = await supabase
    .from('solicitacoes_acesso')
    .select(`
      id,
      empresa_id,
      user_id,
      papel_solicitado,
      status,
      motorista_vinculado_id,
      motivo_decisao,
      decidido_em,
      created_at
    `)
    .eq('empresa_id', companyId)
    .order('created_at', { ascending: false });

  if (solErr) {
    throw new Error(`Falha ao consultar solicitações: ${solErr.message}`);
  }

  // 2. Busca perfis, veículos, documentos e motoristas da empresa em paralelo
  const [perfisRes, veiculosRes, docsRes, motoristasRes] = await Promise.all([
    supabase.from('perfis_usuarios').select('id, nome, email, telefone, avatar_url'),
    supabase.from('veiculos_motoristas').select('*').eq('empresa_id', companyId),
    supabase.from('veiculos_documentos').select('*').eq('empresa_id', companyId),
    supabase.from('motoristas').select('*').eq('empresa_id', companyId),
  ]);

  for (const result of [perfisRes, veiculosRes, docsRes, motoristasRes]) if (result.error) throw new Error(result.error.message);
  const perfis = (perfisRes.data || []) as Array<{ id: string; nome: string; email: string; telefone: string | null; avatar_url: string | null }>;
  const veiculos = (veiculosRes.data || []) as VeiculoDeclarado[];
  const documentos = (docsRes.data || []) as DocumentoVeiculoItem[];
  const motoristas = (motoristasRes.data || []) as MotoristaFrotaItem[];

  const solicitacoes: SolicitacaoAcessoItem[] = (solData || []).map((sol) => {
    const perfil = perfis.find((p) => p.id === sol.user_id);
    const mot = motoristas.find((m) => m.id === sol.motorista_vinculado_id);
    const veic = veiculos.find((v) => v.user_id === sol.user_id);
    const docs = veic ? documentos.filter((d) => d.veiculo_id === veic.id) : [];

    return {
      id: sol.id,
      empresa_id: sol.empresa_id,
      empresa_nome: company.data.nome,
      user_id: sol.user_id,
      usuario_nome: perfil?.nome || `Condutor (${sol.user_id.slice(0, 8)})`,
      usuario_email: perfil?.email || 'e-mail não disponível',
      usuario_telefone: perfil?.telefone,
      usuario_avatar: perfil?.avatar_url,
      papel_solicitado: 'motorista',
      status: sol.status as SolicitacaoAcessoItem['status'],
      motorista_vinculado_id: sol.motorista_vinculado_id,
      motorista_nome: mot?.nome,
      motorista_veiculo: mot?.veiculo_modelo,
      motorista_placa: mot?.veiculo_placa,
      veiculo_declarado: veic || null,
      documentos: docs,
      motivo_decisao: sol.motivo_decisao,
      decidido_em: sol.decidido_em,
      created_at: sol.created_at,
    };
  });

  return { solicitacoes, motoristas };
}
