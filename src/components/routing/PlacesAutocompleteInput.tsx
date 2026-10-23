import { coordenadasValidas, erroLocalizacaoEndereco } from '../../features/routes/services/addressCoordinates';
import React, { useState, useEffect, useRef, useCallback } from 'react';
import { MapPin, Building, Loader2, Sparkles, Search, Globe, Bookmark, Check } from 'lucide-react';
import type { PontoCoordenada } from '../../types/logistics';
import type { ClienteEnderecoItem } from '../../features/routes/types/clienteEndereco';
import { 
  normalizarTexto, 
  pertenceAGrandeFlorianopolis, 
  buscarSugestoesNominatim
} from '../../features/routes/services/buscarClientesEnderecos';
import { 
  buscarEnderecosNoBanco, 
  verificarEnderecoJaSalvo, 
  salvarEnderecoCache 
} from '../../features/routes/services/savedAddressesService';
import { geocodificarEndereco } from '../../features/routes/services/routeOptimization';

const GOOGLE_PLACES_KEY = '';

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
  coordenadas?: PontoCoordenada | null;
  nomeCondominio?: string;
  blocoApto?: string;
  showSaveButton?: boolean;
  onSalvoComSucesso?: (item: ClienteEnderecoItem) => void;
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
  coordenadas,
  nomeCondominio,
  blocoApto,
  showSaveButton = false,
  onSalvoComSucesso,
}) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const debounceTimerRef = useRef<number | null>(null);
  const sessionTokenRef = useRef<string>(crypto.randomUUID());
  const lastSelectedPlaceIdRef = useRef<string | null>(null);
  const selectionRevisionRef = useRef(0);
  const internalCoordsRef = useRef<PontoCoordenada | null>(null);

  const [isOpen, setIsOpen] = useState<boolean>(false);
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [isSaving, setIsSaving] = useState<boolean>(false);
  const [isAlreadySaved, setIsAlreadySaved] = useState<boolean>(false);
  const [erroSalvar, setErroSalvar] = useState<string | null>(null);
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
      setIsAlreadySaved(false);
      setIsOpen(false);
    } else if (value.trim().length >= 4) {
      // Verifica se o endereço atualmente preenchido já está registrado no banco
      let active = true;
      verificarEnderecoJaSalvo(value, empresaId).then(salvo => {
        if (active) {
          setIsAlreadySaved(Boolean(salvo));

        }
      }).catch(() => {});
      return () => { active = false; };
    }
  }, [value, empresaId]);

  // Sincroniza coordenadas passadas externamente
  useEffect(() => {
    internalCoordsRef.current = coordenadas ?? null;
  }, [coordenadas]);

  // Busca resiliente: tenta Google Places e faz fallback para Nominatim se Google falhar ou esgotar cota
  const fetchGooglePredictions = useCallback(async (query: string, revision: number) => {
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
      if (revision === selectionRevisionRef.current) setPredictions(googleResults);
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
        if (revision === selectionRevisionRef.current) setPredictions(mapped);
      } catch {
        if (revision === selectionRevisionRef.current) setPredictions([]);
      }
    }
  }, []);

  // PRIORIDADE AO BANCO: Busca primeiro na base do Supabase com ilike, economizando requisições do Google
  const handleInputChange = (novoValor: string) => {
    const revision = ++selectionRevisionRef.current;
    setPredictions([]);
    setEnderecosDoBanco([]);
    internalCoordsRef.current = null;
    lastSelectedPlaceIdRef.current = null;
    setErroSalvar(null);
    setIsAlreadySaved(false);
    onChange(novoValor);
    setIsOpen(true);

    if (debounceTimerRef.current) {
      window.clearTimeout(debounceTimerRef.current);
    }

    if (novoValor.trim().length >= 2) {
      setIsLoading(true);
      debounceTimerRef.current = window.setTimeout(async () => {
        try {
          // 1. PRIMEIRO: Consulta local no Supabase (zero chamadas de API externa)
          const doBanco = await buscarEnderecosNoBanco(novoValor, empresaId).catch(() => []);
          if (revision !== selectionRevisionRef.current) return;
          setEnderecosDoBanco(doBanco || []);

          // Checa se algum item retornado tem correspondência exata
          const normDigitado = normalizarTexto(novoValor);
          const correspondenciaExata = (doBanco || []).some(item => {
            const normSalvo = normalizarTexto(item.endereco_completo || '');
            const normNome = normalizarTexto(item.nome_identificador || '');
            return normSalvo === normDigitado || normNome === normDigitado;
          });

          if (correspondenciaExata) {
            setIsAlreadySaved(true);
            // Economia máxima: correspondência exata encontrada no banco, não consulta o Google Places
            setPredictions([]);
          } else {
            // 2. SEGUNDO: Somente se não houver correspondência exata ou se usuário digitou além dos salvos
            await fetchGooglePredictions(novoValor, revision).catch(() => {});
          }
        } finally {
          if (revision === selectionRevisionRef.current) setIsLoading(false);
        }
      }, 350);
    } else {
      setPredictions([]);
      setEnderecosDoBanco([]);
      setIsAlreadySaved(false);
      setIsLoading(false);
    }
  };

  // Seleção de sugestão externa (Google Places ou Nominatim) -> Geocoding e preenchimento
  const handleSelectPrediction = async (item: PlacePredictionItem) => {
    const revision = ++selectionRevisionRef.current;
    setErroSalvar(null);
    onChange(item.fullText);
    setIsOpen(false);
    setIsLoading(true);
    lastSelectedPlaceIdRef.current = item.placeId;

    try {
      // Se a sugestão já tiver coordenadas (ex: proveniente do Nominatim), aplica imediatamente sem custo
      if (coordenadasValidas(item.coordenadas)) {
        internalCoordsRef.current = item.coordenadas;
        onAddressSelect({
          enderecoCompleto: item.fullText,
          nomeLocal: item.mainText,
          coordenadas: item.coordenadas,
        });

        // Checa se por acaso já existe salvo
        const salvo = await verificarEnderecoJaSalvo(item.fullText, empresaId);
        setIsAlreadySaved(Boolean(salvo));
        return;
      }

      // Se for Google Places, busca os detalhes com fallback
      let coords: PontoCoordenada | null = null;

      if (GOOGLE_PLACES_KEY && item.origem === 'google') {
        try {
          const detailsUrl = `https://places.googleapis.com/v1/places/${item.placeId}?fields=id,displayName,formattedAddress,location&key=${GOOGLE_PLACES_KEY}&sessionToken=${sessionTokenRef.current}`;
          const res = await fetch(detailsUrl);
          const data = await res.json();
          if (data.location?.latitude && data.location?.longitude) {
            coords = {
              lat: data.location.latitude,
              lng: data.location.longitude,
            };
          } else {
            const geo = await geocodificarEndereco(item.fullText);
            if (geo?.coordenadas) coords = geo.coordenadas;
          }
        } catch {
          const geo = await geocodificarEndereco(item.fullText);
          if (geo?.coordenadas) coords = geo.coordenadas;
        }
      } else {
        const geo = await geocodificarEndereco(item.fullText);
        if (geo?.coordenadas) coords = geo.coordenadas;
      }

      if (revision !== selectionRevisionRef.current) return;
      if (!coordenadasValidas(coords)) {
        setErroSalvar(erroLocalizacaoEndereco);
        return;
      }
      const nomeLocal = item.mainText;
      const enderecoFinal = item.fullText;
      internalCoordsRef.current = coords;

      onChange(enderecoFinal);
      onAddressSelect({
        enderecoCompleto: enderecoFinal,
        nomeLocal,
        coordenadas: coords,
      });

      // Checa se o local já existe no banco
      const salvo = await verificarEnderecoJaSalvo(enderecoFinal, empresaId);
      setIsAlreadySaved(Boolean(salvo));

      sessionTokenRef.current = crypto.randomUUID();
    } catch (err) {
      console.warn('Erro ao obter detalhes de coordenadas do local:', err);
    } finally {
      if (revision === selectionRevisionRef.current) setIsLoading(false);
    }
  };

  // Seleção direta de item vindo do banco: usa diretamente as coordenadas sem gastar API
  const handleSelectDoBanco = (item: ClienteEnderecoItem) => {
    selectionRevisionRef.current++;
    setErroSalvar(null);
    onChange(item.endereco_completo);
    setIsOpen(false);
    setIsAlreadySaved(true);
    const coords: PontoCoordenada = {
      lat: Number(item.latitude),
      lng: Number(item.longitude),
    };
    if (!coordenadasValidas(coords)) {
      setErroSalvar(erroLocalizacaoEndereco);
      return;
    }
    internalCoordsRef.current = coords;

    onAddressSelect({
      enderecoCompleto: item.endereco_completo,
      nomeLocal: item.nome_identificador,
      coordenadas: coords,
    });
  };

  // AÇÃO DIRETA: Gravação do endereço no banco com feedback visual
  const handleSalvarEnderecoDireto = async (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();

    const enderecoLimpo = value.trim();
    if (!enderecoLimpo || isSaving || isAlreadySaved) return;

    setIsSaving(true);
    setErroSalvar(null);
    try {
      let coords = coordenadas || internalCoordsRef.current;
      let label = (nomeCondominio || '').trim();

      if (!coords) {
        const geo = await geocodificarEndereco(enderecoLimpo);
        if (geo?.coordenadas) {
          coords = geo.coordenadas;
          if (!label) label = geo.nome || enderecoLimpo.split(',')[0].trim();
        }
      }

      if (!coordenadasValidas(coords)) throw new Error(erroLocalizacaoEndereco);

      if (!label) {
        label = enderecoLimpo.split(',')[0].trim() || 'Condomínio / Cliente';
      }

      const salvo = await salvarEnderecoCache({
        empresa_id: empresaId,
        label,
        nome_identificador: label,
        full_address: enderecoLimpo,
        endereco_completo: enderecoLimpo,
        coordenadas: coords,
        lat: coords.lat,
        lng: coords.lng,
        destinatario_padrao: blocoApto || null,
        place_id: lastSelectedPlaceIdRef.current || null,
      });

      setIsAlreadySaved(true);
      setEnderecosDoBanco(prev => [salvo, ...prev.filter(p => p.id !== salvo.id)]);
      onSalvoComSucesso?.(salvo);
    } catch (err) {
      setErroSalvar(err instanceof Error ? err.message : 'Não foi possível salvar o endereço.');
    } finally {
      setIsSaving(false);
    }
  };

  // Filtra endereços salvos passados via prop (compatibilidade retroativa)
  const enderecosSalvosFiltrados = enderecosSalvos.filter(item => {
    if (!pertenceAGrandeFlorianopolis({ endereco_completo: item.endereco })) return false;
    if (!value.trim()) return true;
    const q = normalizarTexto(value);
    return normalizarTexto(item.endereco).includes(q) || normalizarTexto(item.complemento).includes(q);
  });

  const canShowSaveButton = showSaveButton && value.trim().length >= 3;

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
          onKeyDown={async (e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              if (predictions.length > 0) {
                void handleSelectPrediction(predictions[0]);
              } else if (enderecosDoBanco.length > 0) {
                handleSelectDoBanco(enderecosDoBanco[0]);
              } else if (value.trim().length >= 3) {
                void handleSelectPrediction({ placeId: '', mainText: value.trim().split(',')[0],
                  secondaryText: '', fullText: value.trim() });
              }
            }
          }}
          placeholder={placeholder || "Digite o endereço ou condomínio no Google Places..."}
          className={`h-11 border-2 border-[#1D4ED8] rounded-[10px] pl-3.5 ${
            canShowSaveButton ? 'pr-28' : 'pr-10'
          } text-sm text-[#0F1B2D] bg-white w-full font-medium focus:outline-none focus:ring-2 focus:ring-[#1D4ED8]/20 shadow-sm transition-all`}
        />

        {/* Ações à Direita: Botão de Salvar (Marcação Vermelha) + Indicador da API */}
        <div className="absolute right-2.5 top-1/2 -translate-y-1/2 flex items-center gap-1.5 z-10">
          {/* BOTÃO DE SALVAR NO CAMPO (Marcação Vermelha) */}
          {canShowSaveButton && (
            <button
              type="button"
              disabled={isAlreadySaved || isSaving}
              onClick={handleSalvarEnderecoDireto}
              title={
                isAlreadySaved
                  ? "Endereço já cadastrado no banco de dados"
                  : "Salvar este endereço no banco de dados"
              }
              className={`h-7 px-2.5 rounded-lg text-xs font-bold flex items-center gap-1 transition-all select-none ${
                isAlreadySaved
                  ? 'bg-emerald-50 text-emerald-700 border border-emerald-200 cursor-default'
                  : isSaving
                  ? 'bg-rose-50 text-rose-500 border border-rose-200 cursor-wait opacity-80'
                  : 'bg-rose-50 hover:bg-rose-100 text-rose-600 hover:text-rose-700 border border-rose-200 shadow-2xs cursor-pointer active:scale-95'
              }`}
            >
              {isSaving ? (
                <Loader2 className="w-3.5 h-3.5 animate-spin text-rose-500" />
              ) : isAlreadySaved ? (
                <>
                  <Check className="w-3.5 h-3.5 text-emerald-600 stroke-[2.5]" />
                  <span className="hidden sm:inline">Salvo</span>
                </>
              ) : (
                <>
                  <Bookmark className="w-3.5 h-3.5 text-rose-500 fill-rose-500/20" />
                  <span>Salvar</span>
                </>
              )}
            </button>
          )}

          {/* Ícone Indicador de Status / Provedor */}
          <div className="flex items-center justify-center w-6 h-6 pointer-events-none">
            {isLoading ? (
              <Loader2 className="w-4 h-4 text-[#1D4ED8] animate-spin" />
            ) : GOOGLE_PLACES_KEY ? (
              <Sparkles className="w-4 h-4 text-[#1D4ED8]" />
            ) : (
              <Search className="w-4 h-4 text-slate-400" />
            )}
          </div>
        </div>
      </div>

      {erroSalvar && (
        <p role="alert" className="mt-1 text-xs font-semibold text-rose-600">{erroSalvar}</p>
      )}

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
                    selectionRevisionRef.current++;
                    if (!coordenadasValidas(item.coordenadas)) {
                      setErroSalvar(erroLocalizacaoEndereco);
                      return;
                    }
                    internalCoordsRef.current = item.coordenadas;
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
              onClick={() => handleSelectPrediction({ placeId: '',
                mainText: value.trim().split(',')[0], secondaryText: '', fullText: value.trim() })}
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
