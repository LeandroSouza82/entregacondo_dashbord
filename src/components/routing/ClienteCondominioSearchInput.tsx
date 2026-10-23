import { coordenadasValidas, erroLocalizacaoEndereco } from '../../features/routes/services/addressCoordinates';
import { geocodificarEndereco } from '../../features/routes/services/routeOptimization';
import React, { useState, useEffect, useRef, useCallback } from 'react';
import { Building2, Search, Loader2, Sparkles, Check, MapPin, Clock, Globe, Trash2 } from 'lucide-react';
import type { ClienteEnderecoItem } from '../../features/routes/types/clienteEndereco';
import type { PontoCoordenada } from '../../types/logistics';
import { 
  buscarClientesEnderecos, 
  pertenceAGrandeFlorianopolis,
  buscarSugestoesNominatim
} from '../../features/routes/services/buscarClientesEnderecos';
import { excluirClienteEndereco } from '../../features/routes/services/excluirClienteEndereco';

const GOOGLE_PLACES_KEY = '';

interface GooglePlaceItem {
  placeId: string;
  mainText: string;
  secondaryText: string;
  fullText: string;
  coordenadas?: PontoCoordenada;
  origem?: 'google' | 'nominatim';
}

interface ClienteCondominioSearchInputProps {
  value: string;
  onChange: (value: string) => void;
  onSelectClienteEndereco: (item: ClienteEnderecoItem) => void;
  onSelectGooglePlace?: (data: {
    nome: string;
    endereco: string;
    coordenadas: PontoCoordenada;
  }) => void;
  placeholder?: string;
  empresaId?: string;
  disabled?: boolean;
  inputRef?: React.RefObject<HTMLInputElement | null>;
}

