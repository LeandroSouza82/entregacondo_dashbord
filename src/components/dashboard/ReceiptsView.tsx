import { receiptLabel } from "./receiptLabels";
import { useEffect, useState } from "react";
import { Camera, X } from "lucide-react";
import { supabase } from "../../lib/supabase";
import { requireCompanyId } from "../../lib/company";
import type { Database } from "../../types/database";
type Receipt = Database["public"]["Tables"]["entrega_comprovantes"]["Row"] & {
  entregas: { destinatario_nome: string; motorista_id: string | null } | null;
};
export function ReceiptsView({ title = "Comprovantes" }: { title?: string }) {
  const [rows, setRows] = useState<Receipt[]>([]);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const [date, setDate] = useState(() =>
    new Date().toLocaleDateString("en-CA"),
  );
  const [preview, setPreview] = useState("");
  useEffect(() => {
    let active = true;
    async function load() {
      setLoading(true);
      setError("");
      try {
        const company = await requireCompanyId();
        const start = new Date(`${date}T00:00:00`),
          end = new Date(start);
        end.setDate(end.getDate() + 1);
        const data: Receipt[] = [];
        for (let offset = 0; ; offset += 500) {
          const result = await supabase
            .from("entrega_comprovantes")
            .select("*,entregas(destinatario_nome,motorista_id)")
            .eq("empresa_id", company)
            .gte("concluida_em", start.toISOString())
            .lt("concluida_em", end.toISOString())
            .order("concluida_em", { ascending: false })
            .order("entrega_id")
            .range(offset, offset + 499);
          if (result.error) throw result.error;
          data.push(...result.data);
          if (result.data.length < 500) break;
        }
        if (active) setRows(data);
      } catch {
        if (active) {
          setRows([]);
          setError("Não foi possível consultar os comprovantes da empresa.");
        }
      } finally {
        if (active) setLoading(false);
      }
    }
    void load();
    return () => {
      active = false;
    };
  }, [date]);
  async function open(path: string) {
    setError("");
    const result = await supabase.storage
      .from("entregas-comprovantes")
      .createSignedUrl(path, 60);
    if (result.error) {
      setError("Não foi possível abrir esta imagem.");
      return;
    }
    setPreview(result.data.signedUrl);
  }
  const success = rows.filter((r) => r.recebedor_tipo !== "tentativa_falha");
  const average = success.length
    ? success.reduce((sum, r) => sum + r.duracao_segundos, 0) / success.length
    : null;
  return (
    <div className="space-y-6 text-[#0F1B2D]">
      <header className="flex justify-between items-center gap-4 flex-wrap">
        <div>
          <h1 className="text-[26px] font-extrabold">{title}</h1>
          <p className="text-sm text-slate-500 mt-1">
            Recebedores, evidências e tempo real de atendimento.
          </p>
        </div>
        <label className="text-sm font-semibold">
          Data{" "}
          <input
            aria-label="Data dos comprovantes"
            type="date"
            value={date}
            onChange={(e) => setDate(e.target.value)}
            className="ml-2 border rounded-xl p-3"
          />
        </label>
      </header>
      <div className="grid grid-cols-3 gap-4">
        {[
          ["Concluídos", success.length],
          ["Ocorrências", rows.length - success.length],
          [
            "Tempo médio",
            average === null ? "—" : `${(average / 60).toFixed(1)} min`,
          ],
        ].map(([label, value]) => (
          <section key={label} className="bg-white border rounded-2xl p-5">
            <p className="text-sm text-slate-500">{label}</p>
            <strong className="text-2xl">{loading ? "—" : value}</strong>
          </section>
        ))}
      </div>
      {error && (
        <p role="alert" className="bg-red-50 text-red-800 p-4 rounded-xl">
          {error}
        </p>
      )}
      <section className="bg-white border rounded-2xl overflow-x-auto">
        <table className="w-full text-sm text-left min-w-[680px]">
          <thead className="bg-slate-50 text-slate-500">
            <tr>
              {[
                "Hora",
                "Cliente",
                "Recebedor / ocorrência",
                "Tempo",
                "Evidências",
              ].map((h) => (
                <th key={h} className="p-4">
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {rows.map((r) => (
              <tr key={r.entrega_id}>
                <td className="p-4">
                  {new Date(r.concluida_em).toLocaleTimeString("pt-BR", {
                    hour: "2-digit",
                    minute: "2-digit",
                  })}
                </td>
                <td className="p-4 font-bold">
                  {r.entregas?.destinatario_nome || "Entrega"}
                </td>
                <td className="p-4">
                  {receiptLabel(r.recebedor_tipo)}
                  {r.recebedor_nome ? ` · ${r.recebedor_nome}` : ""}
                  {r.observacao && (
                    <p className="text-xs text-slate-500 mt-1">
                      {r.observacao}
                    </p>
                  )}
                </td>
                <td className="p-4 tabular-nums">
                  {Math.floor(r.duracao_segundos / 60)} min{" "}
                  {r.duracao_segundos % 60}s
                </td>
                <td className="p-4">
                  <div className="flex gap-3">
                    {r.foto_path && (
                      <button
                        aria-label={`Ver foto de ${r.entregas?.destinatario_nome || "entrega"}`}
                        onClick={() => void open(r.foto_path!)}
                        className="text-blue-700"
                      >
                        <Camera size={20} />
                      </button>
                    )}
                    {r.assinatura_path && (
                      <button
                        onClick={() => void open(r.assinatura_path!)}
                        className="text-blue-700 font-semibold"
                      >
                        Assinatura
                      </button>
                    )}
                    {!r.foto_path && !r.assinatura_path && "—"}
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {!rows.length && (
          <p className="text-center p-12 text-slate-500">
            {loading ? "Carregando…" : "Nenhum comprovante nesta data."}
          </p>
        )}
      </section>
      {preview && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label="Evidência de entrega"
          className="fixed inset-0 bg-black/70 z-50 flex items-center justify-center p-6"
          onClick={() => setPreview("")}
        >
          <div
            className="bg-white rounded-2xl p-4 max-w-3xl max-h-full"
            onClick={(e) => e.stopPropagation()}
          >
            <button
              autoFocus
              onClick={() => setPreview("")}
              aria-label="Fechar evidência"
              className="block ml-auto mb-3"
            >
              <X />
            </button>
            <img
              src={preview}
              alt="Comprovante privado da entrega"
              className="max-h-[75vh] object-contain"
            />
          </div>
        </div>
      )}
    </div>
  );
}
