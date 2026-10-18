import { supabase, isSupabaseConfigured } from '../../../lib/supabase';
import { requireCompanyId } from '../../../lib/company';
import type { ClienteEnderecoItem, NovoClienteEnderecoPayload } from '../types/clienteEndereco';
export async function salvarClienteEndereco(payload: NovoClienteEnderecoPayload): Promise<ClienteEnderecoItem> {
  if (!isSupabaseConfigured) throw new Error('Conexão não configurada.');
  const empresaId = await requireCompanyId();
  if (payload.empresa_id && payload.empresa_id !== empresaId) throw new Error('Empresa inválida.');
  const { data, error } = await supabase.rpc('salvar_cliente_endereco', { p_dados: {
    empresa_id: empresaId, nome_identificador: payload.nome_identificador,
    destinatario_padrao: payload.destinatario_padrao || null, endereco_completo: payload.endereco_completo,
    numero: '', bairro: '', cidade: '', cep: '', latitude: payload.coordenadas.lat, longitude: payload.coordenadas.lng,
    total_entregas_realizadas: 0, tipo_local: payload.tipo_local || 'condominio_horizontal',
    observacoes_acesso: payload.observacoes_acesso || null,
  } });
  if (error) throw new Error(error.message);
  const result = data as unknown as { sucesso: boolean; mensagem?: string; cliente?: ClienteEnderecoItem };
  if (!result?.sucesso || !result.cliente) throw new Error(result?.mensagem || 'O servidor não confirmou o endereço.');
  return result.cliente;
}
