import type { RoadCoordinate } from "./roadGeometry";
// Request only road costs needed for insertion when the route exceeds Matrix's 25-coordinate limit.
export async function collectionRoadCosts(
  points: RoadCoordinate[],
  old: number[],
  added: number[],
  end: number | undefined,
  token: string,
  signal?: AbortSignal,
): Promise<number[][]> {
  if (!token || points.length < 2)
    throw new Error("Cálculo viário indisponível para inserir coletas.");
  const matrix = points.map((_, i) =>
    points.map((__, j) => (i === j ? 0 : Infinity)),
  );
  async function request(
    indices: number[],
    sources: number[],
    destinations: number[],
  ) {
    const query = new URLSearchParams({
      access_token: token,
      annotations: "duration",
      sources: sources.join(";"),
      destinations: destinations.join(";"),
    });
    const response = await fetch(
      `https://api.mapbox.com/directions-matrix/v1/mapbox/driving/${indices.map((i) => points[i].join(",")).join(";")}?${query}`,
      { signal },
    );
    if (!response.ok)
      throw new Error(
        "Não foi possível comparar os trajetos das coletas. Tente novamente.",
      );
    const data = await response.json();
    if (
      data.code !== "Ok" ||
      !Array.isArray(data.durations) ||
      data.durations.length !== sources.length ||
      data.durations.some(
        (row: unknown) =>
          !Array.isArray(row) || row.length !== destinations.length,
      )
    )
      throw new Error(
        "Resposta viária incompleta. Nenhum serviço foi enviado.",
      );
    sources.forEach((source, i) =>
      destinations.forEach((destination, j) => {
        const value = data.durations[i][j];
        matrix[indices[source]][indices[destination]] =
          typeof value === "number" && Number.isFinite(value) && value >= 0
            ? value
            : Infinity;
      }),
    );
  }
  if (points.length <= 25) {
    const ids = points.map((_, i) => i);
    await request(ids, ids, ids);
    return matrix;
  }
  const chain = [0, ...old, ...(end === undefined ? [] : [end])];
  const jobs = [0, ...old, ...added].map((source) => async () => {
    const next = chain[chain.indexOf(source) + 1];
    const destinations = [
      ...new Set(
        added.includes(source)
          ? points.map((_, i) => i)
          : [...added, ...(next === undefined ? [] : [next])],
      ),
    ].filter((i) => i !== source);
    for (let offset = 0; offset < destinations.length; offset += 24) {
      const ids = [source, ...destinations.slice(offset, offset + 24)];
      await request(
        ids,
        [0],
        ids.slice(1).map((_, i) => i + 1),
      );
    }
  });
  for (let offset = 0; offset < jobs.length; offset += 3)
    await Promise.all(jobs.slice(offset, offset + 3).map((job) => job()));
  return matrix;
}
