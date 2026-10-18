import React, { useRef, useMemo, useEffect, useState, useCallback } from 'react';
import Map, { Marker, Source, Layer, Popup, NavigationControl, type MapRef } from 'react-map-gl/mapbox';
import type { PontoParada, PontoCoordenada } from '../../types/logistics';
import type { Feature, LineString } from 'geojson';
import { MapPin } from 'lucide-react';

const MAPBOX_TOKEN = import.meta.env.VITE_MAPBOX_TOKEN || '';

interface RouteMapProps {
  pontoPartida: {
    nome: string;
    coordenadas: PontoCoordenada;
  };
  paradas: PontoParada[];
  pontoPreview?: {
    nome: string;
    coordenadas: PontoCoordenada;
  } | null;
  otimizado?: boolean;
}

export const RouteMap: React.FC<RouteMapProps> = ({
  pontoPartida,
  paradas,
  pontoPreview,
  otimizado = true,
}) => {
  const mapRef = useRef<MapRef | null>(null);
  const [popupInfo, setPopupInfo] = useState<{
    longitude: number;
    latitude: number;
    titulo: string;
    subtitulo: string;
    tempo?: number;
  } | null>(null);

  // Initial Viewport centrado com useMemo
  const initialViewState = useMemo(() => {
    return {
      longitude: pontoPartida.coordenadas.lng,
      latitude: pontoPartida.coordenadas.lat,
      zoom: 12.8,
      pitch: 0,
      bearing: 0,
    };
  }, [pontoPartida.coordenadas.lng, pontoPartida.coordenadas.lat]);

  // GeoJSON LineString da rota para Source / Layer
  const routeGeoJson = useMemo<Feature<LineString>>(() => {
    const coordinates: [number, number][] = [
      [pontoPartida.coordenadas.lng, pontoPartida.coordenadas.lat],
      ...paradas.map((p) => [p.coordenadas.lng, p.coordenadas.lat] as [number, number]),
    ];

    if (pontoPreview) {
      coordinates.push([pontoPreview.coordenadas.lng, pontoPreview.coordenadas.lat]);
    }

    return {
      type: 'Feature',
      properties: {
        otimizado,
      },
      geometry: {
        type: 'LineString',
        coordinates,
      },
    };
  }, [pontoPartida, paradas, pontoPreview, otimizado]);

  // Layer styling memoizado com contorno de alto contraste
  const routeCasingStyle = useMemo(() => ({
    id: 'route-line-casing',
    type: 'line' as const,
    layout: {
      'line-join': 'round' as const,
      'line-cap': 'round' as const,
    },
    paint: {
      'line-color': '#FFFFFF',
      'line-width': 7.5,
      'line-opacity': 0.95,
    },
  }), []);

  const routeLayerStyle = useMemo(() => ({
    id: 'route-line',
    type: 'line' as const,
    layout: {
      'line-join': 'round' as const,
      'line-cap': 'round' as const,
    },
    paint: {
      'line-color': otimizado ? '#1D4ED8' : '#475569',
      'line-width': 4.5,
      'line-opacity': 1,
      ...(otimizado ? {} : { 'line-dasharray': [2, 2] }),
    },
  }), [otimizado]);

  // Auto-ajuste de bounds (fitBounds) com proteção estrita para evitar loops
  const fitRouteBounds = useCallback(() => {
    if (!mapRef.current) return;

    const coordinates = [
      [pontoPartida.coordenadas.lng, pontoPartida.coordenadas.lat],
      ...paradas.map((p) => [p.coordenadas.lng, p.coordenadas.lat]),
    ];

    if (pontoPreview) {
      coordinates.push([pontoPreview.coordenadas.lng, pontoPreview.coordenadas.lat]);
    }

    if (coordinates.length === 0) return;

    let minLng = coordinates[0][0];
    let maxLng = coordinates[0][0];
    let minLat = coordinates[0][1];
    let maxLat = coordinates[0][1];

    coordinates.forEach(([lng, lat]) => {
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
      { padding: 40, duration: 800, maxZoom: 15 }
    );
  }, [pontoPartida.coordenadas.lng, pontoPartida.coordenadas.lat, paradas, pontoPreview]);

  // Dispara fitBounds apenas quando o número de paradas muda
  useEffect(() => {
    const timer = setTimeout(() => {
      fitRouteBounds();
    }, 200);
    return () => clearTimeout(timer);
  }, [paradas.length, fitRouteBounds]);

  // Se houver um novo ponto selecionado no Google Places, faz flyTo para centralizá-lo
  useEffect(() => {
    if (pontoPreview && mapRef.current) {
      mapRef.current.flyTo({
        center: [pontoPreview.coordenadas.lng, pontoPreview.coordenadas.lat],
        zoom: 14.5,
        duration: 1000,
      });
    }
  }, [pontoPreview]);

  // Marcadores das paradas memoizados para garantir renderização de alta performance
  const renderedMarkers = useMemo(() => {
    return paradas.map((parada, idx) => (
      <Marker
        key={parada.id}
        longitude={parada.coordenadas.lng}
        latitude={parada.coordenadas.lat}
        anchor="center"
        onClick={(e: { originalEvent: MouseEvent }) => {
          e.originalEvent.stopPropagation();
          setPopupInfo({
            longitude: parada.coordenadas.lng,
            latitude: parada.coordenadas.lat,
            titulo: `Parada ${idx + 1}: ${parada.destinatario}`,
            subtitulo: `${parada.nomeLocal} · ${parada.enderecoFormatado}`,
            tempo: parada.tempoMedioAtendimentoMinutos,
          });
        }}
      >
        <div className="w-7 h-7 rounded-full bg-[#1D4ED8] text-white font-sans text-xs font-black flex items-center justify-center shadow-lg border-2 border-white cursor-pointer hover:scale-110 transition-transform">
          {idx + 1}
        </div>
      </Marker>
    ));
  }, [paradas]);

  // Fallback caso não haja token válido
  if (!MAPBOX_TOKEN) {
    return (
      <div className="w-full h-[260px] md:h-[280px] bg-slate-100 rounded-2xl flex items-center justify-center p-6 text-center border border-slate-200">
        <div>
          <p className="text-sm font-bold text-navy-900">Mapbox Token Não Configurado</p>
          <p className="text-xs text-slate-500 mt-1">
            Defina <code className="bg-white px-1.5 py-0.5 rounded text-navy-800">VITE_MAPBOX_TOKEN</code> no arquivo .env
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="relative w-full rounded-2xl overflow-hidden border border-[#E1E6ED] bg-white shadow-card">
      <div className="w-full h-[260px] md:h-[280px]">
        <Map
          ref={mapRef}
          initialViewState={initialViewState}
          mapboxAccessToken={MAPBOX_TOKEN}
          mapStyle="mapbox://styles/mapbox/streets-v12"
          reuseMaps
          attributionControl={false}
          style={{ width: '100%', height: '100%' }}
        >
          {/* Rota Polyline com Contorno de Alto Contraste */}
          <Source id="route-source" type="geojson" data={routeGeoJson}>
            <Layer {...routeCasingStyle} />
            <Layer {...routeLayerStyle} />
          </Source>

          <NavigationControl position="bottom-right" showCompass={false} />

          {/* Marcador Ponto de Partida */}
          <Marker
            longitude={pontoPartida.coordenadas.lng}
            latitude={pontoPartida.coordenadas.lat}
            anchor="center"
            onClick={(e: { originalEvent: MouseEvent }) => {
              e.originalEvent.stopPropagation();
              setPopupInfo({
                longitude: pontoPartida.coordenadas.lng,
                latitude: pontoPartida.coordenadas.lat,
                titulo: 'Ponto de Partida',
                subtitulo: pontoPartida.nome,
              });
            }}
          >
            <div className="bg-[#0F1B2D] text-white font-sans text-[10px] font-bold px-2 py-1 rounded-md shadow-md border-2 border-white cursor-pointer hover:scale-105 transition-transform">
              Início
            </div>
          </Marker>

          {/* Marcadores das Paradas da Rota */}
          {renderedMarkers}

          {/* Marcador de Prévia do Endereço Selecionado via Google Places */}
          {pontoPreview && (
            <Marker
              longitude={pontoPreview.coordenadas.lng}
              latitude={pontoPreview.coordenadas.lat}
              anchor="bottom"
              onClick={(e: { originalEvent: MouseEvent }) => {
                e.originalEvent.stopPropagation();
                setPopupInfo({
                  longitude: pontoPreview.coordenadas.lng,
                  latitude: pontoPreview.coordenadas.lat,
                  titulo: 'Novo Ponto Selecionado',
                  subtitulo: pontoPreview.nome,
                });
              }}
            >
              <div className="flex flex-col items-center animate-bounce">
                <span className="bg-[#C2410C] text-white text-[10px] font-extrabold px-2 py-0.5 rounded shadow-md whitespace-nowrap mb-0.5">
                  Nova Parada
                </span>
                <div className="w-8 h-8 rounded-full bg-[#C2410C] text-white flex items-center justify-center shadow-xl border-2 border-white">
                  <MapPin className="w-4 h-4 text-white" />
                </div>
              </div>
            </Marker>
          )}

          {/* Popup Informativo ao Clicar em Marcador */}
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
              <div className="font-sans text-xs p-1 max-w-[200px]">
                <strong className="text-[#0F1B2D] block font-bold">{popupInfo.titulo}</strong>
                <span className="text-[#516074] block mt-0.5">{popupInfo.subtitulo}</span>
                {popupInfo.tempo && (
                  <span className="inline-block mt-1 text-[#1D4ED8] font-semibold text-[11px]">
                    ⏱ Média portaria: {popupInfo.tempo} min
                  </span>
                )}
              </div>
            </Popup>
          )}
        </Map>
      </div>

      {/* Rodapé descritivo com status da rota */}
      <div className="px-4 py-2 bg-slate-50 border-t border-slate-100 flex items-center justify-between text-[11px] text-slate-500">
        <span className="flex items-center gap-1.5">
          <span className="w-2.5 h-2.5 rounded-full bg-[#1D4ED8]"></span>
          <span className="font-medium">{paradas.length} paradas na rota</span>
        </span>
        <span className="font-semibold text-emerald-700">Logística Inteligente · Rota Otimizada</span>
      </div>
    </div>
  );
};
