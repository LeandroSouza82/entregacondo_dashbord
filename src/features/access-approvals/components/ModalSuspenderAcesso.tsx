import React, { useState } from 'react';
import { ShieldAlert, X } from 'lucide-react';
import type { SolicitacaoAcessoItem } from '../types/accessApproval';

interface ModalSuspenderAcessoProps {
  solicitacao: SolicitacaoAcessoItem;
  carregando: boolean;
  onConfirmar: (membroId: string, motivo: string) => Promise<void>;
  onFechar: () => void;
}

export const ModalSuspenderAcesso: React.FC<ModalSuspenderAcessoProps> = ({
  solicitacao,
  carregando,
  onConfirmar,
  onFechar,
}) => {
  const [motivo, setMotivo] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!motivo.trim()) return;
    await onConfirmar(solicitacao.id, motivo.trim());
  };

  return (
    <div className="fixed inset-0 z-50 bg-[#0F1B2D]/60 backdrop-blur-xs flex items-center justify-center p-4 animate-fadeIn">
      <div className="bg-white rounded-2xl max-w-md w-full border border-[#CBD5E1] shadow-2xl p-6 space-y-4 animate-scaleUp">
        <div className="flex items-center justify-between pb-2 border-b border-slate-100">
          <div className="flex items-center gap-2 text-red-600">
            <ShieldAlert className="w-5 h-5" />
            <h3 className="font-extrabold text-base text-[#0F1B2D] m-0">Suspender Acesso de Motorista</h3>
          </div>
          <button
            type="button"
            onClick={onFechar}
            className="text-slate-400 hover:text-slate-600 cursor-pointer"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        <p className="text-xs text-[#516074]">
          Suspender imediatamente o acesso de <strong className="text-[#0F1B2D]">{solicitacao.usuario_nome}</strong> ({solicitacao.motorista_nome || 'Sem cadastro'}). As chamadas para obter rotas no app Flutter serão bloqueadas imediatamente pelo RLS.
        </p>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-1.5">
            <label className="block text-xs font-bold text-[#0F1B2D]">
              Justificativa da Suspensão <span className="text-red-500">*</span>
            </label>
            <textarea
              rows={3}
              value={motivo}
              onChange={(e) => setMotivo(e.target.value)}
              placeholder="Ex: Suspensão preventiva por manutenção de veículo / desligamento temporário."
              className="w-full border border-[#CBD5E1] rounded-xl p-3 text-xs text-[#0F1B2D] focus:outline-none focus:ring-2 focus:ring-red-500/20 focus:border-red-600"
              required
            />
          </div>

          <div className="flex items-center justify-end gap-3 pt-2">
            <button
              type="button"
              onClick={onFechar}
              disabled={carregando}
              className="h-10 px-4 rounded-xl border border-slate-300 text-slate-700 text-xs font-bold hover:bg-slate-50 cursor-pointer"
            >
              Cancelar
            </button>
            <button
              type="submit"
              disabled={carregando || !motivo.trim()}
              className="h-10 px-5 rounded-xl bg-red-600 hover:bg-red-700 disabled:opacity-50 text-white text-xs font-bold shadow-md shadow-red-600/20 transition-all cursor-pointer"
            >
              {carregando ? 'Processando...' : 'Suspender Acesso'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
