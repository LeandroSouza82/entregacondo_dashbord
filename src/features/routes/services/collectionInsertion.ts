// Insert new collections with the least additional road travel time.
// Existing tasks keep their relative order; an ongoing attendance stays first.
export function insertCollections(
  existing: number[],
  collections: number[],
  seconds: number[][],
  pinned = false,
  end?: number,
): number[] {
  const order = [...existing],
    remaining = [...collections];
  const cost = (a: number, b: number) => seconds[a]?.[b] ?? Infinity;
  const chain = [0, ...order, ...(end === undefined ? [] : [end])];
  if (chain.slice(1).some((node, i) => !Number.isFinite(cost(chain[i], node))))
    throw new Error("Uma parada da rota atual não possui trajeto viário.");
  while (remaining.length) {
    let best: { index: number; position: number; extra: number } | undefined;
    for (let index = 0; index < remaining.length; index++) {
      const node = remaining[index];
      for (
        let position = pinned ? 1 : 0;
        position <= order.length;
        position++
      ) {
        const before = position === 0 ? 0 : order[position - 1];
        const after = position < order.length ? order[position] : end;
        const extra =
          cost(before, node) +
          (after === undefined ? 0 : cost(node, after) - cost(before, after));
        if (Number.isFinite(extra) && (!best || extra < best.extra))
          best = { index, position, extra };
      }
    }
    if (!best)
      throw new Error(
        "Não foi encontrado trajeto pelas ruas para inserir a coleta.",
      );
    order.splice(best.position, 0, remaining.splice(best.index, 1)[0]);
  }
  return order;
}
