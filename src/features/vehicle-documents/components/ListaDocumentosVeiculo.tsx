import React from 'react';
import { FileText, Image, Eye, Clock, CheckCircle2, XCircle, AlertTriangle } from 'lucide-react';
import type { DocumentoVeiculoItem, AnguloFotoVeiculo } from '../types/vehicleDocument';

interface ListaDocumentosVeiculoProps {
  documentos: DocumentoVeiculoItem[];
  onSelecionarDocumento: (doc: DocumentoVeiculoItem) => void;
}

const ANGULOS_ORDENADOS: { id: AnguloFotoVeiculo; rotulo: string }[] = [
  { id: 'frente', rotulo: 'Frente' },
  { id: 'lado_direito', rotulo: 'Lado Direito' },
  { id: 'lado_esquerdo', rotulo: 'Lado Esquerdo' },
  { id: 'traseira', rotulo: 'Traseira' },
];

export const ListaDocumentosVeiculo: React.FC<ListaDocumentosVeiculoProps> = ({
  documentos,
  onSelecionarDocumento,
}) => {
  // 1. Separação das fotos pelos 4 ângulos
  const fotosPorAngulo = new Map<AnguloFotoVeiculo, DocumentoVeiculoItem>();
  const fotosLegado: DocumentoVeiculoItem[] = [];
  const crlvDocs: DocumentoVeiculoItem[] = [];
  const complementares: DocumentoVeiculoItem[] = [];

  documentos.forEach((doc) => {
    if (doc.tipo_documento === 'foto_veiculo') {
      if (doc.angulo_foto) {
        fotosPorAngulo.set(doc.angulo_foto, doc);
      } else {
        fotosLegado.push(doc);
      }
    } else if (doc.tipo_documento === 'crlv') {
      crlvDocs.push(doc);
    } else {
      complementares.push(doc);
    }
  });

  const qtdFotosValidas = fotosPorAngulo.size;
  const possuiCrlv = crlvDocs.length > 0;

  return (
    <div className="space-y-4">
      {/* SEÇÃO 1: AS 4 FOTOS DO VEÍCULO */}
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <div className="text-[11px] font-bold text-[#0F1B2D] uppercase tracking-wider flex items-center gap-1.5">
            <span>Fotos do Veículo ({qtdFotosValidas}/4)</span>
            {qtdFotosValidas === 4 ? (
              <span className="px-1.5 py-0.5 rounded text-[10px] bg-emerald-100 text-emerald-700 font-semibold">
                Completo
              </span>
            ) : (
              <span className="px-1.5 py-0.5 rounded text-[10px] bg-amber-100 text-amber-700 font-semibold">
                Faltam {4 - qtdFotosValidas}
              </span>
            )}
          </div>
        </div>

        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
          {ANGULOS_ORDENADOS.map(({ id, rotulo }) => {
            const foto = fotosPorAngulo.get(id);

            if (foto) {
              return (
                <div
                  key={id}
                  className="p-2.5 bg-white border border-slate-200 rounded-xl flex flex-col justify-between hover:border-[#1D4ED8]/40 transition-colors shadow-sm"
                >
                  <div className="flex items-center justify-between gap-1 mb-1.5">
                    <span className="text-[11px] font-bold text-[#0F1B2D]">{rotulo}</span>
                    <div className="flex items-center gap-1">
                      {foto.status_analise === 'aprovado' && <CheckCircle2 className="w-3.5 h-3.5 text-emerald-600" />}
                      {foto.status_analise === 'rejeitado' && <XCircle className="w-3.5 h-3.5 text-red-500" />}
                      {foto.status_analise === 'pendente' && <Clock className="w-3.5 h-3.5 text-amber-500" />}
                    </div>
                  </div>

                  <div className="text-[10px] text-slate-500 truncate mb-2" title={foto.nome_arquivo}>
                    {foto.nome_arquivo}
                  </div>

                  <button
                    type="button"
                    onClick={() => onSelecionarDocumento(foto)}
                    className="w-full py-1 px-2 rounded-lg bg-blue-50 text-[#1D4ED8] hover:bg-blue-100 text-[11px] font-semibold flex items-center justify-center gap-1 transition-colors cursor-pointer"
                  >
                    <Eye className="w-3.5 h-3.5" />
                    Visualizar
                  </button>
                </div>
              );
            }

            // Slot de ângulo faltante
            return (
              <div
                key={id}
                className="p-2.5 bg-slate-50 border border-dashed border-slate-300 rounded-xl flex flex-col justify-between"
              >
                <div className="flex items-center justify-between gap-1 mb-1">
                  <span className="text-[11px] font-bold text-slate-500">{rotulo}</span>
                  <AlertTriangle className="w-3.5 h-3.5 text-amber-500" />
                </div>
                <div className="text-[10px] text-slate-400 italic">
                  Foto pendente
                </div>
                <div className="mt-2 text-[10px] text-slate-400 font-medium">
                  Não enviada
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* SEÇÃO 2: CRLV (OBRIGATÓRIO) */}
      <div className="space-y-1.5">
        <div className="text-[11px] font-bold text-[#0F1B2D] uppercase tracking-wider flex items-center gap-1.5">
          <span>Documento do Veículo — CRLV</span>
          {possuiCrlv ? (
            <span className="px-1.5 py-0.5 rounded text-[10px] bg-emerald-100 text-emerald-700 font-semibold">
              Anexado
            </span>
          ) : (
            <span className="px-1.5 py-0.5 rounded text-[10px] bg-red-100 text-red-700 font-semibold">
              Obrigatório
            </span>
          )}
        </div>

        {possuiCrlv ? (
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
            {crlvDocs.map((doc) => (
              <div
                key={doc.id}
                className="p-2.5 bg-white border border-slate-200 rounded-xl flex items-center justify-between hover:border-[#1D4ED8]/40 transition-colors"
              >
                <div className="flex items-center gap-2 min-w-0">
                  <div className="w-8 h-8 rounded-lg bg-emerald-50 flex items-center justify-center flex-shrink-0 text-emerald-600">
                    <FileText className="w-4 h-4" />
                  </div>
                  <div className="min-w-0">
                    <span className="font-semibold text-xs text-[#0F1B2D] truncate block">
                      {doc.nome_arquivo}
                    </span>
                    <span className="text-[10px] text-slate-400">
                      CRLV · {(doc.tamanho_bytes / 1024).toFixed(0)} KB
                    </span>
                  </div>
                </div>

                <div className="flex items-center gap-1 flex-shrink-0">
                  {doc.status_analise === 'aprovado' && <CheckCircle2 className="w-3.5 h-3.5 text-emerald-600" />}
                  {doc.status_analise === 'rejeitado' && <XCircle className="w-3.5 h-3.5 text-red-500" />}
                  {doc.status_analise === 'pendente' && <Clock className="w-3.5 h-3.5 text-amber-500" />}

                  <button
                    type="button"
                    onClick={() => onSelecionarDocumento(doc)}
                    className="p-1.5 rounded-lg text-slate-500 hover:text-[#1D4ED8] hover:bg-slate-100 transition-colors cursor-pointer"
                    title="Visualizar CRLV"
                  >
                    <Eye className="w-4 h-4" />
                  </button>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="p-2.5 bg-amber-50 border border-amber-200 rounded-xl text-amber-700 text-xs flex items-center gap-2">
            <AlertTriangle className="w-4 h-4 flex-shrink-0 text-amber-600" />
            <span>Condutor ainda não anexou o CRLV. A aprovação requer conferência documental do CRLV.</span>
          </div>
        )}
      </div>

      {/* SEÇÃO 3: DOCUMENTOS COMPLEMENTARES */}
      {complementares.length > 0 && (
        <div className="space-y-1.5">
          <div className="text-[11px] font-bold text-[#0F1B2D] uppercase tracking-wider">
            Documentos Complementares ({complementares.length})
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
            {complementares.map((doc) => (
              <div
                key={doc.id}
                className="p-2.5 bg-white border border-slate-200 rounded-xl flex items-center justify-between hover:border-[#1D4ED8]/40 transition-colors"
              >
                <div className="flex items-center gap-2 min-w-0">
                  <div className="w-8 h-8 rounded-lg bg-slate-100 flex items-center justify-center flex-shrink-0 text-slate-600">
                    <FileText className="w-4 h-4 text-amber-600" />
                  </div>
                  <div className="min-w-0">
                    <span className="font-semibold text-xs text-[#0F1B2D] truncate block">
                      {doc.nome_arquivo}
                    </span>
                    <span className="text-[10px] text-slate-400">
                      Complementar · {(doc.tamanho_bytes / 1024).toFixed(0)} KB
                    </span>
                  </div>
                </div>

                <button
                  type="button"
                  onClick={() => onSelecionarDocumento(doc)}
                  className="p-1.5 rounded-lg text-slate-500 hover:text-[#1D4ED8] hover:bg-slate-100 transition-colors cursor-pointer"
                  title="Visualizar documento"
                >
                  <Eye className="w-4 h-4" />
                </button>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* SEÇÃO 4: FOTOS ANTERIORES / LEGADO (SEM CLASSIFICAÇÃO DE ÂNGULO) */}
      {fotosLegado.length > 0 && (
        <div className="space-y-1.5">
          <div className="text-[11px] font-bold text-slate-400 uppercase tracking-wider">
            Fotos Anteriores (Legado sem ângulo)
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
            {fotosLegado.map((doc) => (
              <div
                key={doc.id}
                className="p-2 bg-slate-50 border border-slate-200 rounded-xl flex items-center justify-between opacity-80"
              >
                <div className="flex items-center gap-2 min-w-0">
                  <Image className="w-4 h-4 text-slate-400 flex-shrink-0" />
                  <span className="text-xs text-slate-600 truncate">{doc.nome_arquivo}</span>
                </div>
                <button
                  type="button"
                  onClick={() => onSelecionarDocumento(doc)}
                  className="p-1 rounded text-slate-500 hover:text-slate-800"
                >
                  <Eye className="w-3.5 h-3.5" />
                </button>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};
