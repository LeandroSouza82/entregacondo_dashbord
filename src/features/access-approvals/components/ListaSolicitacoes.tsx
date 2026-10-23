import React from 'react';
import { 
  Users, 
  Mail, 
  Building2, 
  Clock, 
  UserCheck, 
  UserX, 
  ShieldAlert, 
  Truck, 
  Calendar 
} from 'lucide-react';
import type { SolicitacaoAcessoItem } from '../types/accessApproval';
import { CartaoVeiculoDeclarado } from '../../vehicles/components/CartaoVeiculoDeclarado';

interface ListaSolicitacoesProps {
  solicitacoes: SolicitacaoAcessoItem[];
  filtroStatus: string;
  onAbrirModalAprovar: (item: SolicitacaoAcessoItem) => void;
  onAbrirModalRejeitar: (item: SolicitacaoAcessoItem) => void;
  onAbrirModalSuspender: (item: SolicitacaoAcessoItem) => void;
  onReativar: (item: SolicitacaoAcessoItem) => void;
  onVerDocumentos: (item: SolicitacaoAcessoItem) => void;
}

export const ListaSolicitacoes: React.FC<ListaSolicitacoesProps> = ({
  solicitacoes,
  filtroStatus,
  onAbrirModalAprovar,
  onAbrirModalRejeitar,
  onAbrirModalSuspender,
  onReativar,
  onVerDocumentos,
}) => {
  return (
    <div className="bg-white border border-gray-300 rounded-2xl shadow-card overflow-hidden">
      <div className="overflow-x-auto">
        <table className="w-full text-left text-xs border-collapse">
          <thead>
            <tr className="border-b border-[#E1E6ED] bg-slate-50/70 text-[#516074] uppercase text-[11px] font-bold tracking-wider">
              <th className="py-3.5 px-4">Usuário Autenticado</th>
              <th className="py-3.5 px-4">Empresa / Código</th>
              <th className="py-3.5 px-4">Papel & Status</th>
              <th className="py-3.5 px-4">Veículo Declarado</th>
              <th className="py-3.5 px-4">Motorista Vinculado</th>
              <th className="py-3.5 px-4">Data Solicitação / Decisão</th>
              <th className="py-3.5 px-4 text-right">Ações da Gestão</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-[#EAEFF4] text-[#2B3A4F]">
            {solicitacoes.length === 0 ? (
              <tr>
                <td colSpan={7} className="py-12 text-center text-[#516074]">
                  <Users className="w-8 h-8 text-slate-300 mx-auto mb-2" />
                  <p className="font-semibold text-sm text-[#0F1B2D]">Nenhuma solicitação encontrada</p>
                  <p className="text-xs text-slate-400 mt-0.5">
                    {filtroStatus === 'pendente'
                      ? 'Não há solicitações de acesso pendentes de aprovação no momento.'
                      : 'Nenhum registro corresponde aos filtros selecionados.'}
                  </p>
                </td>
              </tr>
            ) : (
              solicitacoes.map((item) => {
                const dataSolicitacao = new Date(item.created_at).toLocaleDateString('pt-BR', {
                  day: '2-digit',
                  month: '2-digit',
                  year: 'numeric',
                  hour: '2-digit',
                  minute: '2-digit',
                });

                return (
                  <tr key={item.id} className="hover:bg-slate-50/70 transition-colors">
                    {/* Usuário Autenticado */}
                    <td className="py-3.5 px-4">
                      <div className="flex items-center gap-3">
                        <div className="w-9 h-9 rounded-full bg-[#0F1B2D] text-white flex items-center justify-center font-bold text-xs flex-shrink-0">
                          {item.usuario_nome.slice(0, 2).toUpperCase()}
                        </div>
                        <div>
                          <div className="font-bold text-sm text-[#0F1B2D] leading-tight">
                            {item.usuario_nome}
                          </div>
                          <div className="flex items-center gap-1 text-[11px] text-[#516074] mt-0.5">
                            <Mail className="w-3 h-3" />
                            <span>{item.usuario_email}</span>
                          </div>
                          <div className="text-[10px] text-slate-400 font-mono mt-0.5">
                            ID: {item.user_id}
                          </div>
                        </div>
                      </div>
                    </td>

                    {/* Empresa */}
                    <td className="py-3.5 px-4">
                      <div className="flex items-center gap-1.5 font-semibold text-[#0F1B2D]">
                        <Building2 className="w-3.5 h-3.5 text-slate-400" />
                        <span>{item.empresa_nome}</span>
                      </div>
                      <span className="inline-block mt-0.5 text-[10px] font-mono px-2 py-0.5 rounded bg-slate-100 text-slate-600 font-bold">
                        Convite: EC-FLN-01
                      </span>
                    </td>

                    {/* Papel & Status */}
                    <td className="py-3.5 px-4">
                      <div className="flex flex-col gap-1">
                        <span className="text-[11px] font-semibold text-[#516074] uppercase">
                          Papel: {item.papel_solicitado}
                        </span>

                        {item.status === 'pendente' && (
                          <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full bg-amber-100 text-amber-800 text-[11px] font-bold w-fit">
                            <Clock className="w-3 h-3" />
                            Pendente
                          </span>
                        )}

                        {item.status === 'aprovado' && (
                          <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full bg-[#DDF3E4] text-[#14532D] text-[11px] font-bold w-fit">
                            <UserCheck className="w-3 h-3" />
                            Aprovado
                          </span>
                        )}

                        {item.status === 'suspenso' && (
                          <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full bg-red-100 text-red-800 text-[11px] font-bold w-fit">
                            <ShieldAlert className="w-3 h-3" />
                            Suspenso
                          </span>
                        )}

                        {item.status === 'rejeitado' && (
                          <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full bg-slate-200 text-slate-700 text-[11px] font-bold w-fit">
                            <UserX className="w-3 h-3" />
                            Rejeitado
                          </span>
                        )}
                      </div>
                    </td>

                    {/* Veículo Declarado */}
                    <td className="py-3.5 px-4 min-w-[220px]">
                      <CartaoVeiculoDeclarado
                        veiculo={item.veiculo_declarado}
                        onVerDocumentos={
                          item.documentos && item.documentos.length > 0
                            ? () => onVerDocumentos(item)
                            : undefined
                        }
                        compacto
                      />
                    </td>

                    {/* Motorista Vinculado */}
                    <td className="py-3.5 px-4">
                      {item.motorista_nome ? (
                        <div>
                          <div className="font-bold text-[#0F1B2D] flex items-center gap-1.5">
                            <Truck className="w-3.5 h-3.5 text-[#1D4ED8]" />
                            <span>{item.motorista_nome}</span>
                          </div>
                          <div className="text-[11px] text-[#516074] mt-0.5">
                            {item.motorista_veiculo} · <span className="font-mono font-semibold">{item.motorista_placa}</span>
                          </div>
                        </div>
                      ) : (
                        <span className="text-slate-400 italic text-[11px]">Nenhum vínculo na frota</span>
                      )}
                    </td>

                    {/* Data / Decisão */}
                    <td className="py-3.5 px-4">
                      <div className="flex items-center gap-1 text-[11px] text-[#516074]">
                        <Calendar className="w-3 h-3" />
                        <span>Solicitado em: {dataSolicitacao}</span>
                      </div>
                      {item.decidido_em && (
                        <div className="text-[10px] text-slate-500 mt-1">
                          Decidido por: <span className="font-semibold">{item.decidido_por_nome || 'Gestor'}</span>
                          {item.motivo_decisao && <div className="text-slate-400 italic mt-0.5">"{item.motivo_decisao}"</div>}
                        </div>
                      )}
                    </td>

                    {/* Ações da Gestão */}
                    <td className="py-3.5 px-4 text-right">
                      <div className="flex items-center justify-end gap-2">
                        {item.status === 'pendente' && (
                          <>
                            <button
                              type="button"
                              onClick={() => onAbrirModalAprovar(item)}
                              className="h-8 px-3 rounded-lg bg-emerald-600 hover:bg-emerald-700 text-white font-bold text-xs shadow-sm transition-all flex items-center gap-1 cursor-pointer"
                            >
                              <UserCheck className="w-3.5 h-3.5" />
                              <span>Aprovar</span>
                            </button>

                            <button
                              type="button"
                              onClick={() => onAbrirModalRejeitar(item)}
                              className="h-8 px-3 rounded-lg border border-slate-300 hover:bg-slate-100 text-slate-700 font-bold text-xs transition-all flex items-center gap-1 cursor-pointer"
                            >
                              <UserX className="w-3.5 h-3.5" />
                              <span>Rejeitar</span>
                            </button>
                          </>
                        )}

                        {item.status === 'aprovado' && (
                          <button
                            type="button"
                            onClick={() => onAbrirModalSuspender(item)}
                            className="h-8 px-3 rounded-lg border border-red-200 hover:bg-red-50 text-red-700 font-bold text-xs transition-all flex items-center gap-1 cursor-pointer"
                          >
                            <ShieldAlert className="w-3.5 h-3.5" />
                            <span>Suspender</span>
                          </button>
                        )}

                        {item.status === 'suspenso' && (
                          <button
                            type="button"
                            onClick={() => onReativar(item)}
                            className="h-8 px-3 rounded-lg bg-emerald-600 hover:bg-emerald-700 text-white font-bold text-xs transition-all flex items-center gap-1 cursor-pointer"
                          >
                            <UserCheck className="w-3.5 h-3.5" />
                            <span>Reativar Acesso</span>
                          </button>
                        )}

                        {item.status === 'rejeitado' && (
                          <button
                            type="button"
                            onClick={() => onAbrirModalAprovar(item)}
                            className="h-8 px-3 rounded-lg border border-slate-300 hover:bg-slate-100 text-[#0F1B2D] font-bold text-xs transition-all cursor-pointer"
                          >
                            Reavaliar
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
};
