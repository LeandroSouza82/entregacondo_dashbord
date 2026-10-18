import React, { useState, useEffect, useRef, useCallback } from 'react';
import { Building2, Search, Loader2, Sparkles, Check, MapPin, ArrowRight } from 'lucide-react';
import type { ClienteEnderecoItem } from '../../features/routes/types/clienteEndereco';
import { buscarClientesEnderecos } from '../../features/routes/services/buscarClientesEnderecos';

interface ClienteCondominioSearchInputProps {
  value: string;
  onChange: (value: string) => void;
  onSelectClienteEndereco: (item: ClienteEnderecoItem) => void;
  placeholder?: string;
  empresaId?: string;
  disabled?: boolean;
}

export const ClienteCondominioSearchInput: React.FC<ClienteCondominioSearchInputProps> = ({
  value,
  onChange,
  onSelectClienteEndereco,
  placeholder = 'Ex: Condomínio Jardim América ou Maria Fernanda',
  empresaId,
  disabled = false,
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

      {/* Dropdown de Sugestões Prioritárias da Base Local */}
      {isOpen && (
        <div className="absolute left-0 right-0 top-full mt-1.5 bg-white border border-slate-200 rounded-xl shadow-2xl z-50 overflow-hidden animate-fadeIn max-h-[320px] overflow-y-auto">
          {sugestoes.length > 0 ? (
            <div className="p-1.5 space-y-1">
              <div className="px-3 py-1.5 flex items-center justify-between text-[11px] font-bold uppercase tracking-wider text-slate-400 border-b border-slate-100">
                <span className="flex items-center gap-1.5">
                  <Building2 className="w-3.5 h-3.5 text-[#1D4ED8]" />
                  Condomínios e Clientes Salvos
                </span>
                <span className="text-slate-400">{sugestoes.length} resultado{sugestoes.length > 1 ? 's' : ''}</span>
              </div>

              {sugestoes.map((item, index) => {
                const isFocused = indiceFocado === index;
                return (
                  <button
                    key={item.id}
                    type="button"
                    onClick={() => handleSelect(item)}
                    onMouseEnter={() => setIndiceFocado(index)}
                    className={`w-full text-left p-2.5 rounded-lg flex items-center justify-between gap-3 transition-colors cursor-pointer ${
                      isFocused ? 'bg-[#EEF4FF] text-[#0F1B2D]' : 'hover:bg-slate-50 text-slate-800'
                    }`}
                  >
                    <div className="flex items-start gap-2.5 min-w-0">
                      <div className="w-8 h-8 rounded-lg bg-blue-50 text-[#1D4ED8] flex items-center justify-center flex-shrink-0 mt-0.5 border border-blue-100">
                        <Building2 className="w-4 h-4" />
                      </div>
                      <div className="min-w-0">
                        <div className="font-bold text-[13px] text-[#0F1B2D] truncate">
                          {item.nome_identificador}
                        </div>
                        <div className="text-xs text-slate-500 truncate flex items-center gap-1 mt-0.5">
                          <MapPin className="w-3 h-3 text-slate-400 flex-shrink-0" />
                          <span className="truncate">{item.endereco_completo}</span>
                        </div>
                        {item.destinatario_padrao && (
                          <div className="text-[11px] text-slate-400 mt-0.5 truncate">
                            Destinatário/Portaria: <span className="font-medium text-slate-600">{item.destinatario_padrao}</span>
                          </div>
                        )}
                      </div>
                    </div>

                    <div className="flex-shrink-0 flex flex-col items-end gap-1">
                      <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-50 text-emerald-700 border border-emerald-200">
                        <Sparkles className="w-2.5 h-2.5" />
                        Salvo · {item.total_entregas_realizadas} entregas
                      </span>
                      {item.tempo_medio_minutos && (
                        <span className="text-[10px] text-slate-400 font-medium">
                          ~{item.tempo_medio_minutos} min portaria
                        </span>
                      )}
                    </div>
                  </button>
                );
              })}
            </div>
          ) : (
            value.trim().length >= 2 && !carregando && (
              <div className="p-3.5 text-center text-xs space-y-1 text-slate-600 bg-slate-50/50">
                <div className="font-bold text-[#0F1B2D]">
                  Nenhum condomínio salvo encontrado com "{value}"
                </div>
                <div className="text-[11px] text-slate-500 flex items-center justify-center gap-1">
                  <span>Preencha o campo <strong>Endereço</strong> abaixo pelo Google Places para cadastrar este novo local.</span>
                  <ArrowRight className="w-3.5 h-3.5 text-terracotta-600" />
                </div>
              </div>
            )
          )}
        </div>
      )}
    </div>
  );
};
