import React, { useState, useEffect, useRef, useCallback } from 'react';
import { Building2, Search, Loader2, Sparkles, Check, MapPin, ArrowRight, Clock } from 'lucide-react';
import type { ClienteEnderecoItem } from '../../features/routes/types/clienteEndereco';
import { buscarClientesEnderecos } from '../../features/routes/services/buscarClientesEnderecos';

interface ClienteCondominioSearchInputProps {
  value: string;
  onChange: (value: string) => void;
  onSelectClienteEndereco: (item: ClienteEnderecoItem) => void;
  placeholder?: string;
  empresaId?: string;
  disabled?: boolean;
  inputRef?: React.RefObject<HTMLInputElement | null>;
}

export const ClienteCondominioSearchInput: React.FC<ClienteCondominioSearchInputProps> = ({
  value,
  onChange,
  onSelectClienteEndereco,
  placeholder = 'Ex: Condomínio Jardim América ou Maria Fernanda',
  empresaId,
  disabled = false,
  inputRef,
}) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const debounceTimerRef = useRef<number | null>(null);

  const [isOpen, setIsOpen] = useState<boolean>(false);
  const [carregando, setCarregando] = useState<boolean>(false);
  const [sugestoes, setSugestoes] = useState<ClienteEnderecoItem[]>([]);
  const [indiceFocado, setIndiceFocado] = useState<number>(-1);
  const [selecionadoManual, setSelecionadoManual] = useState<boolean>(false);

  // Fecha o dropdown ao clicar fora
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  // Quando o valor for limpo externamente, reseta seleções pendentes e sugestões
  useEffect(() => {
    if (!value) {
      setSelecionadoManual(false);
      setSugestoes([]);
      setIsOpen(false);
    }
  }, [value]);

  // Busca debounced no banco de dados local / Supabase
  const executarBusca = useCallback(async (termo: string) => {
    if (!termo.trim() || termo.length < 1) {
      setSugestoes([]);
      setCarregando(false);
      setIsOpen(false);
      return;
    }

    setCarregando(true);
    try {
      const resultados = await buscarClientesEnderecos(termo, empresaId);
      setSugestoes(resultados);
      setIsOpen(true);
      setIndiceFocado(-1);
    } catch (err) {
      console.warn('Erro ao buscar clientes/endereços:', err);
      setSugestoes([]);
    } finally {
      setCarregando(false);
    }
  }, [empresaId]);

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const novoValor = e.target.value;
    onChange(novoValor);
    setSelecionadoManual(false);

    if (debounceTimerRef.current) {
      window.clearTimeout(debounceTimerRef.current);
    }

    if (!novoValor.trim()) {
      setSugestoes([]);
      setIsOpen(false);
      return;
    }

    debounceTimerRef.current = window.setTimeout(() => {
      executarBusca(novoValor);
    }, 180);
  };

  const handleSelect = (item: ClienteEnderecoItem) => {
    onSelectClienteEndereco(item);
    setSelecionadoManual(true);
    setIsOpen(false);
    setSugestoes([]);
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (!isOpen || sugestoes.length === 0) return;

    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setIndiceFocado((prev) => (prev < sugestoes.length - 1 ? prev + 1 : 0));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setIndiceFocado((prev) => (prev > 0 ? prev - 1 : sugestoes.length - 1));
    } else if (e.key === 'Enter') {
      e.preventDefault();
      if (indiceFocado >= 0 && indiceFocado < sugestoes.length) {
        handleSelect(sugestoes[indiceFocado]);
      }
    } else if (e.key === 'Escape') {
      setIsOpen(false);
    }
  };

  return (
    <div ref={containerRef} className="relative w-full">
      <div className="relative">
        <input
          ref={inputRef}
          type="text"
          value={value}
          onChange={handleInputChange}
          onFocus={() => {
            if (value.trim().length >= 1 && !selecionadoManual) {
              executarBusca(value);
            }
          }}
          onKeyDown={handleKeyDown}
          placeholder={placeholder}
          disabled={disabled}
          autoComplete="off"
          className="w-full h-11 border border-[#CBD5E1] rounded-[10px] pl-3.5 pr-10 text-sm text-[#0F1B2D] bg-white font-medium placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-[#1D4ED8]/20 focus:border-[#1D4ED8] transition-all shadow-2xs"
        />

        <div className="absolute right-3 top-1/2 -translate-y-1/2 flex items-center pointer-events-none text-slate-400">
          {carregando ? (
            <Loader2 className="w-4 h-4 animate-spin text-[#1D4ED8]" />
          ) : selecionadoManual ? (
            <Check className="w-4 h-4 text-emerald-600" />
          ) : (
            <Search className="w-4 h-4" />
          )}
        </div>
      </div>

      {/* Dropdown de Sugestões Prioritárias da Base Local com Largura Expandida */}
      {isOpen && (
        <div className="absolute left-0 top-full mt-2 w-full sm:w-[580px] md:w-[660px] lg:w-[720px] max-w-[94vw] bg-white border border-slate-200/90 rounded-2xl shadow-2xl z-50 overflow-hidden animate-fadeIn max-h-[420px] overflow-y-auto ring-1 ring-slate-900/5">
          {sugestoes.length > 0 ? (
            <div className="p-2 space-y-1">
              <div className="px-3.5 py-2 flex items-center justify-between text-[11px] font-bold uppercase tracking-wider text-slate-500 bg-slate-50/70 border-b border-slate-100 rounded-lg">
                <span className="flex items-center gap-2">
                  <Building2 className="w-3.5 h-3.5 text-[#1D4ED8]" />
                  Condomínios Salvos · Grande Florianópolis
                </span>
                <span className="text-slate-400 font-semibold">{sugestoes.length} resultado{sugestoes.length > 1 ? 's' : ''}</span>
              </div>

              {sugestoes.map((item, index) => {
                const isFocused = indiceFocado === index;
                return (
                  <button
                    key={item.id}
                    type="button"
                    onClick={() => handleSelect(item)}
                    onMouseEnter={() => setIndiceFocado(index)}
                    className={`w-full text-left p-3 rounded-xl flex items-center justify-between gap-4 transition-all cursor-pointer border ${
                      isFocused
                        ? 'bg-[#EEF4FF] border-[#1D4ED8]/30 shadow-xs ring-1 ring-[#1D4ED8]/20'
                        : 'border-transparent hover:bg-slate-50/80 hover:border-slate-100'
                    }`}
                  >
                    <div className="flex items-start gap-3 min-w-0 flex-1">
                      <div className="w-9 h-9 rounded-xl bg-blue-50 text-[#1D4ED8] flex items-center justify-center flex-shrink-0 mt-0.5 border border-blue-100/90 shadow-2xs">
                        <Building2 className="w-4 h-4" />
                      </div>
                      <div className="min-w-0 flex-1">
                        <div className="font-extrabold text-[14px] text-[#0F1B2D] leading-snug">
                          {item.nome_identificador}
                        </div>
                        <div className="text-xs text-slate-600 flex items-center gap-1.5 mt-1 font-medium">
                          <MapPin className="w-3.5 h-3.5 text-slate-400 flex-shrink-0" />
                          <span className="break-words">{item.endereco_completo}</span>
                        </div>
                        {item.destinatario_padrao && (
                          <div className="text-[11px] text-slate-400 mt-1 flex items-center gap-1">
                            <span className="font-semibold text-slate-500">Ponto/Portaria:</span>
                            <span className="text-slate-700">{item.destinatario_padrao}</span>
                          </div>
                        )}
                      </div>
                    </div>

                    <div className="flex-shrink-0 flex flex-col items-end gap-1.5 pl-2">
                      <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-extrabold bg-emerald-50 text-emerald-800 border border-emerald-200/90 whitespace-nowrap shadow-2xs">
                        <Sparkles className="w-3 h-3 text-emerald-600" />
                        Salvo · {item.total_entregas_realizadas} entregas
                      </span>
                      {item.tempo_medio_minutos && (
                        <span className="inline-flex items-center gap-1 text-[11px] text-slate-500 font-semibold whitespace-nowrap">
                          <Clock className="w-3 h-3 text-slate-400" />
                          ~{item.tempo_medio_minutos} min na portaria
                        </span>
                      )}
                    </div>
                  </button>
                );
              })}
            </div>
          ) : (
            value.trim().length >= 2 && !carregando && (
              <div className="p-4 text-center text-xs space-y-1.5 text-slate-600 bg-slate-50/50">
                <div className="font-bold text-[#0F1B2D] text-sm">
                  Nenhum condomínio salvo encontrado com "{value}"
                </div>
                <div className="text-xs text-slate-500 flex items-center justify-center gap-1.5 max-w-md mx-auto">
                  <span>Preencha o campo <strong>Endereço</strong> abaixo pelo Google Places para cadastrar este novo local na Grande Florianópolis.</span>
                  <ArrowRight className="w-3.5 h-3.5 text-terracotta-600 flex-shrink-0" />
                </div>
              </div>
            )
          )}
        </div>
      )}
    </div>
  );
};
