import type { Database } from "../../types/database";
export type TodayDelivery = Database["public"]["Tables"]["entregas"]["Row"] & {
  clientes_enderecos?:
    | Database["public"]["Tables"]["clientes_enderecos"]["Row"]
    | null;
};
export function deliveryStatus(status: string) {
  return status === "entregue"
    ? "Entregue"
    : status === "tentativa_falha" || status === "falha" || status === "falhou"
      ? "Ocorrência"
      : status === "em_transito" || status === "atribuida"
        ? "Em rota"
        : status === "cancelada"
          ? "Cancelada"
          : "Pendente";
}
export function TodayDeliveriesTable({
  rows,
  drivers,
  receivers,
}: {
  rows: TodayDelivery[];
  drivers: Record<string, string>;
  receivers: Record<string, string>;
}) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm text-left min-w-[760px]">
        <thead className="bg-[#F3F5F8] text-xs uppercase text-[#516074]">
          <tr>
            {[
              "Cliente",
              "Endereço",
              "Motorista",
              "Observação",
              "Status",
              "Recebido por",
            ].map((h) => (
              <th className="p-3 font-bold" key={h}>
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-slate-100">
          {rows.map((d) => {
            const label = deliveryStatus(d.status);
            return (
              <tr key={d.id} className="hover:bg-slate-50">
                <td className="px-3 py-4">
                  <strong className="block text-[#0F1B2D]">
                    {d.destinatario_nome}
                  </strong>
                  <span className="text-xs text-slate-500">
                    {d.unidade_apartamento || d.codigo_rastreio}
                  </span>
                </td>
                <td className="p-3 text-slate-600">
                  {d.clientes_enderecos?.endereco_completo ||
                    "Endereço não informado"}
                </td>
                <td className="p-3 text-slate-600">
                  {d.motorista_id
                    ? drivers[d.motorista_id] || "Motorista vinculado"
                    : "—"}
                </td>
                <td className="p-3 text-slate-600 max-w-48">
                  {d.observacoes_gestor || "—"}
                </td>
                <td className="p-3">
                  <span
                    className={`whitespace-nowrap rounded-full px-3 py-1 text-xs font-bold ${label === "Entregue" ? "bg-green-100 text-green-900" : label === "Ocorrência" ? "bg-red-100 text-red-900" : label === "Em rota" ? "bg-blue-100 text-blue-900" : "bg-amber-100 text-amber-900"}`}
                  >
                    {label}
                  </span>
                </td>
                <td className="p-3 text-slate-600">{receivers[d.id] || "—"}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
      {rows.length === 0 && (
        <p className="text-sm text-slate-500 text-center py-12">
          Nenhuma entrega para este filtro.
        </p>
      )}
    </div>
  );
}
