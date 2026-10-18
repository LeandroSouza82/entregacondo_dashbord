import React, { useState, useMemo, useRef, useCallback } from 'react';
import Map, { Marker, Source, Layer, Popup, type MapRef } from 'react-map-gl/mapbox';
import type { FeatureCollection, LineString } from 'geojson';

const MAPBOX_TOKEN = import.meta.env.VITE_MAPBOX_TOKEN || '';

export interface ParadaAoVivo {
  id: string;
  numero: number;
  lat: number;
  lng: number;
  status: 'concluida' | 'atual' | 'pendente';
  cliente: string;
  endereco: string;
}

export interface MotoristaRotaAoVivo {
  id: string;
  nome: string;
  veiculo: string;
  cor: string;
  paradas: ParadaAoVivo[];
}

export const MOCK_ROTAS_FROTA: MotoristaRotaAoVivo[] = [
  {
    id: 'carlos',
    nome: 'Carlos',
    veiculo: 'Fiorino',
    cor: '#1D4ED8', // Azul
    paradas: [
      { id: 'c1', numero: 1, lat: -27.5995, lng: -48.5490, status: 'concluida', cliente: 'Ricardo Almeida', endereco: 'Av. Beira-Mar Norte, 3400' },
      { id: 'c2', numero: 2, lat: -27.5940, lng: -48.5420, status: 'concluida', cliente: 'Luciana Prado', endereco: 'Rua Felipe Schmidt, 1250' },
      { id: 'c3', numero: 3, lat: -27.5890, lng: -48.5320, status: 'atual', cliente: 'Maria Fernanda Rocha', endereco: 'Rua Lauro Linhares, 820' },
      { id: 'c4', numero: 4, lat: -27.5850, lng: -48.5280, status: 'pendente', cliente: 'Lucas Silveira', endereco: 'Rua Lauro Linhares, 1120' },
    ],
  },
  {
    id: 'rafael',
    nome: 'Rafael',
    veiculo: 'Moto',
    cor: '#0F766E', // Verde-azulado
    paradas: [
      { id: 'r1', numero: 1, lat: -27.5820, lng: -48.5150, status: 'concluida', cliente: 'Camila Souza', endereco: 'Rua Bocaiúva, 450' },
      { id: 'r2', numero: 2, lat: -27.5870, lng: -48.5180, status: 'concluida', cliente: 'Eduardo Ramos', endereco: 'Rua Almirante Lamego, 600' },
      { id: 'r3', numero: 3, lat: -27.5920, lng: -48.5230, status: 'atual', cliente: 'Beatriz Martins', endereco: 'Rua Bocaiúva, 800' },
      { id: 'r4', numero: 4, lat: -27.5960, lng: -48.5280, status: 'pendente', cliente: 'Gustavo Lima', endereco: 'Av. Mauro Ramos, 920' },
    ],
  },
  {
    id: 'joao',
    nome: 'João Pedro',
    veiculo: 'Saveiro',
    cor: '#C2410C', // Laranja-terracota
    paradas: [
      { id: 'j1', numero: 1, lat: -27.6040, lng: -48.5380, status: 'concluida', cliente: 'Paulo Henrique Dias', endereco: 'Av. Madre Benvenuta, 1100' },
      { id: 'j2', numero: 2, lat: -27.6000, lng: -48.5310, status: 'atual', cliente: 'Mariana Duarte', endereco: 'Av. Madre Benvenuta, 1400' },
      { id: 'j3', numero: 3, lat: -27.5950, lng: -48.5190, status: 'pendente', cliente: 'Fernando Lopes', endereco: 'Rua João Pio Duarte Silva, 900' },
      { id: 'j4', numero: 4, lat: -27.5920, lng: -48.5110, status: 'pendente', cliente: 'Carla Nogueira', endereco: 'Rua Delfino Conti, 220' },
    ],
  },
];

