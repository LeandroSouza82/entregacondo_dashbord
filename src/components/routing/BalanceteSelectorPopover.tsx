import React, { useState, useEffect, useRef } from 'react';
import { Calendar, ChevronLeft, ChevronRight, X, Clock, Check } from 'lucide-react';

interface BalanceteSelectorPopoverProps {
  onSelect: (mesAnoTexto: string) => void;
  onClose: () => void;
}

const MESES = [
  { numero: '01', nome: 'Janeiro', abrev: 'Jan' },
  { numero: '02', nome: 'Fevereiro', abrev: 'Fev' },
  { numero: '03', nome: 'Março', abrev: 'Mar' },
  { numero: '04', nome: 'Abril', abrev: 'Abr' },
  { numero: '05', nome: 'Maio', abrev: 'Mai' },
  { numero: '06', nome: 'Junho', abrev: 'Jun' },
  { numero: '07', nome: 'Julho', abrev: 'Jul' },
  { numero: '08', nome: 'Agosto', abrev: 'Ago' },
  { numero: '09', nome: 'Setembro', abrev: 'Set' },
  { numero: '10', nome: 'Outubro', abrev: 'Out' },
  { numero: '11', nome: 'Novembro', abrev: 'Nov' },
  { numero: '12', nome: 'Dezembro', abrev: 'Dez' },
];

