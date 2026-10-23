import type { Database } from "../../types/database";
type Driver = Database["public"]["Tables"]["motoristas"]["Row"];
export interface DriverProgress {
  driver: Driver;
  total: number;
  completed: number;
  next: string;
  active: boolean;
}
export function DriversPanel({
  rows,
  onAssign,
}: {
  rows: DriverProgress[];
  onAssign?: () => void;
}) {
  return (
    <section className="bg-white border border-gray-300 rounded-2xl p-5 h-full">
      <div className="flex items-center justify-between gap-3 mb-4">
        <h2 className="font-extrabold text-lg">Motoristas</h2>
        <button onClick={onAssign} className="text-blue-700 text-sm font-bold">
          Atribuir rota
        </button>
      </div>
      <div className="divide-y divide-slate-100">
        {rows.length === 0 ? (
          <p className="py-8 text-sm text-slate-500">
            Nenhum motorista ativo cadastrado.
          </p>
        ) : (
          rows.map(({ driver, total, completed, next, active }, index) => {
            const color = ["#1D4ED8", "#0F766E", "#C2410C", "#475569"][
              index % 4
            ];
            const initials = driver.nome
              .split(/\s+/)
              .filter(Boolean)
              .map((w) => w[0])
              .slice(0, 2)
              .join("");
            return (
              <div key={driver.id} className="py-5 first:pt-0">
                <div className="flex gap-3 items-center">
                  <span
                    className="rounded-full w-10 h-10 flex items-center justify-center shrink-0 text-white font-bold text-sm"
                    style={{ background: color }}
                  >
                    {initials}
                  </span>
                  <div className="min-w-0 flex-1">
                    <h3 className="text-sm font-bold truncate">
                      {driver.nome}
                    </h3>
                    <p className="text-xs text-slate-500">
                      {driver.veiculo_modelo || "Veículo não informado"} ·{" "}
                      {total} tarefas
                    </p>
                  </div>
                  <span
                    className={`text-xs font-bold rounded-full px-2 py-1 ${active ? "bg-blue-100 text-blue-900" : "bg-slate-100 text-slate-600"}`}
                  >
                    {active ? "Em rota" : "Disponível"}
                  </span>
                </div>
                <div className="flex items-center gap-4 mt-3">
                  <div className="bg-slate-200 h-2 rounded-full flex-1 overflow-hidden">
                    <div
                      className="h-full"
                      style={{
                        background: color,
                        width: `${total ? (completed / total) * 100 : 0}%`,
                      }}
                    />
                  </div>
                  <strong className="text-xs">
                    {completed} de {total}
                  </strong>
                </div>
                <p className="text-xs text-slate-500 mt-3">
                  {next ? `Próxima: ${next}` : "Sem parada pendente"}
                </p>
              </div>
            );
          })
        )}
      </div>
    </section>
  );
}
