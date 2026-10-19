import { supabase, isSupabaseConfigured } from '../../../lib/supabase';
import { requireCompanyId } from '../../../lib/company';
import type { ClienteEnderecoItem, NovoClienteEnderecoPayload } from '../types/clienteEndereco';

export async function salvarClienteEndereco(payload: NovoClienteEnderecoPayload): Promise<ClienteEnderecoItem> {
  if (!isSupabaseConfigured) throw new Error('Conexão não configurada.');
  const empresaId = await requireCompanyId();
  if (payload.empresa_id && payload.empresa_id !== empresaId) throw new Error('Empresa inválida.');

  const nomeFinal = (payload.nome_identificador || '').trim() ||
                    (payload.destinatario_padrao || '').trim() ||
                    (payload.endereco_completo || '').split(',')[0].trim() ||
                    'Condomínio / Cliente';

  const enderecoFinal = (payload.endereco_completo || '').trim() || 'Endereço informado';

  const lat = typeof payload.coordenadas?.lat === 'number' && !isNaN(payload.coordenadas.lat)
    ? payload.coordenadas.lat
    : -27.5954;
  const lng = typeof payload.coordenadas?.lng === 'number' && !isNaN(payload.coordenadas.lng)
    ? payload.coordenadas.lng
    : -48.5480;

  const { data, error } = await supabase.rpc('salvar_cliente_endereco', {
    p_dados: {
      empresa_id: empresaId,
      nome_identificador: nomeFinal,
      nome: nomeFinal,
      nome_cliente: nomeFinal,
      cliente_nome: nomeFinal,
      condominio: nomeFinal,
      destinatario_padrao: payload.destinatario_padrao || null,
      endereco_completo: enderecoFinal,
      endereco: enderecoFinal,
      logradouro: enderecoFinal,
      numero: '',
      bairro: '',
      cidade: 'Florianópolis',
      cep: '88000-000',
      latitude: lat,
      lat: lat,
      longitude: lng,
      lng: lng,
      total_entregas_realizadas: 0,
      tempo_medio_atendimento_min: 15,
      tempo_medio_minutos: 15,
      tipo_local: payload.tipo_local || 'condominio_horizontal',
      observacoes_acesso: payload.observacoes_acesso || null,
      complemento: payload.observacoes_acesso || null,
      bloco_apartamento: payload.destinatario_padrao || null,
    },
  });

  if (error) throw new Error(error.message);

  const raw = data as any;
  const cliente = raw?.cliente || (raw?.id ? raw : null);
  if (!cliente) {
    throw new Error(raw?.mensagem || 'O servidor não confirmou o endereço.');
  }

  return cliente as ClienteEnderecoItem;
}
