import Map, { Marker, NavigationControl, type MapRef } from 'react-map-gl/mapbox';
import { useCallback, useEffect, useRef } from 'react';
import type { TrackingPoint } from './arrivalTracking';
import 'mapbox-gl/dist/mapbox-gl.css';

export default function ArrivalTrackingMap({destination, position}: {destination: TrackingPoint; position?: TrackingPoint | null}) {
  const ref = useRef<MapRef>(null);
  const token = import.meta.env.VITE_MAPBOX_TOKEN || '';
  const fit = useCallback(() => {
    if (!ref.current) return;
    if (position) ref.current.fitBounds([[Math.min(destination.longitude, position.longitude), Math.min(destination.latitude, position.latitude)], [Math.max(destination.longitude, position.longitude), Math.max(destination.latitude, position.latitude)]], {padding: 55, maxZoom: 16, duration: 0});
    else ref.current.jumpTo({center: [destination.longitude, destination.latitude], zoom: 14});
  }, [destination, position]);
  useEffect(() => fit(), [fit]);
  if (!token) return <div role="status" className="p-6 bg-slate-100">Mapa indisponível. Consulte a previsão e a última atualização abaixo.</div>;
  return <Map ref={ref} mapboxAccessToken={token} mapStyle="mapbox://styles/mapbox/streets-v12" initialViewState={{longitude: destination.longitude, latitude: destination.latitude, zoom: 13}} onLoad={fit} style={{width: '100%', height: 340}}>
    <Marker longitude={destination.longitude} latitude={destination.latitude}><span aria-label="Seu atendimento" className="rounded-full bg-blue-700 px-3 py-2 text-white shadow">Destino</span></Marker>
    {position ? <Marker longitude={position.longitude} latitude={position.latitude}><span aria-label="Motorista" className="rounded-full border-2 border-white bg-orange-700 px-3 py-2 text-white shadow">Motorista</span></Marker> : null}
    <NavigationControl showCompass={false} />
  </Map>;
}
