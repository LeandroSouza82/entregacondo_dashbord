export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export interface Database {
  public: {
    Tables: {
      entrega_comprovantes: {
        Row: {entrega_id:string;empresa_id:string;registrado_por:string;recebedor_tipo:string;recebedor_nome:string|null;observacao:string|null;foto_path:string|null;assinatura_path:string|null;chegada_em:string;concluida_em:string;duracao_segundos:number;latitude:number|null;longitude:number|null;created_at:string}
        Insert: {entrega_id:string;empresa_id:string;registrado_por:string;recebedor_tipo:string;chegada_em:string;concluida_em:string;duracao_segundos:number}
        Update: never
        Relationships: [{foreignKeyName:'entrega_comprovantes_entrega_id_fkey';columns:['entrega_id'];isOneToOne:true;referencedRelation:'entregas';referencedColumns:['id']}]
      }

      empresas: {
        Row: {
          id: string
          nome: string
          cnpj: string | null
          codigo_convite: string
          cidade: string
          uf: string
          ativa: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          nome: string
          cnpj?: string | null
          codigo_convite: string
          cidade?: string
          uf?: string
          ativa?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: Partial<Database['public']['Tables']['empresas']['Insert']>
        Relationships: []
      }
      perfis_usuarios: {
        Row: {
          id: string
          nome: string
          email: string
          telefone: string | null
          avatar_url: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id: string
          nome: string
          email: string
          telefone?: string | null
          avatar_url?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: Partial<Database['public']['Tables']['perfis_usuarios']['Insert']>
        Relationships: []
      }
      empresa_membros: {
        Row: {
          id: string
          empresa_id: string
          user_id: string
          papel: 'admin' | 'gestor' | 'motorista'
          status: 'pendente' | 'aprovado' | 'rejeitado' | 'suspenso'
          motorista_id: string | null
          motivo_decisao: string | null
          aprovado_por: string | null
          aprovado_em: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          empresa_id: string
          user_id: string
          papel?: 'admin' | 'gestor' | 'motorista'
          status?: 'pendente' | 'aprovado' | 'rejeitado' | 'suspenso'
          motorista_id?: string | null
          motivo_decisao?: string | null
          aprovado_por?: string | null
          aprovado_em?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: Partial<Database['public']['Tables']['empresa_membros']['Insert']>
        Relationships: []
      }
      solicitacoes_acesso: {
        Row: {
          id: string
          empresa_id: string
          user_id: string
          papel_solicitado: 'motorista'
          status: 'pendente' | 'aprovado' | 'rejeitado' | 'suspenso'
          motorista_vinculado_id: string | null
          motivo_decisao: string | null
          decidido_por: string | null
          decidido_em: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          empresa_id: string
          user_id: string
          papel_solicitado?: 'motorista'
          status?: 'pendente' | 'aprovado' | 'rejeitado' | 'suspenso'
          motorista_vinculado_id?: string | null
          motivo_decisao?: string | null
          decidido_por?: string | null
          decidido_em?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: Partial<Database['public']['Tables']['solicitacoes_acesso']['Insert']>
        Relationships: []
      }
      auditoria_acessos: {
        Row: {
          id: string
          empresa_id: string
          user_id: string
          acao: string
          status_anterior: string | null
          novo_status: string
          motorista_id: string | null
          motivo: string | null
          executado_por: string | null
          detalhes: Json
          created_at: string
        }
        Insert: {
          id?: string
          empresa_id: string
          user_id: string
          acao: string
          status_anterior?: string | null
          novo_status: string
          motorista_id?: string | null
          motivo?: string | null
          executado_por?: string | null
          detalhes?: Json
          created_at?: string
        }
        Update: Partial<Database['public']['Tables']['auditoria_acessos']['Insert']>
        Relationships: []
      }
      motoristas: {
        Row: {
          id: string
          empresa_id: string
          user_id: string | null
          nome: string
          telefone: string
          email: string | null
          veiculo_tipo?: 'moto' | 'carro' | 'caminhao' | string | null
          veiculo_modelo: string
          veiculo_placa: string
          status: 'disponivel' | 'em_rota' | 'pausado' | 'offline'
          ativo: boolean
          latitude_atual: number | null
          longitude_atual: number | null
          localizacao_atualizada_em?: string | null
          capacidade_max_pacotes: number
          avaliacao_media: number
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          empresa_id: string
          user_id?: string | null
          nome: string
          telefone: string
          email?: string | null
          veiculo_modelo: string
          veiculo_placa: string
          status?: 'disponivel' | 'em_rota' | 'pausado' | 'offline'
          ativo?: boolean
          latitude_atual?: number | null
          longitude_atual?: number | null
          capacidade_max_pacotes?: number
          avaliacao_media?: number
          created_at?: string
          updated_at?: string
        }
        Update: Partial<Database['public']['Tables']['motoristas']['Insert']>
        Relationships: []
      }
      clientes_enderecos: {
        Row: {
          id: string
          empresa_id: string
          nome_identificador: string
          whatsapp_cliente: string | null
          destinatario_padrao: string | null
          endereco_completo: string
          numero: string
          bairro: string
          cidade: string
          cep: string
          latitude: number
          longitude: number
          tempo_medio_minutos: number
          total_entregas_realizadas: number
          tipo_local: 'condominio_horizontal' | 'edificio_vertical' | 'comercial' | 'casa_rua'
          observacoes_acesso: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          empresa_id: string
          nome_identificador: string
          whatsapp_cliente?: string | null
          destinatario_padrao?: string | null
          endereco_completo: string
          numero: string
          bairro: string
          cidade: string
          cep: string
          latitude: number
          longitude: number
          tempo_medio_minutos?: number
          total_entregas_realizadas?: number
          tipo_local?: 'condominio_horizontal' | 'edificio_vertical' | 'comercial' | 'casa_rua'
          observacoes_acesso?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: Partial<Database['public']['Tables']['clientes_enderecos']['Insert']>
        Relationships: []
      }
      entregas: {
        Row: {
          id: string
          empresa_id: string
          codigo_rastreio: string
          cliente_endereco_id: string
          destinatario_nome: string
          destinatario_telefone: string | null
          unidade_apartamento: string | null
          status: 'pendente' | 'atribuida' | 'em_transito' | 'entregue' | 'tentativa_falha' | 'cancelada'
          prioridade: 'baixa' | 'normal' | 'alta' | 'urgente'
          tipo_tarefa: 'entrega' | 'coleta' | 'outros'
          descricao_outro: string | null
          peso_kg: number | null
          volumes_qtd: number
          motorista_id: string | null
          rota_id: string | null
          ordem_na_rota: number | null
          observacoes_gestor: string | null
          chegada_em: string | null
          data_hora_entrega: string | null
          janela_inicio: string | null
          janela_fim: string | null
          janela_data: string | null
          janela_inicio_em: string | null
          janela_fim_em: string | null
          coleta_origem_id: string | null
          tempo_atendimento_previsto_min: number
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          empresa_id: string
          codigo_rastreio: string
          cliente_endereco_id: string
          destinatario_nome: string
          destinatario_telefone?: string | null
          unidade_apartamento?: string | null
          status?: 'pendente' | 'atribuida' | 'em_transito' | 'entregue' | 'tentativa_falha' | 'cancelada'
          prioridade?: 'baixa' | 'normal' | 'alta' | 'urgente'
          tipo_tarefa?: 'entrega' | 'coleta' | 'outros'
          descricao_outro?: string | null
          peso_kg?: number | null
          volumes_qtd?: number
          motorista_id?: string | null
          rota_id?: string | null
          ordem_na_rota?: number | null
          observacoes_gestor?: string | null
          data_hora_entrega?: string | null
          janela_inicio?: string | null
          janela_fim?: string | null
          janela_data?: string | null
          coleta_origem_id?: string | null
          tempo_atendimento_previsto_min?: number
          created_at?: string
          updated_at?: string
        }
        Update: Partial<Database['public']['Tables']['entregas']['Insert']>
        Relationships: [
          { foreignKeyName: 'entregas_cliente_endereco_id_fkey'; columns: ['cliente_endereco_id']; isOneToOne: false; referencedRelation: 'clientes_enderecos'; referencedColumns: ['id'] },
          { foreignKeyName: 'entregas_coleta_origem_fk'; columns: ['empresa_id','coleta_origem_id']; isOneToOne: false; referencedRelation: 'entregas'; referencedColumns: ['empresa_id','id'] }
        ]
      }
      veiculos_motoristas: {
        Row: {
          id: string
          user_id: string
          empresa_id: string
          tipo_veiculo: 'moto' | 'carro'
          marca: string
          modelo: string
          placa: string
          compartimento: 'bau' | 'mochila' | 'bag' | null
          volume_litros: number | null
          tamanho_compartimento: 'pequeno' | 'medio' | 'grande' | null
          capacidade_kg: number | null
          status_analise: 'pendente' | 'aprovado' | 'rejeitado'
          motivo_rejeicao: string | null
          revisao: number
          analisado_por: string | null
          analisado_em: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          user_id: string
          empresa_id: string
          tipo_veiculo: 'moto' | 'carro'
          marca: string
          modelo: string
          placa: string
          compartimento?: 'bau' | 'mochila' | 'bag' | null
          volume_litros?: number | null
          tamanho_compartimento?: 'pequeno' | 'medio' | 'grande' | null
          capacidade_kg?: number | null
          status_analise?: 'pendente' | 'aprovado' | 'rejeitado'
          motivo_rejeicao?: string | null
          revisao?: number
          analisado_por?: string | null
          analisado_em?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: Partial<Database['public']['Tables']['veiculos_motoristas']['Insert']>
        Relationships: []
      }
      veiculos_documentos: {
        Row: {
          id: string
          veiculo_id: string
          user_id: string
          empresa_id: string
          tipo_documento: 'foto_veiculo' | 'crlv' | 'complementar'
          angulo_foto: 'frente' | 'lado_direito' | 'lado_esquerdo' | 'traseira' | null
          nome_arquivo: string
          storage_path: string
          mime_type: string
          tamanho_bytes: number
          status_analise: 'pendente' | 'aprovado' | 'rejeitado'
          motivo_rejeicao: string | null
          analisado_por: string | null
          analisado_em: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          veiculo_id: string
          user_id: string
          empresa_id: string
          tipo_documento: 'foto_veiculo' | 'crlv' | 'complementar'
          angulo_foto?: 'frente' | 'lado_direito' | 'lado_esquerdo' | 'traseira' | null
          nome_arquivo: string
          storage_path: string
          mime_type: string
          tamanho_bytes: number
          status_analise?: 'pendente' | 'aprovado' | 'rejeitado'
          motivo_rejeicao?: string | null
          analisado_por?: string | null
          analisado_em?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: Partial<Database['public']['Tables']['veiculos_documentos']['Insert']>
        Relationships: []
      }
      storage_limpeza_fila: {
        Row: {
          id: string
          bucket_id: string
          storage_path: string
          empresa_id: string
          user_id: string
          motivo: string
          status: 'reservado' | 'vinculado' | 'pendente' | 'em_processamento' | 'concluido' | 'falhou'
          tentativas: number
          max_tentativas: number
          ultimo_erro: string | null
          autorizado_em: string
          processado_em: string | null
          claim_token: string | null
          claimed_by: string | null
          lease_expires_at: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          bucket_id?: string
          storage_path: string
          empresa_id: string
          user_id: string
          motivo: string
          status?: 'reservado' | 'vinculado' | 'pendente' | 'em_processamento' | 'concluido' | 'falhou'
          tentativas?: number
          max_tentativas?: number
          ultimo_erro?: string | null
          autorizado_em?: string
          processado_em?: string | null
          claim_token?: string | null
          claimed_by?: string | null
          lease_expires_at?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: Partial<Database['public']['Tables']['storage_limpeza_fila']['Insert']>
        Relationships: []
      }
      historico_atendimentos: {
        Row: {
          id: string
          entrega_id: string
          cliente_endereco_id: string
          motorista_id: string
          tempo_portaria_espera_minutos: number
          tempo_deslocamento_interno_minutos: number
          tempo_total_minutos: number
          data_hora_chegada: string
          data_hora_conclusao: string
          sucesso: boolean
          motivo_falha: string | null
          created_at: string
        }
        Insert: {
          id?: string
          entrega_id: string
          cliente_endereco_id: string
          motorista_id: string
          tempo_portaria_espera_minutos?: number
          tempo_deslocamento_interno_minutos?: number
          tempo_total_minutos: number
          data_hora_chegada: string
          data_hora_conclusao: string
          sucesso?: boolean
          motivo_falha?: string | null
          created_at?: string
        }
        Update: Partial<Database['public']['Tables']['historico_atendimentos']['Insert']>
        Relationships: []
      }
      rotas_planejadas: {
        Row: {
          id: string
          empresa_id: string
          motorista_id: string
          idempotency_key: string
          payload_hash: string | null
          status: 'planejada' | 'em_execucao' | 'concluida' | 'cancelada'
          distancia_original_km: number
          tempo_original_minutos: number
          distancia_otimizada_km: number
          tempo_otimizado_minutos: number
          percentual_economia_km: number
          percentual_economia_tempo: number
          configuracao_navegacao: Json
          metricas_fonte: string | null
          metricas_atualizadas_em: string | null
          ordem_paradas_json: Json
          iniciada_em: string | null
          concluida_em: string | null
          created_at: string
        }
        Insert: {
          id?: string
          empresa_id: string
          motorista_id: string
          idempotency_key: string
          payload_hash?: string | null
          status?: 'planejada' | 'em_execucao' | 'concluida' | 'cancelada'
          distancia_original_km: number
          tempo_original_minutos: number
          distancia_otimizada_km: number
          tempo_otimizado_minutos: number
          percentual_economia_km: number
          percentual_economia_tempo: number
          metricas_fonte?: string | null
          metricas_atualizadas_em?: string | null
          ordem_paradas_json: Json
          iniciada_em?: string | null
          concluida_em?: string | null
          created_at?: string
        }
        Update: Partial<Database['public']['Tables']['rotas_planejadas']['Insert']>
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      iniciar_teste_empresa: {Args: {p_nome_empresa?: string | null}; Returns: Json}
      obter_minha_assinatura: {Args: {p_empresa_id: string}; Returns: Json}
      criar_compartilhamento_comprovante: {Args: {p_entrega_id:string;p_token:string;p_foto_url?:string|null;p_assinatura_url?:string|null}; Returns:Json}
      obter_comprovante_compartilhado: {Args: {p_token:string}; Returns:Json}
      revogar_compartilhamento_comprovante: {Args: {p_entrega_id:string}; Returns:Json}
      obter_capacidades_rotas: {Args: Record<PropertyKey, never>; Returns: Json}
      configurar_nome_empresa: {Args: {p_empresa_id: string; p_nome: string}; Returns: Json}
      obter_acompanhamento_cliente: {Args: {p_token: string}; Returns: Json}
      enviar_servicos_motorista: {Args: {p_dados:Json;p_plano_coletas?:Json};Returns:Json}
      enviar_pedidos_motorista: {Args: {p_dados:Json};Returns:Json}

      salvar_cliente_endereco: { Args: { p_dados: Json }; Returns: Json }
      excluir_cliente_endereco: { Args: { p_id: string }; Returns: Json }
      obter_comprovante_publico: { Args: { p_entrega_id: string }; Returns: Json }

      obter_meu_status_acesso: {
        Args: Record<PropertyKey, never>
        Returns: Json
      }
      solicitar_acesso_empresa: {
        Args: {
          p_codigo_convite: string
        }
        Returns: Json
      }
      cadastrar_meu_veiculo: {
        Args: {
          p_dados: Json
        }
        Returns: Json
      }
      analisar_veiculo_motorista: {
        Args: {
          p_veiculo_id: string
          p_aprovar: boolean
          p_revisao_esperada: number
          p_motivo_rejeicao?: string
        }
        Returns: Json
      }
      anexar_documento_veiculo: {
        Args: {
          p_veiculo_id: string
          p_tipo_documento: string
          p_nome_arquivo: string
          p_storage_path: string
          p_tamanho_bytes: number
          p_angulo_foto?: string | null
        }
        Returns: Json
      }
      remover_documento_veiculo: {
        Args: {
          p_documento_id: string
        }
        Returns: Json
      }
      fn_validar_autorizacao_condutor: {
        Args: {
          p_empresa_id: string
          p_user_id?: string
        }
        Returns: Json
      }
      fn_validar_completude_veiculo: {
        Args: {
          p_veiculo_id: string
        }
        Returns: Json
      }
      aprovar_solicitacao_motorista: {
        Args: {
          p_solicitacao_id: string
          p_motorista_id?: string | null
          p_criar_novo_motorista?: boolean
          p_nome_motorista?: string | null
          p_telefone_motorista?: string | null
          p_aprovar_veiculo?: boolean
          p_revisao_esperada_veiculo?: number | null
        }
        Returns: Json
      }
      registrar_limpeza_storage_executada: {
        Args: {
          p_fila_id: string
          p_claim_token: string
          p_sucesso: boolean
          p_erro?: string | null
        }
        Returns: Json
      }
      reservar_upload_evidencia: {
        Args: {
          p_empresa_id: string
          p_tipo_documento: string
          p_nome_arquivo: string
          p_angulo_foto?: string | null
        }
        Returns: Json
      }
      descartar_evidencia_temporaria: {
        Args: {
          p_storage_path: string
        }
        Returns: Json
      }
      reivindicar_itens_limpeza_storage: {
        Args: {
          p_limite?: number
          p_fila_id?: string | null
        }
        Returns: Json[]
      }
      retomar_limpeza_falha: {
        Args: {
          p_fila_id: string
        }
        Returns: Json
      }
      rejeitar_solicitacao_acesso: {
        Args: {
          p_solicitacao_id: string
          p_motivo: string
        }
        Returns: Json
      }
      suspender_acesso_membro: {
        Args: {
          p_membro_id: string
          p_motivo: string
        }
        Returns: Json
      }
      reativar_acesso_membro: {
        Args: {
          p_membro_id: string
        }
        Returns: Json
      }
      alterar_papel_membro: {
        Args: {
          p_membro_id: string
          p_novo_papel: string
        }
        Returns: Json
      }
      despachar_rota_transacional: {
        Args: {
          p_dados: Json
        }
        Returns: Json
      }
      iniciar_rota: {
        Args: {
          p_rota_id: string
        }
        Returns: Json
      }
      concluir_rota: {
        Args: {
          p_rota_id: string
        }
        Returns: Json
      }
      registrar_conclusao_entrega: {
        Args: {
          p_entrega_id: string
          p_sucesso: boolean
          p_motivo_falha?: string
          p_tempo_portaria?: number
          p_tempo_deslocamento?: number
          p_data_hora_chegada?: string
          p_data_hora_conclusao?: string
        }
        Returns: Json
      }
      bootstrap_primeiro_gestor: {
        Args: {
          p_email_gestor: string
          p_codigo_convite: string
          p_nome_empresa?: string
        }
        Returns: Json
      }
      sincronizar_meu_perfil: {
        Args: Record<PropertyKey, never>
        Returns: Json
      }
    }
  }
}
