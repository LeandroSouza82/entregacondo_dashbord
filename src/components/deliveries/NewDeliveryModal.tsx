import { useState } from 'react';
import { X, PackagePlus, Clock } from 'lucide-react';
import { MOCK_CLIENTES_ENDERECOS } from '../../services/mockData';
import type { PontoParada } from '../../types/logistics';

interface NewDeliveryModalProps {
  isOpen: boolean;
  onClose: () => void;
  onAddDelivery: (novaParada: PontoParada) => void;
}

export const NewDeliveryModal: React.FC<NewDeliveryModalProps> = ({
  isOpen,
  onClose,
  onAddDelivery,
}) => {
  const [clienteEnderecoId, setClienteEnderecoId] = useState(MOCK_CLIENTES_ENDERECOS[0].id);
  const [destinatario, setDestinatario] = useState('');
  const [unidade, setUnidade] = useState('');
  const [prioridade, setPrioridade] = useState<'baixa' | 'normal' | 'alta' | 'urgente'>('normal');

  if (!isOpen) return null;

  const localSelecionado = MOCK_CLIENTES_ENDERECOS.find(c => c.id === clienteEnderecoId) || MOCK_CLIENTES_ENDERECOS[0];

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!destinatario.trim()) return;

    const novaEntrega: PontoParada = {
      id: `ent-${Date.now()}`,
      sequencia: 99,
      clienteEnderecoId: localSelecionado.id,
      nomeLocal: localSelecionado.nome_identificador,
      destinatario: destinatario.trim(),
      unidade: unidade.trim() || undefined,
      enderecoFormatado: `${localSelecionado.endereco_completo} - ${localSelecionado.bairro}`,
      coordenadas: {
        lat: localSelecionado.latitude,
        lng: localSelecionado.longitude,
      },
      tempoMedioAtendimentoMinutos: localSelecionado.tempo_medio_minutos,
      prioridade,
      codigoRastreio: `EC-${new Date().getFullYear()}-${Math.floor(1000 + Math.random() * 9000)}`,
    };

    onAddDelivery(novaEntrega);
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-navy-950/60 backdrop-blur-sm animate-fadeIn">
      <div className="bg-white rounded-3xl max-w-lg w-full shadow-2xl border border-slate-200 overflow-hidden">
        {/* Header */}
        <div className="bg-navy-850 px-6 py-5 text-white flex items-center justify-between border-b border-navy-700">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-terracotta-600 flex items-center justify-center text-white shadow-md">
              <PackagePlus className="w-5 h-5" />
            </div>
            <div>
              <h3 className="font-extrabold text-base">Nova Entrega em Condomínio</h3>
              <p className="text-xs text-slate-300">Cadastre uma encomenda para inclusão na rota</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-2 text-slate-400 hover:text-white rounded-xl hover:bg-navy-700 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Form Body */}
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="text-xs font-bold uppercase tracking-wider text-slate-500 block mb-1.5">
              Condomínio / Endereço Cadastrado
            </label>
            <select
              value={clienteEnderecoId}
              onChange={(e) => setClienteEnderecoId(e.target.value)}
              className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3.5 py-2.5 text-sm font-semibold text-navy-900 focus:outline-none focus:ring-2 focus:ring-terracotta-500/20"
            >
              {MOCK_CLIENTES_ENDERECOS.map((cliente) => (
                <option key={cliente.id} value={cliente.id}>
                  {cliente.nome_identificador} (Média: {cliente.tempo_medio_minutos} min)
                </option>
              ))}
            </select>
          </div>

          {/* Info Card do Condomínio */}
          <div className="p-3 bg-amber-50/60 border border-amber-200/80 rounded-xl text-xs text-amber-900 flex items-start gap-2.5">
            <Clock className="w-4 h-4 text-amber-700 flex-shrink-0 mt-0.5" />
            <div>
              <span className="font-bold">Tempo Histórico Ponderado: </span>
              {localSelecionado.tempo_medio_minutos} minutos em média na portaria/descarga com base em {localSelecionado.total_entregas_realizadas} entregas.
            </div>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <label className="text-xs font-bold uppercase tracking-wider text-slate-500 block mb-1.5">
                Nome do Morador / Destinatário
              </label>
              <input
                type="text"
                required
                placeholder="Ex: Gabriela Duarte"
                value={destinatario}
                onChange={(e) => setDestinatario(e.target.value)}
                className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3.5 py-2.5 text-sm text-slate-800 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-terracotta-500/20"
              />
            </div>

            <div>
              <label className="text-xs font-bold uppercase tracking-wider text-slate-500 block mb-1.5">
                Unidade / Apartamento / Bloco
              </label>
              <input
                type="text"
                placeholder="Ex: Bloco 2 - Apto 804"
                value={unidade}
                onChange={(e) => setUnidade(e.target.value)}
                className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3.5 py-2.5 text-sm text-slate-800 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-terracotta-500/20"
              />
            </div>
          </div>

          <div>
            <label className="text-xs font-bold uppercase tracking-wider text-slate-500 block mb-1.5">
              Prioridade da Encomenda
            </label>
            <div className="grid grid-cols-4 gap-2">
              {(['baixa', 'normal', 'alta', 'urgente'] as const).map((prio) => (
                <button
                  type="button"
                  key={prio}
                  onClick={() => setPrioridade(prio)}
                  className={`py-2 text-xs font-bold uppercase rounded-xl border transition-all ${
                    prioridade === prio
                      ? 'bg-navy-800 text-white border-navy-800 shadow-sm'
                      : 'bg-slate-50 text-slate-600 border-slate-200 hover:bg-slate-100'
                  }`}
                >
                  {prio}
                </button>
              ))}
            </div>
          </div>

          {/* Actions */}
          <div className="pt-4 flex items-center justify-end gap-3 border-t border-slate-100">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2.5 rounded-xl border border-slate-200 text-xs font-semibold text-slate-600 hover:bg-slate-50 transition-colors"
            >
              Cancelar
            </button>
            <button
              type="submit"
              className="px-5 py-2.5 rounded-xl bg-terracotta-600 hover:bg-terracotta-700 active:scale-95 text-white text-xs font-bold shadow-md shadow-terracotta-600/30 transition-all"
            >
              Adicionar à Fila de Rota
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
