import React, { useState, useEffect, useRef, useCallback } from 'react';
import { MapPin, Building, Loader2, Sparkles, Search, Globe } from 'lucide-react';
import type { PontoCoordenada } from '../../types/logistics';
import type { ClienteEnderecoItem } from '../../features/routes/types/clienteEndereco';
import { 
  normalizarTexto, 
  pertenceAGrandeFlorianopolis, 
  buscarClientesEnderecos,
  buscarSugestoesNominatim
} from '../../features/routes/services/buscarClientesEnderecos';
import { geocodificarEndereco } from '../../features/routes/services/routeOptimization';

const GOOGLE_PLACES_KEY = import.meta.env.VITE_GOOGLE_PLACES_KEY || '';

export interface EnderecoSalvoItem {
  endereco: string;
  complemento: string;
  entregasContagem: number;
  coordenadas: PontoCoordenada;
}

interface PlacesAutocompleteInputProps {
  value: string;
  onChange: (value: string) => void;
  onAddressSelect: (data: {
    enderecoCompleto: string;
    nomeLocal?: string;
    coordenadas: PontoCoordenada;
  }) => void;
  enderecosSalvos?: EnderecoSalvoItem[];
  empresaId?: string;
  placeholder?: string;
  name?: string;
}

export interface PlacePredictionItem {
  placeId: string;
  mainText: string;
  secondaryText: string;
  fullText: string;
  coordenadas?: PontoCoordenada;
  origem?: 'google' | 'nominatim' | 'banco';
}

