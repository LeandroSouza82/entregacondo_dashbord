import { supabase, isSupabaseConfigured } from '../../../lib/supabase';
import type { ClienteEnderecoItem, NovoClienteEnderecoPayload } from '../types/clienteEndereco';
import { registrarEnderecoNoCacheLocal } from './buscarClientesEnderecos';

export async function salvarClienteEndereco(
  payload: NovoClienteEnderecoPayload
): Promise<ClienteEnderecoItem> {
  const novoItem: ClienteEnderecoItem = {
    id: crypto.randomUUID(),
    empresa_id: payload.empresa_id,
    nome_identificador: payload.nome_identificador,
    destinatario_padrao: payload.destinatario_padrao || null,
    endereco_completo: payload.endereco_completo,
    latitude: payload.coordenadas.lat,
    longitude: payload.coordenadas.lng,
    tempo_medio_minutos: 15,
    total_entregas_realizadas: 1,
    tipo_local: payload.tipo_local || 'condominio_horizontal',
    observacoes_acesso: payload.observacoes_acesso || null,
  };

  // 1. Persistir no Supabase se disponível
  if (isSupabaseConfigured && supabase) {
    try {
      const { data, error } = await supabase
        .from('clientes_enderecos')
        .insert({
          empresa_id: payload.empresa_id || '11111111-1111-1111-1111-111111111111',
          nome_identificador: payload.nome_identificador,
          destinatario_padrao: payload.destinatario_padrao || null,
          endereco_completo: payload.endereco_completo,
          numero: 'S/N',
          bairro: 'Geral',
          cidade: 'Florianópolis',
          cep: '88000-000',
          latitude: payload.coordenadas.lat,
          longitude: payload.coordenadas.lng,
          tempo_medio_minutos: 15,
          total_entregas_realizadas: 1,
          tipo_local: payload.tipo_local || 'condominio_horizontal',
          observacoes_acesso: payload.observacoes_acesso || null,
        })
        .select()
        .single();

      if (!error && data) {
        const itemPersistido: ClienteEnderecoItem = {
          id: data.id,
          empresa_id: data.empresa_id,
          nome_identificador: data.nome_identificador,
          destinatario_padrao: data.destinatario_padrao,
          endereco_completo: data.endereco_completo,
          latitude: Number(data.latitude),
          longitude: Number(data.longitude),
          tempo_medio_minutos: Number(data.tempo_medio_minutos),
          total_entregas_realizadas: data.total_entregas_realizadas || 1,
          tipo_local: data.tipo_local,
          observacoes_acesso: data.observacoes_acesso,
        };
        registrarEnderecoNoCacheLocal(itemPersistido);
        return itemPersistido;
      }
    } catch (err) {
      console.warn('Persistência no Supabase falhou, guardando no cache da sessão:', err);
    }
  }

  // 2. Fallback: Registrar no cache local da sessão para que próximas buscas o encontrem
  registrarEnderecoNoCacheLocal(novoItem);
  return novoItem;
}
