export type RoadCoordinate = [number, number];
export interface RoadPlan { lines: RoadCoordinate[][]; kilometers: number; minutes: number }

export async function fetchRoadPlan(points: RoadCoordinate[], token: string, signal?: AbortSignal): Promise<RoadPlan> {
  if (points.length < 2 || !token) throw new Error('Estimativa viária indisponível.');
  const lines: RoadCoordinate[][] = [];
  let meters = 0, seconds = 0;
  for (let start = 0; start < points.length - 1; start += 24) {
    const coords = points.slice(start, start + 25).map(p => p.join(',')).join(';');
    const query = new URLSearchParams({access_token: token, overview: 'full', geometries: 'geojson', steps: 'false'});
    const response = await fetch(`https://api.mapbox.com/directions/v5/mapbox/driving/${coords}?${query}`, {signal});
    if (!response.ok) throw new Error('Não foi possível calcular o trajeto pelas ruas.');
    const data = await response.json();
    const route = data.routes?.[0];
    const line = route?.geometry?.coordinates;
    if (data.code !== 'Ok' || !Array.isArray(line) || line.length < 2 || !Number.isFinite(route.distance) || !Number.isFinite(route.duration) || route.distance < 0 || route.duration < 0) throw new Error('Trajeto ou estimativa não encontrado.');
    lines.push(line); meters += route.distance; seconds += route.duration;
  }
  return {lines, kilometers: meters / 1000, minutes: seconds / 60};
}
export async function fetchRoadGeometry(points: RoadCoordinate[], token: string, signal?: AbortSignal): Promise<RoadCoordinate[][]> {
  return points.length < 2 ? [] : (await fetchRoadPlan(points, token, signal)).lines;
}
