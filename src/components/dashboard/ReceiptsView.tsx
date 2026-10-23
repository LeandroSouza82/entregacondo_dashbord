import {shareReceipt} from "../../features/receipts/receiptSharing";
import { receiptLabel } from "./receiptLabels";
import { useEffect, useState } from "react";
import { Camera, Check, Copy, X } from "lucide-react";
import { supabase, supabaseUrl } from "../../lib/supabase";
import { requireCompanyId } from "../../lib/company";
import type { Database } from "../../types/database";
type Receipt = Database["public"]["Tables"]["entrega_comprovantes"]["Row"] & {
  entregas: { destinatario_nome: string; motorista_id: string | null } | null;
};
export function ReceiptsView({ title = "Comprovantes" }: { title?: string }) {
  const [rows, setRows] = useState<Receipt[]>([]);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const [copyingId,setCopyingId]=useState<string|null>(null);
  const [copyNotice,setCopyNotice]=useState("");
  const [copiedId, setCopiedId] = useState<string | null>(null);
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

  async function handleCopy(r: Receipt) {
    if (copyingId) return;
    setCopyingId(r.entrega_id);setError('');setCopyNotice('');
    try {
    const shared = await shareReceipt(supabase,r,window.location.href,supabaseUrl);
    const publicUrl = shared.url;
    const dataConclusao = new Date(r.concluida_em);
    const dataFormatada = dataConclusao.toLocaleDateString("pt-BR");
    const horaFormatada = dataConclusao.toLocaleTimeString("pt-BR", {
      hour: "2-digit",
      minute: "2-digit",
    });

    const tempoFormatado = `${Math.floor(r.duracao_segundos / 60)} min ${r.duracao_segundos % 60}s`;
    const recebedorFormatado =
      [receiptLabel(r.recebedor_tipo), r.recebedor_nome]
        .filter(Boolean)
        .join(" · ") + (r.observacao ? ` (${r.observacao})` : "");

    const texto = [
      "📦 *Comprovante de Atendimento*",
      `👤 *Cliente:* ${r.entregas?.destinatario_nome || "Cliente"}`,
      `🤝 *Recebedor:* ${recebedorFormatado || "Não informado"}`,
      `🕒 *Data/Hora:* ${dataFormatada} às ${horaFormatada}`,
      `⏱️ *Tempo de atendimento:* ${tempoFormatado}`,
      "",
      "📎 *Evidência:*",
      publicUrl,
    ].join("\n");

    await navigator.clipboard.writeText(texto);
    setCopiedId(r.entrega_id);
    setCopyNotice('Comprovante copiado com link válido por 55 minutos. Um novo link substitui o anterior.');
    setTimeout(() => setCopiedId(curr=>curr===r.entrega_id?null:curr),2000);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Não foi possível copiar o comprovante.');
    } finally {setCopyingId(null);}
  }

  async function revokeShare(r:Receipt) {
    if(copyingId)return;
    setCopyingId(r.entrega_id);setError('');setCopyNotice('');
    try {
      const {data,error}=await supabase.rpc('revogar_compartilhamento_comprovante',{p_entrega_id:r.entrega_id});
      if(error || (data as {sucesso?:boolean}|null)?.sucesso!==true)throw new Error('Não foi possível revogar o link. Tente novamente.');
      setCopiedId(null);setCopyNotice('Link de acesso ao comprovante revogado.');
    } catch(error){setError(error instanceof Error?error.message:'Não foi possível revogar o link.');}
    finally {setCopyingId(null);}
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
          <section key={label} className="bg-white border border-gray-300 rounded-2xl p-5">
            <p className="text-sm text-slate-500">{label}</p>
            <strong className="text-2xl">{loading ? "—" : value}</strong>
          </section>
        ))}
      </div>
      {copyNotice && <p role="status" className="rounded-xl bg-emerald-50 p-3 text-sm text-emerald-800">{copyNotice}</p>}
      {error && (
        <p role="alert" className="bg-red-50 text-red-800 p-4 rounded-xl">
          {error}
        </p>
      )}
      <section className="bg-white border border-gray-300 rounded-2xl overflow-x-auto">
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
                  <div className="flex items-center justify-between gap-3">
                    <div className="flex gap-3 items-center">
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
                      {!r.foto_path && !r.assinatura_path && (
                        <span className="text-slate-400">—</span>
                      )}
                    </div>
                    <button
                      type="button"
                      onClick={() => void handleCopy(r)}
                      disabled={copyingId!==null}
                      title="Copiar comprovante com link temporário"
                      aria-label="Copiar dados do comprovante"
                      className="p-1.5 rounded-lg text-gray-400 hover:text-gray-700 hover:bg-gray-100 transition-colors cursor-pointer shrink-0"
                    >
                      {copiedId === r.entrega_id ? (
                        <Check size={16} className="text-emerald-600" />
                      ) : (
                        <Copy size={16} />
                      )}
                    </button>
                    <button type="button" disabled={copyingId!==null} onClick={()=>void revokeShare(r)} title="Revogar link temporário" aria-label="Revogar link do comprovante" className="p-1.5 rounded-lg text-gray-400 hover:text-red-700 disabled:opacity-50"><X size={16}/></button>
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
