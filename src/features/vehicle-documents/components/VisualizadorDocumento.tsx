import React, { useState, useEffect } from 'react';
import { X, ExternalLink, Download, FileText, Image, AlertCircle, Loader2 } from 'lucide-react';
import { obterUrlVisualizacaoDocumento } from '../services/obterUrlVisualizacaoDocumento';
import type { DocumentoVeiculoItem } from '../types/vehicleDocument';

interface VisualizadorDocumentoProps {
  documento: DocumentoVeiculoItem | null;
  onFechar: () => void;
}

export const VisualizadorDocumento: React.FC<VisualizadorDocumentoProps> = ({
  documento,
  onFechar,
}) => {
  const [urlAssinada, setUrlAssinada] = useState<string | null>(null);
  const [carregando, setCarregando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    if (!documento) {
      setUrlAssinada(null);
      return;
    }

    let ativo = true;
    setCarregando(true);
    setErro(null);

    obterUrlVisualizacaoDocumento(documento.storage_path)
      .then((url) => {
        if (ativo) setUrlAssinada(url);
      })
      .catch((err) => {
        if (ativo) setErro(err instanceof Error ? err.message : 'Erro ao carregar visualização.');
      })
      .finally(() => {
        if (ativo) setCarregando(false);
      });

    return () => {
      ativo = false;
    };
  }, [documento]);

  if (!documento) return null;

  const ehImagem = documento.mime_type.startsWith('image/');
  const ehPdf = documento.mime_type === 'application/pdf';

  return (
    <div className="fixed inset-0 z-50 bg-[#0F1B2D]/70 backdrop-blur-xs flex items-center justify-center p-4 animate-fadeIn">
      <div className="bg-white rounded-2xl max-w-2xl w-full border border-[#CBD5E1] shadow-2xl overflow-hidden flex flex-col max-h-[90vh]">
        {/* Cabeçalho */}
        <div className="flex items-center justify-between p-4 border-b border-slate-100 bg-slate-50/50">
          <div className="flex items-center gap-2">
            {ehImagem ? <Image className="w-5 h-5 text-[#1D4ED8]" /> : <FileText className="w-5 h-5 text-amber-600" />}
            <div>
              <h3 className="font-bold text-sm text-[#0F1B2D] m-0">{documento.nome_arquivo}</h3>
              <p className="text-[11px] text-slate-500 m-0">
                Tipo: <strong className="uppercase">{documento.tipo_documento.replace('_', ' ')}</strong> · {(documento.tamanho_bytes / 1024).toFixed(1)} KB
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onFechar}
            className="text-slate-400 hover:text-slate-600 p-1 rounded-lg"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Área de Conteúdo */}
        <div className="p-4 overflow-y-auto flex-1 flex items-center justify-center bg-slate-100/50 min-h-[300px]">
          {carregando && (
            <div className="flex flex-col items-center gap-2 text-slate-500">
              <Loader2 className="w-8 h-8 animate-spin text-[#1D4ED8]" />
              <span className="text-xs">Gerando link seguro de visualização...</span>
            </div>
          )}

          {erro && (
            <div className="p-4 bg-red-50 border border-red-200 rounded-xl text-red-700 text-xs flex items-center gap-2">
              <AlertCircle className="w-5 h-5 flex-shrink-0" />
              <span>{erro}</span>
            </div>
          )}

          {!carregando && !erro && urlAssinada && (
            <>
              {ehImagem && (
                <img
                  src={urlAssinada}
                  alt={documento.nome_arquivo}
                  className="max-h-[60vh] max-w-full rounded-lg object-contain shadow-sm border border-slate-200"
                />
              )}

              {ehPdf && (
                <div className="w-full h-[55vh] flex flex-col items-center justify-center p-6 bg-white rounded-xl border border-slate-200 text-center space-y-3">
                  <FileText className="w-16 h-16 text-red-500" />
                  <div>
                    <p className="font-bold text-sm text-[#0F1B2D]">Documento PDF Carregado</p>
                    <p className="text-xs text-slate-500">Para conferência completa, visualize em uma nova aba segura.</p>
                  </div>
                  <a
                    href={urlAssinada}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="h-10 px-4 rounded-xl bg-[#0F1B2D] text-white text-xs font-bold flex items-center gap-2 hover:bg-[#1A2E4C] transition-colors"
                  >
                    <ExternalLink className="w-4 h-4" />
                    Abrir PDF em Nova Aba
                  </a>
                </div>
              )}
            </>
          )}
        </div>

        {/* Rodapé */}
        <div className="p-3 border-t border-slate-100 bg-white flex items-center justify-between">
          <span className="text-[11px] text-slate-400">
            Link autenticado com validade temporária (1h)
          </span>
          {urlAssinada && (
            <a
              href={urlAssinada}
              download={documento.nome_arquivo}
              className="h-8 px-3 rounded-lg border border-slate-300 text-slate-700 hover:bg-slate-50 text-xs font-semibold flex items-center gap-1.5"
            >
              <Download className="w-3.5 h-3.5" />
              Baixar Arquivo
            </a>
          )}
        </div>
      </div>
    </div>
  );
};