export const BalanceteSelectorPopover: React.FC<BalanceteSelectorPopoverProps> = ({
  onSelect,
  onClose,
}) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const dataHoje = new Date();
  const anoCorrente = dataHoje.getFullYear();
  const mesCorrenteIdx = dataHoje.getMonth(); // 0-indexed (ex: 9 para Outubro)

  const [anoSelecionado, setAnoSelecionado] = useState<number>(anoCorrente);
  const anosDisponiveis = [anoCorrente - 1, anoCorrente, anoCorrente + 1];

  // Fechar ao clicar fora
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        onClose();
      }
    };
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        onClose();
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    document.addEventListener('keydown', handleKeyDown);
    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
      document.removeEventListener('keydown', handleKeyDown);
    };
  }, [onClose]);

  const handleSelectMes = (mesNumero: string) => {
    const textoFormatado = `Mês ${mesNumero}/${anoSelecionado}`;
    onSelect(textoFormatado);
  };

  // Cálculo de atalhos rápidos (Mês anterior e Mês atual)
  const mesAnteriorIdx = mesCorrenteIdx === 0 ? 11 : mesCorrenteIdx - 1;
  const anoMesAnterior = mesCorrenteIdx === 0 ? anoCorrente - 1 : anoCorrente;
  const mesAnteriorItem = MESES[mesAnteriorIdx];
  const mesAtualItem = MESES[mesCorrenteIdx];

  return (
    <div
      ref={containerRef}
      className="absolute left-0 top-full mt-2 z-50 w-[340px] sm:w-[380px] max-w-[95vw] bg-white border border-slate-200/90 rounded-2xl shadow-2xl overflow-hidden animate-fadeIn ring-1 ring-slate-900/10"
      style={{ boxShadow: '0 20px 35px -10px rgba(15, 27, 45, 0.22), 0 0 1px 1px rgba(15, 27, 45, 0.05)' }}
    >
      {/* Cabeçalho */}
      <div className="px-4 py-3 bg-slate-50 border-b border-slate-100 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="w-7 h-7 rounded-lg bg-blue-100/80 text-[#1D4ED8] flex items-center justify-center">
            <Calendar className="w-4 h-4" />
          </div>
          <div>
            <h4 className="text-xs font-bold text-[#0F1B2D]">Período do Balancete</h4>
            <p className="text-[11px] text-slate-500">Selecione o mês de referência</p>
          </div>
        </div>
        <button
          type="button"
          onClick={onClose}
          className="w-7 h-7 rounded-lg text-slate-400 hover:text-slate-600 hover:bg-slate-200/60 flex items-center justify-center transition-colors"
          title="Fechar"
        >
          <X className="w-4 h-4" />
        </button>
      </div>

      <div className="p-3.5 space-y-3">
        {/* Atalhos Rápidos */}
        <div className="space-y-1.5">
          <span className="text-[10px] font-bold uppercase tracking-wider text-slate-400">
            Atalhos frequentes
          </span>
          <div className="grid grid-cols-2 gap-2">
            <button
              type="button"
              onClick={() => {
                setAnoSelecionado(anoMesAnterior);
                onSelect(`Mês ${mesAnteriorItem.numero}/${anoMesAnterior}`);
              }}
              className="px-2.5 py-1.5 rounded-xl border border-slate-200 hover:border-[#1D4ED8] hover:bg-blue-50/70 text-left transition-all group"
            >
              <div className="flex items-center gap-1.5 text-[10px] font-bold text-slate-500 group-hover:text-[#1D4ED8]">
                <Clock className="w-3 h-3 text-slate-400 group-hover:text-[#1D4ED8]" />
                Mês Anterior
              </div>
              <div className="text-xs font-bold text-[#0F1B2D] group-hover:text-[#1D4ED8]">
                {mesAnteriorItem.abrev}/{anoMesAnterior} ({mesAnteriorItem.numero})
              </div>
            </button>

            <button
              type="button"
              onClick={() => {
                setAnoSelecionado(anoCorrente);
                onSelect(`Mês ${mesAtualItem.numero}/${anoCorrente}`);
              }}
              className="px-2.5 py-1.5 rounded-xl border border-blue-200 bg-blue-50/50 hover:bg-blue-50 text-left transition-all group"
            >
              <div className="flex items-center gap-1.5 text-[10px] font-bold text-[#1D4ED8]">
                <Check className="w-3 h-3 text-[#1D4ED8]" />
                Mês Atual
              </div>
              <div className="text-xs font-bold text-[#1D4ED8]">
                {mesAtualItem.abrev}/{anoCorrente} ({mesAtualItem.numero})
              </div>
            </button>
          </div>
        </div>

        {/* Seletor de Ano */}
        <div className="flex items-center justify-between bg-slate-100/80 p-1 rounded-xl">
          <button
            type="button"
            onClick={() => setAnoSelecionado((prev) => prev - 1)}
            className="w-7 h-7 rounded-lg text-slate-500 hover:text-slate-800 hover:bg-white flex items-center justify-center transition-all"
            title="Ano anterior"
          >
            <ChevronLeft className="w-4 h-4" />
          </button>

          <div className="flex items-center gap-1">
            {anosDisponiveis.map((ano) => {
              const isSelected = ano === anoSelecionado;
              return (
                <button
                  key={ano}
                  type="button"
                  onClick={() => setAnoSelecionado(ano)}
                  className={`px-3 py-1 rounded-lg text-xs font-bold transition-all ${
                    isSelected
                      ? 'bg-[#1D4ED8] text-white shadow-xs'
                      : 'text-slate-600 hover:text-slate-900 hover:bg-white/70'
                  }`}
                >
                  {ano}
                </button>
              );
            })}
          </div>

          <button
            type="button"
            onClick={() => setAnoSelecionado((prev) => prev + 1)}
            className="w-7 h-7 rounded-lg text-slate-500 hover:text-slate-800 hover:bg-white flex items-center justify-center transition-all"
            title="Próximo ano"
          >
            <ChevronRight className="w-4 h-4" />
          </button>
        </div>

        {/* Grade de 12 Meses */}
        <div className="grid grid-cols-3 gap-1.5 max-h-[220px] overflow-y-auto pr-0.5">
          {MESES.map((mes, index) => {
            const isMesAtual = anoSelecionado === anoCorrente && index === mesCorrenteIdx;

            return (
              <button
                key={mes.numero}
                type="button"
                onClick={() => handleSelectMes(mes.numero)}
                className={`p-2 rounded-xl border text-left transition-all flex flex-col justify-between hover:scale-[1.02] cursor-pointer ${
                  isMesAtual
                    ? 'border-blue-300 bg-blue-50/60 hover:bg-blue-100/70 hover:border-blue-400'
                    : 'border-slate-200/90 bg-white hover:bg-slate-50 hover:border-slate-300'
                }`}
              >
                <div className="flex items-center justify-between w-full">
                  <span className="text-[12px] font-extrabold text-[#0F1B2D]">
                    Mês {mes.numero}
                  </span>
                  {isMesAtual && (
                    <span className="w-1.5 h-1.5 rounded-full bg-[#1D4ED8]" title="Mês corrente" />
                  )}
                </div>
                <div className="flex items-center justify-between text-[11px] text-slate-500 mt-1 font-medium">
                  <span>{mes.abrev}</span>
                  <span className="text-[10px] text-slate-400">/{anoSelecionado}</span>
                </div>
              </button>
            );
          })}
        </div>
      </div>

      {/* Rodapé com pré-visualização */}
      <div className="px-3.5 py-2.5 bg-slate-50 border-t border-slate-100 flex items-center justify-between text-[11px] text-slate-500">
        <span>Formato inserido:</span>
        <code className="px-2 py-0.5 bg-white border border-slate-200 rounded font-semibold text-[#1D4ED8]">
          Balancete referente ao mês XX/{anoSelecionado}
        </code>
      </div>
    </div>
  );
};