export const LiveFleetMap: React.FC = () => {
  const mapRef = useRef<MapRef | null>(null);
  const [motoristaFiltro, setMotoristaFiltro] = useState<string>('todos');
  const [popupInfo, setPopupInfo] = useState<{
    longitude: number;
    latitude: number;
    motorista: string;
    parada: ParadaAoVivo;
    cor: string;
  } | null>(null);

  // Filtra as rotas baseado no motorista selecionado
  const rotasFiltradas = useMemo(() => {
    if (motoristaFiltro === 'todos') {
      return MOCK_ROTAS_FROTA;
    }
    return MOCK_ROTAS_FROTA.filter((r) => r.id === motoristaFiltro);
  }, [motoristaFiltro]);

  // Initial Viewport centrado na frota (Florianópolis / região operacional)
  const initialViewState = useMemo(() => {
    return {
      longitude: -48.5300,
      latitude: -27.5930,
      zoom: 12.6,
      pitch: 0,
      bearing: 0,
    };
  }, []);

  // Gera o GeoJSON FeatureCollection para as polylines de todas as rotas visíveis
  const routesGeoJson = useMemo<FeatureCollection<LineString>>(() => {
    return {
      type: 'FeatureCollection',
      features: rotasFiltradas.map((r) => ({
        type: 'Feature',
        properties: {
          id: r.id,
          cor: r.cor,
        },
        geometry: {
          type: 'LineString',
          coordinates: r.paradas.map((p) => [p.lng, p.lat]),
        },
      })),
    };
  }, [rotasFiltradas]);

  // Auto-fit bounds quando o filtro de motorista muda
  const handleAjustarFoco = useCallback((motoristaId: string) => {
    setMotoristaFiltro(motoristaId);
    if (!mapRef.current) return;

    const rotas = motoristaId === 'todos' 
      ? MOCK_ROTAS_FROTA 
      : MOCK_ROTAS_FROTA.filter(r => r.id === motoristaId);

    const todasCoords = rotas.flatMap(r => r.paradas.map(p => [p.lng, p.lat]));
    if (todasCoords.length === 0) return;

    let minLng = todasCoords[0][0];
    let maxLng = todasCoords[0][0];
    let minLat = todasCoords[0][1];
    let maxLat = todasCoords[0][1];

    todasCoords.forEach(([lng, lat]) => {
      minLng = Math.min(minLng, lng);
      maxLng = Math.max(maxLng, lng);
      minLat = Math.min(minLat, lat);
      maxLat = Math.max(maxLat, lat);
    });

    mapRef.current.fitBounds(
      [
        [minLng, minLat],
        [maxLng, maxLat],
      ],
      { padding: 45, duration: 800, maxZoom: 14.5 }
    );
  }, []);

  // Marcadores dos motoristas memoizados
  const renderedMarkers = useMemo(() => {
    return rotasFiltradas.flatMap((rota) =>
      rota.paradas.map((parada) => {
        const isConcluida = parada.status === 'concluida';
        const isAtual = parada.status === 'atual';
        const isPendente = parada.status === 'pendente';

        return (
          <Marker
            key={`${rota.id}-${parada.id}`}
            longitude={parada.lng}
            latitude={parada.lat}
            anchor="center"
            onClick={(e: { originalEvent: MouseEvent }) => {
              e.originalEvent.stopPropagation();
              setPopupInfo({
                longitude: parada.lng,
                latitude: parada.lat,
                motorista: rota.nome,
                parada,
                cor: rota.cor,
              });
            }}
          >
            {/* Pinos estilizados conforme especificação visual */}
            <div className="cursor-pointer transition-transform hover:scale-125">
              {isAtual && (
                /* Marcador com halo de sombra pulsante (posição atual) */
                <div
                  style={{
                    backgroundColor: rota.cor,
                    boxShadow: `0 0 0 5px ${rota.cor}40, 0 4px 10px rgba(0,0,0,0.25)`,
                    borderColor: '#FFFFFF',
                  }}
                  className="w-[28px] h-[28px] rounded-full border-2 text-white font-extrabold text-[11px] flex items-center justify-center animate-pulse"
                >
                  {parada.numero}
                </div>
              )}

              {isConcluida && (
                /* Marcador cheio (concluída) */
                <div
                  style={{
                    backgroundColor: rota.cor,
                    borderColor: '#FFFFFF',
                  }}
                  className="w-[24px] h-[24px] rounded-full border-2 text-white font-extrabold text-[11px] flex items-center justify-center shadow-md"
                >
                  {parada.numero}
                </div>
              )}

              {isPendente && (
                /* Marcador vazado com fundo branco e borda colorida (pendente) */
                <div
                  style={{
                    backgroundColor: '#FFFFFF',
                    borderColor: rota.cor,
                    color: rota.cor,
                  }}
                  className="w-[24px] h-[24px] rounded-full border-[3px] font-extrabold text-[11px] flex items-center justify-center shadow-md"
                >
                  {parada.numero}
                </div>
              )}
            </div>
          </Marker>
        );
      })
    );
  }, [rotasFiltradas]);

  return (
    <section className="bg-white border border-[#E1E6ED] rounded-2xl p-5 shadow-card flex flex-col gap-4">
      {/* Header do Mapa com Filtros em Pílulas */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2.5">
          <h2 className="text-[17px] font-extrabold text-[#0F1B2D] m-0">Rotas em tempo real</h2>
          <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-[#DDF3E4] text-[#14532D] text-xs font-bold">
            <span className="w-2 h-2 rounded-full bg-[#15803D] animate-ping" />
            Ao vivo
          </span>
        </div>

        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            onClick={() => handleAjustarFoco('todos')}
            className={`h-8 px-3 rounded-full text-[13px] font-semibold transition-all cursor-pointer ${
              motoristaFiltro === 'todos'
                ? 'bg-[#0F1B2D] text-white border border-[#0F1B2D] shadow-sm'
                : 'bg-white text-[#0F1B2D] border border-[#D5DCE5] hover:bg-slate-50'
            }`}
          >
            Todos
          </button>

          <button
            type="button"
            onClick={() => handleAjustarFoco('carlos')}
            className={`h-8 px-3 rounded-full text-[13px] font-semibold inline-flex items-center gap-1.5 transition-all cursor-pointer ${
              motoristaFiltro === 'carlos'
                ? 'bg-[#1D4ED8] text-white border border-[#1D4ED8] shadow-sm'
                : 'bg-white text-[#0F1B2D] border border-[#D5DCE5] hover:bg-slate-50'
            }`}
          >
            <span className="w-2.5 h-2.5 rounded-full bg-[#1D4ED8]" />
            Carlos
          </button>

          <button
            type="button"
            onClick={() => handleAjustarFoco('rafael')}
            className={`h-8 px-3 rounded-full text-[13px] font-semibold inline-flex items-center gap-1.5 transition-all cursor-pointer ${
              motoristaFiltro === 'rafael'
                ? 'bg-[#0F766E] text-white border border-[#0F766E] shadow-sm'
                : 'bg-white text-[#0F1B2D] border border-[#D5DCE5] hover:bg-slate-50'
            }`}
          >
            <span className="w-2.5 h-2.5 rounded-full bg-[#0F766E]" />
            Rafael
          </button>

          <button
            type="button"
            onClick={() => handleAjustarFoco('joao')}
            className={`h-8 px-3 rounded-full text-[13px] font-semibold inline-flex items-center gap-1.5 transition-all cursor-pointer ${
              motoristaFiltro === 'joao'
                ? 'bg-[#C2410C] text-white border border-[#C2410C] shadow-sm'
                : 'bg-white text-[#0F1B2D] border border-[#D5DCE5] hover:bg-slate-50'
            }`}
          >
            <span className="w-2.5 h-2.5 rounded-full bg-[#C2410C]" />
            João Pedro
          </button>
        </div>
      </div>

      {/* Canvas Mapbox GL */}
      <div className="w-full h-[360px] md:h-[400px] rounded-xl overflow-hidden border border-[#CBD5E1]/60 relative">
        <Map
          ref={mapRef}
          initialViewState={initialViewState}
          mapboxAccessToken={MAPBOX_TOKEN}
          mapStyle="mapbox://styles/mapbox/light-v11"
          reuseMaps
          attributionControl={false}
          style={{ width: '100%', height: '100%' }}
        >
          {/* Rotas dos Motoristas */}
          <Source id="fleet-routes" type="geojson" data={routesGeoJson}>
            <Layer
              id="fleet-routes-layer"
              type="line"
              layout={{
                'line-join': 'round',
                'line-cap': 'round',
              }}
              paint={{
                'line-color': ['get', 'cor'],
                'line-width': 4.5,
                'line-opacity': 0.85,
              }}
            />
          </Source>

          {/* Marcadores Renderizados */}
          {renderedMarkers}

          {/* Popup ao Clicar em Qualquer Ponto */}
          {popupInfo && (
            <Popup
              longitude={popupInfo.longitude}
              latitude={popupInfo.latitude}
              anchor="bottom"
              onClose={() => setPopupInfo(null)}
              closeButton={true}
              closeOnClick={false}
              className="z-50"
            >
              <div className="font-sans text-xs p-1 max-w-[210px]">
                <div className="flex items-center gap-1.5 mb-1">
                  <span
                    style={{ backgroundColor: popupInfo.cor }}
                    className="w-2 h-2 rounded-full inline-block"
                  />
                  <strong className="text-[#0F1B2D] font-bold">
                    {popupInfo.motorista} · Parada {popupInfo.parada.numero}
                  </strong>
                </div>
                <div className="font-semibold text-slate-800">
                  {popupInfo.parada.cliente}
                </div>
                <div className="text-[11px] text-[#516074] mt-0.5">
                  {popupInfo.parada.endereco}
                </div>
                <div className="mt-1.5 pt-1 border-t border-slate-100 flex items-center justify-between text-[10px]">
                  <span className="capitalize font-bold text-slate-600">
                    Status: {popupInfo.parada.status === 'atual' ? 'Em atendimento' : popupInfo.parada.status}
                  </span>
                </div>
              </div>
            </Popup>
          )}
        </Map>
      </div>

      {/* Legenda Exata do Design 01-dashboard-visao-geral.html */}
      <div className="flex flex-wrap items-center gap-4 text-xs text-[#516074] pt-1">
        <span className="inline-flex items-center gap-2">
          <span className="w-3 h-3 rounded-full bg-[#516074]" />
          <span>Entrega concluída</span>
        </span>
        <span className="inline-flex items-center gap-2">
          <span className="w-3 h-3 rounded-full border-[3px] border-[#516074] bg-white box-border" />
          <span>Entrega pendente</span>
        </span>
        <span className="inline-flex items-center gap-2">
          <span className="w-3 h-3 rounded-full bg-[#516074] shadow-[0_0_0_4px_rgba(81,96,116,0.25)]" />
          <span>Posição atual do motorista</span>
        </span>
      </div>
    </section>
  );
};
