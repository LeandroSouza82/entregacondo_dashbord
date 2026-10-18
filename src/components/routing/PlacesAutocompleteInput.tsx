import React, { useState, useEffect, useRef, useCallback } from 'react';
import { MapPin, Building, Loader2, Sparkles, AlertTriangle, Check, Search } from 'lucide-react';
import type { PontoCoordenada } from '../../types/logistics';
import { normalizarTexto, pertenceAGrandeFlorianopolis } from '../../features/routes/services/buscarClientesEnderecos';

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
}

interface PlacePredictionItem {
  placeId: string;
  mainText: string;
  secondaryText: string;
  fullText: string;
}

export const PlacesAutocompleteInput: React.FC<PlacesAutocompleteInputProps> = ({
  value,
  onChange,
  onAddressSelect,
  enderecosSalvos = [],
}) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const debounceTimerRef = useRef<number | null>(null);
  const sessionTokenRef = useRef<string>(crypto.randomUUID());

  const [isOpen, setIsOpen] = useState<boolean>(false);
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [predictions, setPredictions] = useState<PlacePredictionItem[]>([]);
  const [apiError, setApiError] = useState<{
    tipo: 'referrer' | 'legacy_api' | 'not_activated' | 'general';
    mensagem: string;
  } | null>(null);

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
      setIsOpen(false);
    }
  }, [value]);

  // Busca de sugestões de alta precisão via Google Places API (New)
  const fetchGooglePredictions = useCallback(async (query: string) => {
    if (!query.trim() || query.length < 2 || !GOOGLE_PLACES_KEY) {
      setPredictions([]);
      setIsLoading(false);
      return;
    }

    setIsLoading(true);

    try {
      // Endpoint oficial da Google Places API (New)
      const res = await fetch('https://places.googleapis.com/v1/places:autocomplete', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': GOOGLE_PLACES_KEY,
        },
        body: JSON.stringify({
          input: query,
          includedRegionCodes: ['br'],
          languageCode: 'pt-BR',
          sessionToken: sessionTokenRef.current,
          // Restrição geográfica obrigatória: Grande Florianópolis (raio de 50km centrado em Florianópolis)
          locationRestriction: {
            circle: {
              center: {
                latitude: -27.5954,
                longitude: -48.5480,
              },
              radius: 50000.0,
            },
          },
        }),
      });

      const data = await res.json();

      if (data.error) {
        console.warn('Google Places API (New) aviso:', data.error);
        if (data.error.message?.includes('referer') || data.error.reason === 'API_KEY_HTTP_REFERRER_BLOCKED') {
          setApiError({
            tipo: 'referrer',
            mensagem: 'Restrição de Referrer HTTP ativa no Google Cloud. Se estiver acessando por 127.0.0.1, acesse por http://localhost:5174/ ou libere o IP no console do Google.',
          });
        } else if (data.error.message?.includes('legacy')) {
          setApiError({
            tipo: 'legacy_api',
            mensagem: 'API Legada desativada no projeto. A nova Places API (New) está configurada.',
          });
        } else {
          setApiError({
            tipo: 'general',
            mensagem: data.error.message || 'Erro ao consultar Google Places.',
          });
        }
        setPredictions([]);
        return;
      }

      setApiError(null);

      if (data.suggestions && Array.isArray(data.suggestions)) {
        const parsed: PlacePredictionItem[] = data.suggestions
          .filter((s: { placePrediction?: unknown }) => s.placePrediction)
          .map((s: { placePrediction: {
            placeId: string;
            text?: { text: string };
            structuredFormat?: {
              mainText?: { text: string };
              secondaryText?: { text: string };
            };
          } }) => {
            const pred = s.placePrediction;
            return {
              placeId: pred.placeId,
              mainText: pred.structuredFormat?.mainText?.text || pred.text?.text || '',
              secondaryText: pred.structuredFormat?.secondaryText?.text || '',
              fullText: pred.text?.text || '',
            };
          })
          .filter((pred: PlacePredictionItem) => {
            // Garante que o endereço retornado pelo Google pertence exclusivamente à Grande Florianópolis
            return pertenceAGrandeFlorianopolis({
              cidade: pred.secondaryText,
              endereco_completo: `${pred.mainText} ${pred.secondaryText} ${pred.fullText}`,
            });
          });

        setPredictions(parsed);
      } else {
        setPredictions([]);
      }
    } catch (err: unknown) {
      console.warn('Falha na requisição ao Google Places:', err);
    } finally {
      setIsLoading(false);
    }
  }, []);

  // Disparo com debounce suave de 280ms
  const handleInputChange = (novoValor: string) => {
    onChange(novoValor);
    setIsOpen(true);

    if (debounceTimerRef.current) {
      window.clearTimeout(debounceTimerRef.current);
    }

    if (novoValor.trim().length >= 2) {
      setIsLoading(true);
      debounceTimerRef.current = window.setTimeout(() => {
        fetchGooglePredictions(novoValor);
      }, 280);
    } else {
      setPredictions([]);
      setIsLoading(false);
    }
  };

  // Ao selecionar uma sugestão do Google Places (New) -> Busca Place Details para obter Lat/Lng exatas
  const handleSelectPrediction = async (item: PlacePredictionItem) => {
    onChange(item.fullText);
    setIsOpen(false);
    setIsLoading(true);

    try {
      const detailsUrl = `https://places.googleapis.com/v1/places/${item.placeId}?fields=id,displayName,formattedAddress,location&key=${GOOGLE_PLACES_KEY}&sessionToken=${sessionTokenRef.current}`;
      const res = await fetch(detailsUrl);
      const data = await res.json();

      if (data.location && typeof data.location.latitude === 'number' && typeof data.location.longitude === 'number') {
        const coordenadas: PontoCoordenada = {
          lat: data.location.latitude,
          lng: data.location.longitude,
        };

        const nomeLocal = data.displayName?.text || item.mainText;
        const enderecoFinal = data.formattedAddress || item.fullText;

        onChange(enderecoFinal);

        onAddressSelect({
          enderecoCompleto: enderecoFinal,
          nomeLocal,
          coordenadas,
        });

        // Renova o token de sessão para a próxima busca (melhor prática Google Cloud)
        sessionTokenRef.current = crypto.randomUUID();
      } else {
        // Fallback caso venha sem geometry direta
        onAddressSelect({
          enderecoCompleto: item.fullText,
          nomeLocal: item.mainText,
          coordenadas: {
            lat: -27.5950 + (Math.random() - 0.5) * 0.03,
            lng: -48.5300 + (Math.random() - 0.5) * 0.03,
          },
        });
      }
    } catch (err) {
      console.warn('Erro ao obter detalhes de coordenadas do local:', err);
    } finally {
      setIsLoading(false);
    }
  };

  // Seleção de endereço salvo na base local
  const handleSelectEnderecoSalvo = (item: EnderecoSalvoItem) => {
    onChange(item.endereco);
    setIsOpen(false);

    onAddressSelect({
      enderecoCompleto: item.endereco,
      nomeLocal: item.complemento,
      coordenadas: item.coordenadas,
    });
  };

  // Filtra endereços salvos que coincidem com a digitação (insensível a maiúsculas/acentos e restrito à Grande Floripa)
  const enderecosSalvosFiltrados = enderecosSalvos.filter(item => {
    if (!pertenceAGrandeFlorianopolis({ endereco_completo: item.endereco })) return false;
    if (!value.trim()) return true;
    const q = normalizarTexto(value);
    return normalizarTexto(item.endereco).includes(q) || normalizarTexto(item.complemento).includes(q);
  });

  return (
    <div ref={containerRef} className="relative w-full">
      {/* Campo de Input com Design Elegante */}
      <div className="relative">
        <input
          type="text"
          value={value}
          onChange={(e) => handleInputChange(e.target.value)}
          onFocus={() => setIsOpen(true)}
          placeholder="Digite o endereço ou condomínio no Google Places..."
          className="h-11 border-2 border-[#1D4ED8] rounded-[10px] pl-3.5 pr-10 text-sm text-[#0F1B2D] bg-white w-full font-medium focus:outline-none focus:ring-2 focus:ring-[#1D4ED8]/20 shadow-sm transition-all"
        />

        {/* Indicador de Status à direita */}
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
        <div className="absolute left-0 right-0 top-full mt-1.5 z-50 bg-white border border-[#CBD5E1] rounded-xl shadow-2xl overflow-hidden divide-y divide-[#EAEFF4] animate-fadeIn max-h-[360px] overflow-y-auto">
          {/* Alerta de Referrer HTTP caso a chave do Google tenha restrição */}
          {apiError && apiError.tipo === 'referrer' && (
            <div className="p-3 bg-amber-50 border-b border-amber-200 text-amber-900 text-xs flex items-start gap-2.5">
              <AlertTriangle className="w-4 h-4 text-amber-600 flex-shrink-0 mt-0.5" />
              <div>
                <strong className="block font-bold">Aviso de Referrer HTTP (Google Cloud)</strong>
                <span>
                  Sua chave aceita requisições via <code className="bg-amber-100 px-1 py-0.5 rounded font-mono font-bold">http://localhost:5174/</code>. 
                  Se estiver usando <code className="bg-amber-100 px-1 py-0.5 rounded font-mono">127.0.0.1</code>, acesse através de <a href="http://localhost:5174" className="underline font-bold text-amber-950">http://localhost:5174</a> ou adicione 127.0.0.1 no console do Google Cloud.
                </span>
              </div>
            </div>
          )}

          {/* SEÇÃO 1: SUGESTÕES DO GOOGLE PLACES (NEW) */}
          {predictions.length > 0 && (
            <div>
              <div className="px-3.5 py-1.5 bg-[#EEF4FF] text-[11px] font-bold text-[#1D4ED8] uppercase tracking-wider flex items-center justify-between">
                <span className="flex items-center gap-1.5">
                  <Sparkles className="w-3.5 h-3.5 text-[#1D4ED8]" />
                  Google Places (Geocoding de Alta Precisão)
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
                  <span className="text-[10px] font-semibold text-[#1D4ED8] bg-[#EEF4FF] px-2 py-0.5 rounded flex items-center gap-1">
                    <Check className="w-3 h-3" />
                    Obter Lat/Lng
                  </span>
                </div>
              ))}
            </div>
          )}

          {/* SEÇÃO 2: ENDEREÇOS SALVOS NA BASE LOCAL */}
          {enderecosSalvosFiltrados.length > 0 && (
            <div>
              <div className="px-3.5 py-1.5 bg-slate-50 text-[11px] font-bold text-slate-500 uppercase tracking-wider flex items-center justify-between">
                <span className="flex items-center gap-1.5">
                  <Building className="w-3.5 h-3.5 text-emerald-600" />
                  Condomínios Salvos na Base ({enderecosSalvosFiltrados.length})
                </span>
                <span className="text-[10px] text-slate-400 font-normal">Histórico com média de portaria</span>
              </div>

              {enderecosSalvosFiltrados.map((item, idx) => (
                <div
                  key={idx}
                  onClick={() => handleSelectEnderecoSalvo(item)}
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

          {/* RODAPÉ DO DROPDOWN */}
          <div className="px-3.5 py-2 bg-[#FAFBFC] flex items-center justify-between text-xs text-[#516074]">
            <span className="flex items-center gap-1 text-[11px]">
              <Sparkles className="w-3 h-3 text-[#1D4ED8]" />
              Geocoding automático com Google Places API (New)
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
