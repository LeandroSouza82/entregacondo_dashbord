import React, { useState } from 'react';
import { UserCheck, X, PlusCircle, Link as LinkIcon, AlertCircle, FileText } from 'lucide-react';
import type { SolicitacaoAcessoItem, MotoristaFrotaItem } from '../types/accessApproval';
import { CartaoVeiculoDeclarado } from '../../vehicles/components/CartaoVeiculoDeclarado';
import type { DocumentoVeiculoItem } from '../../vehicle-documents/types/vehicleDocument';

interface ModalAprovarMotoristaProps {
  solicitacao: SolicitacaoAcessoItem;
  motoristasDisponiveis: MotoristaFrotaItem[];
  carregando: boolean;
  onConfirmar: (dados: {
    solicitacaoId: string;
    criarNovoMotorista: boolean;
    motoristaId?: string | null;
    nomeMotorista?: string;
    telefoneMotorista?: string;
    revisaoEsperadaVeiculo?: number | null;
  }) => Promise<void>;
  onFechar: () => void;
  onVerDocumento: (doc: DocumentoVeiculoItem) => void;
}

export const ModalAprovarMotorista: React.FC<ModalAprovarMotoristaProps> = ({
  solicitacao,
  motoristasDisponiveis,
  carregando,
  onConfirmar,
  onFechar,
  onVerDocumento,
}) => {
  // Modo de aprovação: 'criar_novo' (Opção A) ou 'vincular_existente' (Opção B)
  const [modoAprovacao, setModoAprovacao] = useState<'criar_novo' | 'vincular_existente'>('criar_novo');
  const [motoristaSelecionadoId, setMotoristaSelecionadoId] = useState<string>('');
  const [nomeCustomizado, setNomeCustomizado] = useState(solicitacao.usuario_nome);
  const [telefoneCustomizado, setTelefoneCustomizado] = useState(solicitacao.usuario_telefone || '');

  const motoristasFiltrados = motoristasDisponiveis.filter(
    (m) => !m.user_id || m.user_id === solicitacao.user_id
  );

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (modoAprovacao === 'vincular_existente' && !motoristaSelecionadoId) {
      return;
    }

    await onConfirmar({
      solicitacaoId: solicitacao.id,
      criarNovoMotorista: modoAprovacao === 'criar_novo',
      motoristaId: modoAprovacao === 'vincular_existente' ? motoristaSelecionadoId : null,
      nomeMotorista: nomeCustomizado,
      telefoneMotorista: telefoneCustomizado,
      revisaoEsperadaVeiculo: solicitacao.veiculo_declarado?.revisao ?? null,
    });
  };

  return (
    <div className="fixed inset-0 z-50 bg-[#0F1B2D]/60 backdrop-blur-xs flex items-center justify-center p-4 animate-fadeIn">
      <div className="bg-white rounded-2xl max-w-xl w-full border border-[#CBD5E1] shadow-2xl p-6 space-y-5 animate-scaleUp max-h-[92vh] overflow-y-auto">
        {/* Cabeçalho */}
        <div className="flex items-center justify-between pb-3 border-b border-slate-100">
          <div className="flex items-center gap-2.5">
            <div className="w-9 h-9 rounded-xl bg-emerald-100 text-emerald-800 flex items-center justify-center">
              <UserCheck className="w-5 h-5" />
            </div>
            <div>
              <h3 className="font-extrabold text-base text-[#0F1B2D] m-0">Aprovação de Motorista</h3>
              <p className="text-xs text-[#516074] m-0">Conceder acesso operacional seguro às rotas</p>
            </div>
          </div>
          <button
            type="button"
            onClick={onFechar}
            className="text-slate-400 hover:text-slate-600 p-1 rounded-lg cursor-pointer"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Dados da Conta Solicitante */}
        <div className="p-3.5 rounded-xl bg-slate-50 border border-slate-200 text-xs space-y-1">
          <div className="flex justify-between">
            <span className="text-slate-500 font-medium">Nome na Autenticação:</span>
            <span className="font-bold text-[#0F1B2D]">{solicitacao.usuario_nome}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-slate-500 font-medium">E-mail:</span>
            <span className="font-bold text-[#0F1B2D]">{solicitacao.usuario_email}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-slate-500 font-medium">Empresa Solicitada:</span>
            <span className="font-bold text-[#0F1B2D]">{solicitacao.empresa_nome}</span>
          </div>
        </div>

        {/* Veículo Declarado pelo Condutor */}
        <div className="space-y-2">
          <label className="block text-xs font-bold text-[#0F1B2D]">
            Veículo Declarado no Aplicativo Móvel
          </label>
          <CartaoVeiculoDeclarado veiculo={solicitacao.veiculo_declarado} />
        </div>

        {/* Anexos e Documentos */}
        {solicitacao.documentos && solicitacao.documentos.length > 0 && (
          <div className="space-y-1.5 p-3 rounded-xl bg-slate-50 border border-slate-200">
            <span className="text-xs font-bold text-[#0F1B2D] flex items-center gap-1.5">
              <FileText className="w-3.5 h-3.5 text-[#1D4ED8]" />
              Evidências Anexadas ({solicitacao.documentos.length})
            </span>
            <div className="flex flex-wrap gap-2 pt-1">
              {solicitacao.documentos.map((doc) => (
                <button
                  key={doc.id}
                  type="button"
                  onClick={() => onVerDocumento(doc)}
                  className="px-2.5 py-1 rounded-lg bg-white border border-slate-200 text-[11px] font-semibold text-slate-700 hover:border-[#1D4ED8] hover:text-[#1D4ED8] transition-colors flex items-center gap-1 cursor-pointer"
                >
                  <span>{doc.tipo_documento === 'foto_veiculo' ? '📷 Foto' : '📄 ' + doc.nome_arquivo}</span>
                </button>
              ))}
            </div>
          </div>
        )}

        {/* Seletor de Opção de Homologação */}
        <form onSubmit={handleSubmit} className="space-y-4 pt-1">
          <div className="space-y-2">
            <label className="block text-xs font-bold text-[#0F1B2D]">
              Como você deseja aprovar esta conta? <span className="text-red-500">*</span>
            </label>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
              {/* Opção A: Criar Novo */}
              <button
                type="button"
                onClick={() => setModoAprovacao('criar_novo')}
                className={`p-3 rounded-xl border text-left transition-all cursor-pointer ${
                  modoAprovacao === 'criar_novo'
                    ? 'border-emerald-600 bg-emerald-50/50 ring-2 ring-emerald-500/20'
                    : 'border-slate-200 hover:border-slate-300 bg-white'
                }`}
              >
                <div className="flex items-center gap-2 font-bold text-xs text-[#0F1B2D]">
                  <PlusCircle className={`w-4 h-4 ${modoAprovacao === 'criar_novo' ? 'text-emerald-600' : 'text-slate-400'}`} />
                  <span>Criar Novo Cadastro</span>
                </div>
                <p className="text-[11px] text-slate-500 mt-1 m-0">
                  Gera um motorista novo na frota a partir dos dados reais e veículo desta solicitação.
                </p>
              </button>

              {/* Opção B: Vincular Existente */}
              <button
                type="button"
                onClick={() => setModoAprovacao('vincular_existente')}
                className={`p-3 rounded-xl border text-left transition-all cursor-pointer ${
                  modoAprovacao === 'vincular_existente'
                    ? 'border-[#1D4ED8] bg-blue-50/50 ring-2 ring-[#1D4ED8]/20'
                    : 'border-slate-200 hover:border-slate-300 bg-white'
                }`}
              >
                <div className="flex items-center gap-2 font-bold text-xs text-[#0F1B2D]">
                  <LinkIcon className={`w-4 h-4 ${modoAprovacao === 'vincular_existente' ? 'text-[#1D4ED8]' : 'text-slate-400'}`} />
                  <span>Vincular a Existente</span>
                </div>
                <p className="text-[11px] text-slate-500 mt-1 m-0">
                  Associa a um registro já cadastrado na frota da mesma pessoa que esteja livre.
                </p>
              </button>
            </div>
          </div>

          {/* Campos específicos da Opção A */}
          {modoAprovacao === 'criar_novo' && (
            <div className="p-3 bg-slate-50 rounded-xl border border-slate-200 space-y-2">
              <span className="text-[11px] font-bold text-slate-700 block">
                Confirmar Dados Operacionais do Novo Motorista:
              </span>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                <div>
                  <label className="block text-[10px] font-semibold text-slate-500">Nome do Condutor</label>
                  <input
                    type="text"
                    value={nomeCustomizado}
                    onChange={(e) => setNomeCustomizado(e.target.value)}
                    className="w-full h-9 px-2.5 text-xs border border-slate-300 rounded-lg bg-white text-[#0F1B2D] font-medium"
                    required
                  />
                </div>
                <div>
                  <label className="block text-[10px] font-semibold text-slate-500">Telefone de Contato</label>
                  <input
                    type="text"
                    value={telefoneCustomizado}
                    onChange={(e) => setTelefoneCustomizado(e.target.value)}
                    placeholder="(48) 99999-9999"
                    className="w-full h-9 px-2.5 text-xs border border-slate-300 rounded-lg bg-white text-[#0F1B2D] font-medium"
                  />
                </div>
              </div>
            </div>
          )}

          {/* Campos específicos da Opção B */}
          {modoAprovacao === 'vincular_existente' && (
            <div className="space-y-1.5">
              <label className="block text-xs font-bold text-[#0F1B2D]">
                Selecione o Cadastro da Frota para Vínculo <span className="text-red-500">*</span>
              </label>
              {motoristasFiltrados.length === 0 ? (
                <div className="p-3 bg-amber-50 border border-amber-200 rounded-xl text-amber-800 text-xs flex items-center gap-2">
                  <AlertCircle className="w-4 h-4 flex-shrink-0" />
                  <span>Não há cadastros desocupados na frota. Escolha a opção de "Criar Novo Cadastro".</span>
                </div>
              ) : (
                <select
                  value={motoristaSelecionadoId}
                  onChange={(e) => setMotoristaSelecionadoId(e.target.value)}
                  className="w-full h-11 border border-[#CBD5E1] rounded-xl px-3 text-xs text-[#0F1B2D] bg-white font-semibold"
                  required
                >
                  <option value="">-- Selecione o cadastro da frota --</option>
                  {motoristasFiltrados.map((m) => (
                    <option key={m.id} value={m.id}>
                      {m.nome} — {m.veiculo_modelo} ({m.veiculo_placa})
                    </option>
                  ))}
                </select>
              )}
            </div>
          )}

          {/* Botões de Ação */}
          <div className="flex items-center justify-end gap-3 pt-3 border-t border-slate-100">
            <button
              type="button"
              onClick={onFechar}
              disabled={carregando}
              className="h-10 px-4 rounded-xl border border-slate-300 text-slate-700 text-xs font-bold hover:bg-slate-50 transition-colors cursor-pointer"
            >
              Cancelar
            </button>
            <button
              type="submit"
              disabled={carregando || (modoAprovacao === 'vincular_existente' && !motoristaSelecionadoId)}
              className="h-10 px-5 rounded-xl bg-emerald-600 hover:bg-emerald-700 active:scale-98 disabled:opacity-50 text-white text-xs font-bold shadow-md shadow-emerald-600/25 transition-all flex items-center gap-1.5 cursor-pointer"
            >
              <UserCheck className="w-4 h-4" />
              <span>{carregando ? 'Processando...' : 'Confirmar Aprovação'}</span>
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
