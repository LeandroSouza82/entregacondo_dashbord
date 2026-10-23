import { Map as MapIcon, Globe, Moon } from 'lucide-react';

export const MAP_STYLES = [
  {
    id: 'streets',
    label: 'Ruas / Logística',
    icon: MapIcon,
    styleUrl: 'mapbox://styles/mapbox/streets-v12',
  },
  {
    id: 'satellite',
    label: 'Satélite',
    icon: Globe,
    styleUrl: 'mapbox://styles/mapbox/satellite-streets-v12',
  },
  {
    id: 'dark',
    label: 'Dark / Noturno',
    icon: Moon,
    styleUrl: 'mapbox://styles/mapbox/navigation-night-v1',
  },
];

export const DEFAULT_MAP_STYLE = MAP_STYLES[0].styleUrl;