export const ClienteCondominioSearchInput: React.FC<ClienteCondominioSearchInputProps> = ({
  value,
  onChange,
  onSelectClienteEndereco,
  onSelectGooglePlace,
  placeholder = 'Ex: Condomínio Jardim América ou Maria Fernanda',
  empresaId,
  disabled = false,
  inputRef,
}) => {
  const selectionRevisionRef = useRef(0);
  const containerRef = useRef<HTMLDivElement>(null);
  const debounceTimerRef = useRef<number | null>(null);
  const sessionTokenRef = useRef<string>(crypto.randomUUID());

  const [erroLocalizacao, setErroLocalizacao] = useState<string | null>(null);
  const [isOpen, setIsOpen] = useState<boolean>(false);
  const [carregando, setCarregando] = useState<boolean>(false);
  const [sugestoesLocais, setSugestoesLocais] = useState<ClienteEnderecoItem[]>([]);
  const [sugestoesGoogle, setSugestoesGoogle] = useState<GooglePlaceItem[]>([]);
  const [indiceFocado, setIndiceFocado] = useState<number>(-1);
  const [selecionadoManual, setSelecionadoManual] = useState<boolean>(false);
  const [excluindoId, setExcluindoId] = useState<string | null>(null);

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
      setSugestoesLocais([]);
      setSugestoesGoogle([]);
      setIsOpen(false);
    }
  }, [value]);

  // Consulta resiliente: tenta Google Places API (New) e faz fallback para Nominatim
  const buscarGooglePlaces = useCallback(async (query: string) => {
    if (!query.trim() || query.length < 2) {
      setSugestoesGoogle([]);
      return;
    }

    let parsedGoogle: GooglePlaceItem[] = [];

    // CAMADA 2: Google Places REST API
    if (GOOGLE_PLACES_KEY) {
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 2000);

        const res = await fetch('https://places.googleapis.com/v1/places:autocomplete', {
          method: 'POST',
          signal: controller.signal,
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': GOOGLE_PLACES_KEY,
          },
          body: JSON.stringify({
            input: query,
            includedRegionCodes: ['br'],
            languageCode: 'pt-BR',
            sessionToken: sessionTokenRef.current,
            locationRestriction: {
              circle: {
                center: { latitude: -27.5954, longitude: -48.5480 },
                radius: 50000.0,
              },
            },
          }),
        });
        clearTimeout(timeoutId);

        if (res.ok) {
          const data = await res.json();
          if (data.suggestions && Array.isArray(data.suggestions)) {
            parsedGoogle = data.suggestions
              .filter((s: { placePrediction?: unknown }) => s.placePrediction)
              .map((s: any) => {
                const pred = s.placePrediction;
                return {
                  placeId: pred.placeId,
                  mainText: pred.structuredFormat?.mainText?.text || pred.text?.text || '',
                  secondaryText: pred.structuredFormat?.secondaryText?.text || '',
                  fullText: pred.text?.text || '',
                  origem: 'google' as const,
                };
              })
              .filter((pred: GooglePlaceItem) => {
                return pertenceAGrandeFlorianopolis({
                  cidade: pred.secondaryText,
                  endereco_completo: `${pred.mainText} ${pred.secondaryText} ${pred.fullText}`,
                });
              });
          }
        }
      } catch (err) {
        // Silencioso: segue para a Camada 3 de Fallback
      }
    }

    // CAMADA 3: Fallback Geocoding / Nominatim se Google não retornou resultados ou falhou
    if (parsedGoogle.length > 0) {
      setSugestoesGoogle(parsedGoogle);
    } else {
      try {
        const nomResults = await buscarSugestoesNominatim(query);
        const mapped: GooglePlaceItem[] = nomResults.map((n) => ({
          placeId: n.placeId,
          mainText: n.mainText,
          secondaryText: n.secondaryText,
          fullText: n.fullText,
          coordenadas: n.coordenadas,
          origem: 'nominatim' as const,
        }));
        setSugestoesGoogle(mapped);
      } catch {
        setSugestoesGoogle([]);
      }
    }
  }, []);

  // Busca debounced "Banco Primeiro, Google Depois"
  const executarBusca = useCallback(async (termo: string) => {
    if (!termo.trim() || termo.length < 1) {
      setSugestoesLocais([]);
      setSugestoesGoogle([]);
      setCarregando(false);
      setIsOpen(false);
      return;
    }

    setCarregando(true);
    try {
      // 1. PRIORIDADE MÁXIMA: Consulta no Banco Local da Empresa
      const resultadosLocais = await buscarClientesEnderecos(termo, empresaId);
      setSugestoesLocais(resultadosLocais);
      setIsOpen(true);
      setIndiceFocado(-1);

      // 2. GOOGLE/FALLBACK DEPOIS: Se não houver correspondência no banco local, busca externa
      if (resultadosLocais.length === 0 && termo.trim().length >= 2) {
        await buscarGooglePlaces(termo);
      } else {
        setSugestoesGoogle([]);
      }
    } catch (err) {
      console.warn('Erro na busca inteligente de clientes:', err);
      setSugestoesLocais([]);
      setSugestoesGoogle([]);
    } finally {
      setCarregando(false);
    }
  }, [empresaId, buscarGooglePlaces]);

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    selectionRevisionRef.current++;
    setErroLocalizacao(null);
    const novoValor = e.target.value;
    onChange(novoValor);
    setSelecionadoManual(false);

    if (debounceTimerRef.current) {
      window.clearTimeout(debounceTimerRef.current);
    }

    if (!novoValor.trim()) {
      setSugestoesLocais([]);
      setSugestoesGoogle([]);
      setIsOpen(false);
      return;
    }

    debounceTimerRef.current = window.setTimeout(() => {
      executarBusca(novoValor);
    }, 450);
  };

  // Seleção de item da base local (0 custo de API)
  const handleSelectLocal = (item: ClienteEnderecoItem) => {
    selectionRevisionRef.current++;
    onSelectClienteEndereco(item);
    setSelecionadoManual(true);
    setIsOpen(false);
    setSugestoesLocais([]);
    setSugestoesGoogle([]);
  };

  // Exclusão permanente de endereço salvo (isolada da seleção)
  const handleExcluirLocal = async (e: React.MouseEvent, item: ClienteEnderecoItem) => {
    e.stopPropagation();
    e.preventDefault();
    if (excluindoId) return;
    setExcluindoId(item.id);
    setErroLocalizacao(null);
    try {
      await excluirClienteEndereco(item.id);
      setSugestoesLocais((prev) => prev.filter((s) => s.id !== item.id));
      setIndiceFocado(-1);
    } catch (err) {
      console.warn('Erro ao excluir endereço salvo:', err);
      setErroLocalizacao(err instanceof Error && err.message ? err.message : 'Não foi possível excluir o endereço. Tente novamente.');
    } finally {
      setExcluindoId(null);
    }
  };

  // Seleção de item de sugestão externa (Google Places ou Nominatim)
  const handleSelectGoogle = async (item: GooglePlaceItem) => {
    const revision = ++selectionRevisionRef.current;
    setCarregando(true);
    setErroLocalizacao(null);
    try {
      // Se já temos coordenadas (fallback Nominatim), não consome a API do Google
      if (coordenadasValidas(item.coordenadas)) {
        const nomeFinal = item.mainText;
        const enderecoFinal = item.fullText;

        onChange(nomeFinal);
        setSelecionadoManual(true);
        setIsOpen(false);
        setSugestoesLocais([]);
        setSugestoesGoogle([]);

        if (onSelectGooglePlace) {
          onSelectGooglePlace({
            nome: nomeFinal,
            endereco: enderecoFinal,
            coordenadas: item.coordenadas,
          });
        }
        return;
      }

      let coordenadas: PontoCoordenada | null = null;

      if (GOOGLE_PLACES_KEY && item.placeId) {
        try {
          const detailsUrl = `https://places.googleapis.com/v1/places/${item.placeId}?fields=id,displayName,formattedAddress,location&key=${GOOGLE_PLACES_KEY}&sessionToken=${sessionTokenRef.current}`;
          const res = await fetch(detailsUrl);
          if (res.ok) {
            const data = await res.json();
            if (data.location && typeof data.location.latitude === 'number' && typeof data.location.longitude === 'number') {
              coordenadas = {
                lat: data.location.latitude,
                lng: data.location.longitude,
              };
            }
          }
        } catch {
          // Tenta geocodificação pelo endereço completo abaixo.
        }
      }

      if (!coordenadasValidas(coordenadas)) {
        coordenadas = (await geocodificarEndereco(item.fullText))?.coordenadas ?? null;
      }
      if (revision !== selectionRevisionRef.current) return;
      if (!coordenadasValidas(coordenadas)) {
        setErroLocalizacao(erroLocalizacaoEndereco);
        return;
      }

      const nomeFinal = item.mainText;
      const enderecoFinal = item.fullText;

      onChange(nomeFinal);
      setSelecionadoManual(true);
      setIsOpen(false);
      setSugestoesLocais([]);
      setSugestoesGoogle([]);

      sessionTokenRef.current = crypto.randomUUID();

      if (onSelectGooglePlace) {
        onSelectGooglePlace({
          nome: nomeFinal,
          endereco: enderecoFinal,
          coordenadas,
        });
      }
    } catch (err) {
      console.warn('Erro ao obter detalhes do Place selecionado:', err);
    } finally {
      setCarregando(false);
    }
  };

  const totalOpcoes = sugestoesLocais.length + sugestoesGoogle.length;

  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (!isOpen || totalOpcoes === 0) return;

    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setIndiceFocado((prev) => (prev < totalOpcoes - 1 ? prev + 1 : 0));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setIndiceFocado((prev) => (prev > 0 ? prev - 1 : totalOpcoes - 1));
    } else if (e.key === 'Enter') {
      e.preventDefault();
      if (indiceFocado >= 0) {
        if (indiceFocado < sugestoesLocais.length) {
          handleSelectLocal(sugestoesLocais[indiceFocado]);
        } else {
          const googleIdx = indiceFocado - sugestoesLocais.length;
          if (googleIdx >= 0 && googleIdx < sugestoesGoogle.length) {
            handleSelectGoogle(sugestoesGoogle[googleIdx]);
          }
        }
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
          name="cliente_condominio_busca_ec"
          autoComplete="off"
          autoCorrect="off"
          spellCheck={false}
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

      {erroLocalizacao && <p role="alert" className="mt-2 text-sm text-red-700">{erroLocalizacao}</p>}
      {/* Dropdown de Resultados Inteligentes */}
      {isOpen && (
        <div className="absolute left-0 top-full mt-2 w-full sm:w-[580px] md:w-[660px] lg:w-[720px] max-w-[94vw] bg-white border border-slate-200/90 rounded-2xl shadow-2xl z-50 overflow-hidden animate-fadeIn max-h-[440px] overflow-y-auto ring-1 ring-slate-900/5">
          {/* SEÇÃO 1: BANCO PRIMEIRO (CONDOMÍNIOS SALVOS NA EMPRESA) */}
          {sugestoesLocais.length > 0 && (
            <div className="p-2 space-y-1">
              <div className="px-3.5 py-2 flex items-center justify-between text-[11px] font-bold uppercase tracking-wider text-emerald-800 bg-emerald-50/80 border-b border-emerald-100 rounded-lg">
                <span className="flex items-center gap-2">
                  <Building2 className="w-3.5 h-3.5 text-emerald-700" />
                  Base de Dados da Empresa (Instantâneo · Sem custo de API)
                </span>
                <span className="text-emerald-700 font-semibold">{sugestoesLocais.length} encontrado{sugestoesLocais.length > 1 ? 's' : ''}</span>
              </div>

              {sugestoesLocais.map((item, index) => {
                const isFocused = indiceFocado === index;
                return (
                  <button
                    key={item.id}
                    type="button"
                    onClick={() => handleSelectLocal(item)}
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
                      <div className="flex items-center gap-2">
                        <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-extrabold bg-emerald-50 text-emerald-800 border border-emerald-200/90 whitespace-nowrap shadow-2xs">
                          <Sparkles className="w-3 h-3 text-emerald-600" />
                          Salvo no Banco · {item.total_entregas_realizadas} entregas
                        </span>
                        <span
                          role="button"
                          tabIndex={0}
                          aria-label={`Excluir endereço ${item.nome_identificador}`}
                          title="Excluir endereço"
                          aria-disabled={excluindoId === item.id}
                          onClick={(e) => handleExcluirLocal(e, item)}
                          onMouseDown={(e) => e.stopPropagation()}
                          onKeyDown={(e) => {
                            if (e.key === 'Enter' || e.key === ' ') handleExcluirLocal(e as unknown as React.MouseEvent, item);
                          }}
                          className="p-1.5 rounded-lg text-slate-400 hover:text-red-600 hover:bg-red-50 transition-colors cursor-pointer"
                        >
                          {excluindoId === item.id ? (
                            <Loader2 className="w-4 h-4 animate-spin" />
                          ) : (
                            <Trash2 className="w-4 h-4" />
                          )}
                        </span>
                      </div>
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
          )}

          {/* SEÇÃO 2: GOOGLE DEPOIS (APENAS SE NÃO HOUVER NO BANCO OU PARA NOVOS LOCAIS) */}
          {sugestoesGoogle.length > 0 && (
            <div className="p-2 space-y-1 border-t border-slate-100">
              <div className="px-3.5 py-2 flex items-center justify-between text-[11px] font-bold uppercase tracking-wider text-[#1D4ED8] bg-[#EEF4FF]/80 border-b border-[#DBEAFE] rounded-lg">
                <span className="flex items-center gap-2">
                  <Globe className="w-3.5 h-3.5 text-[#1D4ED8]" />
                  {sugestoesGoogle.some(s => s.origem === 'nominatim')
                    ? 'Endereços e Locais Verificados · Grande Florianópolis'
                    : 'Google Places · Novo Local na Grande Florianópolis'}
                </span>
                <span className="text-[#1D4ED8] font-semibold">{sugestoesGoogle.length} sugestões</span>
              </div>

              {sugestoesGoogle.map((item, index) => {
                const combinedIndex = sugestoesLocais.length + index;
                const isFocused = indiceFocado === combinedIndex;
                return (
                  <button
                    key={item.placeId}
                    type="button"
                    onClick={() => handleSelectGoogle(item)}
                    onMouseEnter={() => setIndiceFocado(combinedIndex)}
                    className={`w-full text-left p-3 rounded-xl flex items-center justify-between gap-4 transition-all cursor-pointer border ${
                      isFocused
                        ? 'bg-[#EEF4FF] border-[#1D4ED8]/30 shadow-xs ring-1 ring-[#1D4ED8]/20'
                        : 'border-transparent hover:bg-slate-50/80 hover:border-slate-100'
                    }`}
                  >
                    <div className="flex items-start gap-3 min-w-0 flex-1">
                      <div className="w-9 h-9 rounded-xl bg-orange-50 text-orange-600 flex items-center justify-center flex-shrink-0 mt-0.5 border border-orange-100 shadow-2xs">
                        <Globe className="w-4 h-4" />
                      </div>
                      <div className="min-w-0 flex-1">
                        <div className="font-extrabold text-[14px] text-[#0F1B2D] leading-snug">
                          {item.mainText}
                        </div>
                        <div className="text-xs text-slate-600 flex items-center gap-1.5 mt-1 font-medium truncate">
                          <MapPin className="w-3.5 h-3.5 text-slate-400 flex-shrink-0" />
                          <span>{item.secondaryText || item.fullText}</span>
                        </div>
                      </div>
                    </div>

                    <div className="flex-shrink-0">
                      <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-bold bg-blue-50 text-[#1D4ED8] border border-blue-200">
                        <Sparkles className="w-3 h-3 text-[#1D4ED8]" />
                        Gravar no Banco
                      </span>
                    </div>
                  </button>
                );
              })}
            </div>
          )}

          {/* VAZIO: NENHUM RESULTADO LOCAL NEM GOOGLE */}
          {sugestoesLocais.length === 0 && sugestoesGoogle.length === 0 && value.trim().length >= 2 && !carregando && (
            <div className="p-4 text-center text-xs space-y-1.5 text-slate-600 bg-slate-50/50">
              <div className="font-bold text-[#0F1B2D] text-sm">
                Nenhum resultado para "{value}"
              </div>
              <div className="text-xs text-slate-500 max-w-md mx-auto">
                Digite o endereço completo no campo abaixo para geocodificar e gravar automaticamente na base de dados da sua empresa.
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
};
