export type RoadCoordinate = [number, number];

export async function fetchRoadGeometry(points: RoadCoordinate[], token: string, signal?: AbortSignal): Promise<RoadCoordinate[][]> {
  if (points.length < 2) return [];
  const lines: RoadCoordinate[][] = [];
  for (let start = 0; start < points.length - 1; start += 24) {
    const coords = points.slice(start, start + 25).map(p => p.join(',')).join(';');
    const query = new URLSearchParams({access_token: token, overview: 'full', geometries: 'geojson', steps: 'false'});
    const response = await fetch(`https://api.mapbox.com/directions/v5/mapbox/driving/${coords}?${query}`, {signal});
    if (!response.ok) throw new Error('Não foi possível calcular o trajeto pelas ruas.');
    const data = await response.json();
    const line = data.routes?.[0]?.geometry?.coordinates;
    if (data.code !== 'Ok' || !Array.isArray(line) || line.length < 2) throw new Error('Trajeto não encontrado.');
    lines.push(line);
  }
  return lines;
}
