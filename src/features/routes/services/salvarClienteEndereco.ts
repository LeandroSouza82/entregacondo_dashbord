import { normalizeCustomerWhatsApp } from './customerContact';
import { coordenadasValidas, erroLocalizacaoEndereco, cidadeDoEndereco } from './addressCoordinates';
import { supabase, isSupabaseConfigured } from '../../../lib/supabase';
import { requireCompanyId, hasActiveSupabaseSession, isDemoModeActive } from '../../../lib/company';
import type { ClienteEnderecoItem, NovoClienteEnderecoPayload } from '../types/clienteEndereco';

export async function salvarClienteEndereco(payload: NovoClienteEnderecoPayload): Promise<ClienteEnderecoItem> {
  if (!isSupabaseConfigured) throw new Error('Conexão não configurada.');
  const empresaId = await requireCompanyId();
  if (payload.empresa_id && payload.empresa_id !== empresaId) throw new Error('Empresa inválida.');

  const whatsapp = payload.whatsapp_cliente === undefined ? undefined : normalizeCustomerWhatsApp(payload.whatsapp_cliente || '');
  const nomeFinal = (payload.label || payload.nome_identificador || '').trim() ||
                    (payload.destinatario_padrao || '').trim() ||
                    (payload.full_address || payload.endereco_completo || '').split(',')[0].trim() ||
                    'Condomínio / Cliente';

  const enderecoFinal = (payload.full_address || payload.endereco_completo || '').trim() || 'Endereço informado';
  const cidade = cidadeDoEndereco(enderecoFinal);
  const cep = enderecoFinal.match(/\b\d{5}-?\d{3}\b/)?.[0] || '';

  const latRaw = typeof payload.coordenadas?.lat === 'number' ? payload.coordenadas.lat : payload.lat;
  const lngRaw = typeof payload.coordenadas?.lng === 'number' ? payload.coordenadas.lng : payload.lng;

  const coordinates = { lat: latRaw, lng: lngRaw };
  if (!coordenadasValidas(coordinates)) throw new Error(erroLocalizacaoEndereco);
  const { lat, lng } = coordinates;

  if (!(await hasActiveSupabaseSession())) {
    if (isDemoModeActive()) {
      const now = new Date().toISOString();
      return {
        id: crypto.randomUUID(),
        empresa_id: empresaId,
        nome_identificador: nomeFinal,
        destinatario_padrao: payload.destinatario_padrao || null,
        whatsapp_cliente: whatsapp || null,
        endereco_completo: enderecoFinal,
        numero: 'S/N',
        bairro: 'Região de Entrega',
        cidade,
        cep,
        latitude: lat,
        longitude: lng,
        tempo_medio_minutos: 15,
        total_entregas_realizadas: 0,
        tipo_local: payload.tipo_local || 'condominio_horizontal',
        observacoes_acesso: payload.observacoes_acesso || null,
        created_at: now,
      };
    }
    throw new Error('Usuário não autenticado.');
  }

  const { data, error } = await supabase.rpc('salvar_cliente_endereco', {
    p_dados: {
      empresa_id: empresaId,
      nome_identificador: nomeFinal,
      label: nomeFinal,
      nome: nomeFinal,
      nome_cliente: nomeFinal,
      cliente_nome: nomeFinal,
      condominio: nomeFinal,
      destinatario_padrao: payload.destinatario_padrao || null,
      ...(whatsapp !== undefined ? {whatsapp_cliente: whatsapp || null} : {}),
      endereco_completo: enderecoFinal,
      full_address: enderecoFinal,
      endereco: enderecoFinal,
      logradouro: enderecoFinal,
      numero: '',
      bairro: '',
      cidade,
      cep,
      latitude: lat,
      lat: lat,
      longitude: lng,
      lng: lng,
      place_id: payload.place_id || null,
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