export const PlacesAutocompleteInput: React.FC<PlacesAutocompleteInputProps> = ({
  value,
  onChange,
  onAddressSelect,
  enderecosSalvos = [],
  empresaId,
  placeholder,
  name,
}) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const debounceTimerRef = useRef<number | null>(null);
  const sessionTokenRef = useRef<string>(crypto.randomUUID());

  const [isOpen, setIsOpen] = useState<boolean>(false);
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [predictions, setPredictions] = useState<PlacePredictionItem[]>([]);
  const [enderecosDoBanco, setEnderecosDoBanco] = useState<ClienteEnderecoItem[]>([]);

  // Fecha o dropdown ao clicar fora do componente
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  // Quando o valor for limpo externamente, fecha o dropdown e reseta predições
  useEffect(() => {
    if (!value) {
      setPredictions([]);
      setEnderecosDoBanco([]);
      setIsOpen(false);
    }
  }, [value]);

  // Busca resiliente: tenta Google Places e faz fallback para Nominatim se Google falhar ou esgotar cota
  const fetchGooglePredictions = useCallback(async (query: string) => {
    if (!query.trim() || query.length < 2) {
      setPredictions([]);
      return;
    }

    let googleResults: PlacePredictionItem[] = [];

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

        if (res.status === 429) {
          // Cota excedida no Google Cloud: segue silenciosamente para a Camada 3 de Fallback Aberto
        } else if (res.ok) {
          const data = await res.json();
          if (data.suggestions && Array.isArray(data.suggestions)) {
            googleResults = data.suggestions
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
              .filter((pred: PlacePredictionItem) => {
                return pertenceAGrandeFlorianopolis({
                  cidade: pred.secondaryText,
                  endereco_completo: `${pred.mainText} ${pred.secondaryText} ${pred.fullText}`,
                });
              });
          }
        }
      } catch (err) {
        // Falha tratada silenciosamente
      }
    }

    // CAMADA 3: Fallback Geocoding / Nominatim se o Google não tiver retornado resultados
    if (googleResults.length > 0) {
      setPredictions(googleResults);
    } else {
      try {
        const nomResults = await buscarSugestoesNominatim(query);
        const mapped: PlacePredictionItem[] = nomResults.map(n => ({
          placeId: n.placeId,
          mainText: n.mainText,
          secondaryText: n.secondaryText,
          fullText: n.fullText,
          coordenadas: n.coordenadas,
          origem: 'nominatim',
        }));
        setPredictions(mapped);
      } catch {
        setPredictions([]);
      }
    }
  }, []);

  // Busca "Banco Primeiro, Google/Nominatim Depois" com debounce protetivo de 480ms
  const handleInputChange = (novoValor: string) => {
    onChange(novoValor);
    setIsOpen(true);

    if (debounceTimerRef.current) {
      window.clearTimeout(debounceTimerRef.current);
    }

    if (novoValor.trim().length >= 2) {
      setIsLoading(true);
      debounceTimerRef.current = window.setTimeout(async () => {
        try {
          // Executa em paralelo a consulta local no banco e o autocomplete Google/Nominatim
          const [doBanco] = await Promise.all([
            buscarClientesEnderecos(novoValor, empresaId).catch(() => []),
            fetchGooglePredictions(novoValor).catch(() => {}),
          ]);
          setEnderecosDoBanco(doBanco || []);
        } finally {
          setIsLoading(false);
        }
      }, 480);
    } else {
      setPredictions([]);
      setEnderecosDoBanco([]);
      setIsLoading(false);
    }
  };

  // Seleção de sugestão (Google Places ou Nominatim) -> Geocoding e preenchimento
  const handleSelectPrediction = async (item: PlacePredictionItem) => {
    onChange(item.fullText);
    setIsOpen(false);
    setIsLoading(true);

    try {
      // Se a sugestão já tiver coordenadas (ex: proveniente do Nominatim), aplica imediatamente sem custo
      if (item.coordenadas && typeof item.coordenadas.lat === 'number' && !isNaN(item.coordenadas.lat)) {
        onAddressSelect({
          enderecoCompleto: item.fullText,
          nomeLocal: item.mainText,
          coordenadas: item.coordenadas,
        });
        return;
      }

      // Se for Google Places, busca os detalhes com fallback
      let coordenadas: PontoCoordenada = {
        lat: -27.5954,
        lng: -48.5480,
      };

      if (GOOGLE_PLACES_KEY && item.origem === 'google') {
        try {
          const detailsUrl = `https://places.googleapis.com/v1/places/${item.placeId}?fields=id,displayName,formattedAddress,location&key=${GOOGLE_PLACES_KEY}&sessionToken=${sessionTokenRef.current}`;
          const res = await fetch(detailsUrl);
          const data = await res.json();
          if (data.location?.latitude && data.location?.longitude) {
            coordenadas = {
              lat: data.location.latitude,
              lng: data.location.longitude,
            };
          } else {
            const geo = await geocodificarEndereco(item.fullText);
            if (geo?.coordenadas) coordenadas = geo.coordenadas;
          }
        } catch {
          const geo = await geocodificarEndereco(item.fullText);
          if (geo?.coordenadas) coordenadas = geo.coordenadas;
        }
      } else {
        const geo = await geocodificarEndereco(item.fullText);
        if (geo?.coordenadas) coordenadas = geo.coordenadas;
      }

      const nomeLocal = item.mainText;
      const enderecoFinal = item.fullText;

      onChange(enderecoFinal);
      onAddressSelect({
        enderecoCompleto: enderecoFinal,
        nomeLocal,
        coordenadas,
      });

      sessionTokenRef.current = crypto.randomUUID();
    } catch (err) {
      console.warn('Erro ao obter detalhes de coordenadas do local:', err);
    } finally {
      setIsLoading(false);
    }
  };

  // Tolerância a falhas: se o usuário digitou e clicou fora sem selecionar do dropdown
  const handleInputBlur = () => {
    setTimeout(async () => {
      if (value.trim().length >= 4) {
        try {
          const geo = await geocodificarEndereco(value.trim());
          if (geo && geo.coordenadas) {
            onAddressSelect({
              enderecoCompleto: geo.endereco || value.trim(),
              nomeLocal: geo.nome || value.trim().split(',')[0].trim(),
              coordenadas: geo.coordenadas,
            });
          }
        } catch (e) {
          console.warn('Geocodificação silenciosa no blur:', e);
        }
      }
    }, 250);
  };

  // Seleção de item da base do banco
  const handleSelectDoBanco = (item: ClienteEnderecoItem) => {
    onChange(item.endereco_completo);
    setIsOpen(false);

    onAddressSelect({
      enderecoCompleto: item.endereco_completo,
      nomeLocal: item.nome_identificador,
      coordenadas: {
        lat: Number(item.latitude),
        lng: Number(item.longitude),
      },
    });
  };

  // Filtra endereços salvos passados via prop (compatibilidade retroativa)
  const enderecosSalvosFiltrados = enderecosSalvos.filter(item => {
    if (!pertenceAGrandeFlorianopolis({ endereco_completo: item.endereco })) return false;
    if (!value.trim()) return true;
    const q = normalizarTexto(value);
    return normalizarTexto(item.endereco).includes(q) || normalizarTexto(item.complemento).includes(q);
  });

  return (
    <div ref={containerRef} className="relative w-full">
      <div className="relative">
        <input
          type="text"
          name={name || "endereco_places_busca_ec"}
          autoComplete="off"
          autoCorrect="off"
          spellCheck={false}
          value={value}
          onChange={(e) => handleInputChange(e.target.value)}
          onFocus={() => setIsOpen(true)}
          onBlur={handleInputBlur}
          onKeyDown={async (e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              if (predictions.length > 0) {
                void handleSelectPrediction(predictions[0]);
              } else if (enderecosDoBanco.length > 0) {
                handleSelectDoBanco(enderecosDoBanco[0]);
              } else if (value.trim().length >= 3) {
                setIsLoading(true);
                try {
                  const geo = await geocodificarEndereco(value.trim());
                  if (geo && geo.coordenadas) {
                    onChange(geo.endereco);
                    setIsOpen(false);
                    onAddressSelect({
                      enderecoCompleto: geo.endereco,
                      nomeLocal: geo.nome,
                      coordenadas: geo.coordenadas,
                    });
                  }
                } finally {
                  setIsLoading(false);
                }
              }
            }
          }}
          placeholder={placeholder || "Digite o endereço ou condomínio no Google Places..."}
          className="h-11 border-2 border-[#1D4ED8] rounded-[10px] pl-3.5 pr-10 text-sm text-[#0F1B2D] bg-white w-full font-medium focus:outline-none focus:ring-2 focus:ring-[#1D4ED8]/20 shadow-sm transition-all"
        />

        <div className="absolute right-3 top-1/2 -translate-y-1/2 flex items-center gap-1.5 pointer-events-none">
          {isLoading ? (
            <Loader2 className="w-4 h-4 text-[#1D4ED8] animate-spin" />
          ) : GOOGLE_PLACES_KEY ? (
            <Sparkles className="w-4 h-4 text-[#1D4ED8]" />
          ) : (
            <Search className="w-4 h-4 text-slate-400" />
          )}
        </div>
      </div>

      {/* Dropdown Inteligente de Resultados */}
      {isOpen && (
        <div className="absolute left-0 right-0 top-full mt-1.5 z-50 bg-white border border-[#CBD5E1] rounded-xl shadow-2xl overflow-hidden divide-y divide-[#EAEFF4] animate-fadeIn max-h-[380px] overflow-y-auto">
          {/* PRIORIDADE 1: BANCO PRIMEIRO (ENDEREÇOS DA BASE LOCAL - SEM CUSTO) */}
          {enderecosDoBanco.length > 0 && (
            <div>
              <div className="px-3.5 py-1.5 bg-emerald-50 text-[11px] font-bold text-emerald-800 uppercase tracking-wider flex items-center justify-between">
                <span className="flex items-center gap-1.5">
                  <Building className="w-3.5 h-3.5 text-emerald-700" />
                  Base da Empresa (Instantâneo · Sem custo de API)
                </span>
                <span className="text-[10px] text-emerald-700 font-semibold">{enderecosDoBanco.length} salvos</span>
              </div>

              {enderecosDoBanco.map((item) => (
                <div
                  key={item.id}
                  onClick={() => handleSelectDoBanco(item)}
                  className="flex items-center gap-3 p-3 hover:bg-[#EEF4FF] cursor-pointer transition-colors"
                >
                  <div className="w-7 h-7 rounded-full bg-emerald-100 flex items-center justify-center flex-shrink-0">
                    <Building className="w-3.5 h-3.5 text-emerald-700" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="font-bold text-sm text-[#0F1B2D] truncate">
                      {item.nome_identificador}
                    </div>
                    <div className="text-xs text-[#516074] truncate">
                      {item.endereco_completo}
                    </div>
                  </div>
                  <span className="px-2 py-0.5 rounded-full bg-[#DDF3E4] text-[#14532D] text-xs font-bold whitespace-nowrap">
                    Salvo no Banco
                  </span>
                </div>
              ))}
            </div>
          )}

          {/* COMPATIBILIDADE: ENDEREÇOS SALVOS PASSADOS VIA PROPS */}
          {enderecosSalvosFiltrados.length > 0 && enderecosDoBanco.length === 0 && (
            <div>
              <div className="px-3.5 py-1.5 bg-slate-50 text-[11px] font-bold text-slate-500 uppercase tracking-wider flex items-center justify-between">
                <span className="flex items-center gap-1.5">
                  <Building className="w-3.5 h-3.5 text-emerald-600" />
                  Condomínios Salvos na Base ({enderecosSalvosFiltrados.length})
                </span>
              </div>

              {enderecosSalvosFiltrados.map((item, idx) => (
                <div
                  key={idx}
                  onClick={() => {
                    onChange(item.endereco);
                    setIsOpen(false);
                    onAddressSelect({
                      enderecoCompleto: item.endereco,
                      nomeLocal: item.complemento,
                      coordenadas: item.coordenadas,
                    });
                  }}
                  className="flex items-center gap-3 p-3 hover:bg-[#EEF4FF] cursor-pointer transition-colors"
                >
                  <div className="w-7 h-7 rounded-full bg-emerald-50 flex items-center justify-center flex-shrink-0">
                    <Building className="w-3.5 h-3.5 text-emerald-600" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="font-bold text-sm text-[#0F1B2D] truncate">
                      {item.endereco}
                    </div>
                    <div className="text-xs text-[#516074]">
                      {item.complemento}
                    </div>
                  </div>
                  <span className="px-2 py-0.5 rounded-full bg-[#DDF3E4] text-[#14532D] text-xs font-bold whitespace-nowrap">
                    Salvo · {item.entregasContagem} entregas
                  </span>
                </div>
              ))}
            </div>
          )}

          {/* PRIORIDADE 2: GOOGLE PLACES (NOVO LOCAL COM GEOCODING E AUTO-SALVAMENTO) */}
          {predictions.length > 0 && (
            <div>
              <div className="px-3.5 py-1.5 bg-[#EEF4FF] text-[11px] font-bold text-[#1D4ED8] uppercase tracking-wider flex items-center justify-between">
                <span className="flex items-center gap-1.5">
                  <Globe className="w-3.5 h-3.5 text-[#1D4ED8]" />
                  {predictions[0]?.origem === 'nominatim' ? 'Endereços Verificados · Grande Florianópolis' : 'Google Places · Novo Local na Grande Florianópolis'}
                </span>
                <span className="text-[10px] lowercase font-semibold opacity-75">{predictions.length} sugestões</span>
              </div>

              {predictions.map((item) => (
                <div
                  key={item.placeId}
                  onClick={() => handleSelectPrediction(item)}
                  className="flex items-start gap-3 p-3 hover:bg-[#F3F7FF] cursor-pointer transition-colors border-b border-slate-50 last:border-b-0"
                >
                  <div className="w-7 h-7 rounded-full bg-[#EEF4FF] flex items-center justify-center flex-shrink-0 mt-0.5">
                    <MapPin className="w-3.5 h-3.5 text-[#1D4ED8]" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="font-bold text-sm text-[#0F1B2D] truncate">
                      {item.mainText}
                    </div>
                    <div className="text-xs text-[#516074] truncate mt-0.5">
                      {item.secondaryText || item.fullText}
                    </div>
                  </div>
                  <span className="text-[10px] font-bold text-[#1D4ED8] bg-blue-50 border border-blue-200 px-2.5 py-1 rounded-full flex items-center gap-1 shadow-2xs">
                    <Sparkles className="w-3 h-3 text-[#1D4ED8]" />
                    Gravar no Banco
                  </span>
                </div>
              ))}
            </div>
          )}

          {/* CAMADA 4: CONFIRMAÇÃO DE ENDEREÇO DIGITADO (FALLBACK IMEDIATO SEM TRAVAR) */}
          {value.trim().length >= 3 && (
            <div
              onClick={async () => {
                setIsLoading(true);
                try {
                  const geo = await geocodificarEndereco(value.trim());
                  const enderecoFinal = geo?.endereco || value.trim();
                  const nomeLocal = geo?.nome || value.trim().split(',')[0].trim();
                  const coordenadas = geo?.coordenadas || { lat: -27.5954, lng: -48.5480 };

                  onChange(enderecoFinal);
                  setIsOpen(false);
                  onAddressSelect({
                    enderecoCompleto: enderecoFinal,
                    nomeLocal,
                    coordenadas,
                  });
                } finally {
                  setIsLoading(false);
                }
              }}
              className="flex items-center justify-between p-3 bg-blue-50/70 hover:bg-blue-100/80 text-[#1D4ED8] cursor-pointer transition-colors border-t border-blue-100"
            >
              <div className="flex items-center gap-2.5 min-w-0 flex-1">
                <MapPin className="w-4 h-4 text-[#1D4ED8] flex-shrink-0" />
                <div className="truncate">
                  <span className="font-bold text-xs text-[#0F1B2D]">Usar este endereço: </span>
                  <span className="text-xs text-[#1D4ED8] font-medium">"{value.trim()}"</span>
                </div>
              </div>
              <span className="text-[11px] font-bold text-[#1D4ED8] bg-white border border-blue-200 px-2.5 py-1 rounded-md shadow-2xs whitespace-nowrap ml-2">
                Confirmar Endereço
              </span>
            </div>
          )}

          {/* RODAPÉ DO DROPDOWN */}
          <div className="px-3.5 py-2 bg-[#FAFBFC] flex items-center justify-between text-xs text-[#516074]">
            <span className="flex items-center gap-1 text-[11px]">
              <Sparkles className="w-3 h-3 text-[#1D4ED8]" />
              Geocoding automático com Google Places API (New) · Salva na base própria
            </span>
            <button
              type="button"
              onClick={() => setIsOpen(false)}
              className="text-[#1D4ED8] hover:underline font-bold text-xs"
            >
              Fechar
            </button>
          </div>
        </div>
      )}
    </div>
  );
};
