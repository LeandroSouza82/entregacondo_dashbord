import React, { useState, useEffect, useRef } from 'react';
import { 
  FileText, 
  ClipboardCheck, 
  BarChart3, 
  Scale, 
  CreditCard, 
  Folder,
  Package,
  FolderPlus, 
  X, 
  ChevronRight,
  Send,
  Sparkles
} from 'lucide-react';

interface DocumentosSelectorPopoverProps {
  onSelect: (documentoNome: string) => void;
  onClose: () => void;
}

interface CategoriaDocumento {
  id: string;
  nome: string;
  descricao: string;
  icone: React.ElementType;
  corBg: string;
  corTexto: string;
  destaque?: boolean;
}

const CATEGORIAS_DOCUMENTOS: CategoriaDocumento[] = [
  {
    id: 'edital',
    nome: 'Edital de Convocação',
    descricao: 'Convocação formal para assembleia geral',
    icone: FileText,
    corBg: 'bg-blue-50 border-blue-200',
    corTexto: 'text-[#1D4ED8]',
  },
  {
    id: 'registro_ata',
    nome: 'Registro de Ata',
    descricao: 'Cartório e deliberações de assembleia',
    icone: ClipboardCheck,
    corBg: 'bg-emerald-100 border-emerald-300',
    corTexto: 'text-emerald-800',
    destaque: true,
  },
  {
    id: 'prestacao',
    nome: 'Prestação de Contas',
    descricao: 'Relatórios contábeis, receitas e despesas',
    icone: BarChart3,
    corBg: 'bg-purple-50 border-purple-200',
    corTexto: 'text-purple-700',
  },
  {
    id: 'convencao',
    nome: 'Convenção / Regimento Interno',
    descricao: 'Normas, regulamentos e regras condominiais',
    icone: Scale,
    corBg: 'bg-indigo-50 border-indigo-200',
    corTexto: 'text-indigo-700',
  },
  {
    id: 'boletos',
    nome: 'Boletos',
    descricao: 'Cobranças, taxas e acordos de inadimplência',
    icone: CreditCard,
    corBg: 'bg-amber-50 border-amber-200',
    corTexto: 'text-amber-700',
  },
  {
    id: 'documentos_generico',
    nome: 'Documentos',
    descricao: 'Entrega genérica de envelope ou papéis',
    icone: Folder,
    corBg: 'bg-slate-100 border-slate-200',
    corTexto: 'text-slate-700',
  },
  {
    id: 'outros_documentos',
    nome: 'Outros documentos',
    descricao: 'Demais itens documentais não listados',
    icone: Package,
    corBg: 'bg-teal-50 border-teal-200',
    corTexto: 'text-teal-700',
  },
];

export const DocumentosSelectorPopover: React.FC<DocumentosSelectorPopoverProps> = ({
  onSelect,
  onClose,
}) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const outroInputRef = useRef<HTMLInputElement>(null);

  const [mostrandoCampoPersonalizado, setMostrandoCampoPersonalizado] = useState<boolean>(false);
  const [documentoCustomizadoTexto, setDocumentoCustomizadoTexto] = useState<string>('');

  // Fechar ao clicar fora ou tecla Escape
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        onClose();
      }
    };
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        onClose();
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    document.addEventListener('keydown', handleKeyDown);
    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
      document.removeEventListener('keydown', handleKeyDown);
    };
  }, [onClose]);

  // Foco no campo personalizado se aberto
  useEffect(() => {
    if (mostrandoCampoPersonalizado) {
      setTimeout(() => outroInputRef.current?.focus(), 50);
    }
  }, [mostrandoCampoPersonalizado]);

  const handleConfirmarCustomizado = () => {
    const finalTexto = documentoCustomizadoTexto.trim() || 'Outros documentos';
    onSelect(finalTexto);
  };

  return (
    <div
      ref={containerRef}
      className="absolute left-0 top-full mt-2 z-50 w-[340px] sm:w-[380px] max-w-[95vw] bg-white border border-slate-200/90 rounded-2xl shadow-2xl overflow-hidden animate-fadeIn ring-1 ring-slate-900/10"
      style={{ boxShadow: '0 20px 35px -10px rgba(15, 27, 45, 0.22), 0 0 1px 1px rgba(15, 27, 45, 0.05)' }}
    >
      {/* Cabeçalho */}
      <div className="px-4 py-3 bg-slate-50 border-b border-slate-100 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="w-7 h-7 rounded-lg bg-blue-100/80 text-[#1D4ED8] flex items-center justify-center">
            <FileText className="w-4 h-4" />
          </div>
          <div>
            <h4 className="text-xs font-bold text-[#0F1B2D]">Tipo de Documento</h4>
            <p className="text-[11px] text-slate-500">Selecione para anexar à observação</p>
          </div>
        </div>
        <button
          type="button"
          onClick={onClose}
          className="w-7 h-7 rounded-lg text-slate-400 hover:text-slate-600 hover:bg-slate-200/60 flex items-center justify-center transition-colors cursor-pointer"
          title="Fechar"
        >
          <X className="w-4 h-4" />
        </button>
      </div>

      {/* Lista de Opções */}
      <div className="p-2 space-y-1.5 max-h-[320px] overflow-y-auto">
        {CATEGORIAS_DOCUMENTOS.map((item) => {
          const Icone = item.icone;

          return (
            <button
              key={item.id}
              type="button"
              onClick={() => onSelect(item.nome)}
              className={`w-full text-left p-2.5 rounded-xl border transition-all flex items-center justify-between group cursor-pointer ${
                item.destaque
                  ? 'border-emerald-300 bg-emerald-50/50 hover:bg-emerald-50 hover:border-emerald-400 shadow-2xs ring-1 ring-emerald-500/15'
                  : 'border-slate-100 hover:border-[#1D4ED8]/30 hover:bg-blue-50/60'
              }`}
            >
              <div className="flex items-center gap-3 min-w-0">
                <div className={`w-8 h-8 rounded-lg border flex items-center justify-center flex-shrink-0 ${item.corBg} ${item.corTexto} shadow-2xs`}>
                  <Icone className="w-4 h-4" />
                </div>
                <div className="min-w-0">
                  <div className="flex items-center gap-1.5">
                    <span className="text-xs font-bold text-[#0F1B2D] group-hover:text-[#1D4ED8] transition-colors leading-snug">
                      {item.nome}
                    </span>
                    {item.destaque && (
                      <span className="inline-flex items-center gap-1 px-1.5 py-0.2 rounded-md bg-emerald-100 text-emerald-800 text-[10px] font-bold border border-emerald-200">
                        <Sparkles className="w-2.5 h-2.5 text-emerald-600" />
                        Principal
                      </span>
                    )}
                  </div>
                  <div className="text-[11px] text-slate-500 truncate leading-tight">
                    {item.descricao}
                  </div>
                </div>
              </div>

              <ChevronRight className={`w-4 h-4 text-slate-300 group-hover:translate-x-0.5 transition-all flex-shrink-0 ${
                item.destaque ? 'group-hover:text-emerald-700' : 'group-hover:text-[#1D4ED8]'
              }`} />
            </button>
          );
        })}

        {/* Opção para especificar termo customizado se necessário */}
        {!mostrandoCampoPersonalizado ? (
          <button
            type="button"
            onClick={() => setMostrandoCampoPersonalizado(true)}
            className="w-full text-left p-2 rounded-xl border border-dashed border-slate-200 hover:border-[#1D4ED8] hover:bg-slate-50 transition-all flex items-center justify-between group cursor-pointer text-slate-500 hover:text-slate-700"
          >
            <div className="flex items-center gap-2.5 text-xs font-medium">
              <FolderPlus className="w-4 h-4 text-slate-400 group-hover:text-[#1D4ED8]" />
              <span>Digitar outro nome personalizado...</span>
            </div>
            <span className="text-[10px] text-slate-400">+ Escrever</span>
          </button>
        ) : (
          <div className="p-2.5 rounded-xl border border-blue-200 bg-blue-50/40 space-y-2 animate-fadeIn">
            <label className="text-[11px] font-bold text-[#1D4ED8] flex items-center justify-between">
              <span>Digitar documento personalizado:</span>
              <button
                type="button"
                onClick={() => setMostrandoCampoPersonalizado(false)}
                className="text-slate-400 hover:text-slate-600 text-[10px] font-medium cursor-pointer"
              >
                Voltar
              </button>
            </label>
            <div className="flex items-center gap-1.5">
              <input
                ref={outroInputRef}
                type="text"
                value={documentoCustomizadoTexto}
                onChange={(e) => setDocumentoCustomizadoTexto(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    e.preventDefault();
                    handleConfirmarCustomizado();
                  }
                }}
                placeholder="Ex: Notificação Extrajudicial, Laudo..."
                className="flex-1 h-8 px-2.5 bg-white border border-slate-200 rounded-lg text-xs text-[#0F1B2D] focus:outline-none focus:ring-2 focus:ring-[#1D4ED8]/20 focus:border-[#1D4ED8]"
              />
              <button
                type="button"
                onClick={handleConfirmarCustomizado}
                className="h-8 px-2.5 rounded-lg bg-[#1D4ED8] hover:bg-[#1E40AF] text-white text-xs font-bold flex items-center gap-1 transition-colors cursor-pointer shadow-xs"
              >
                <span>Inserir</span>
                <Send className="w-3 h-3" />
              </button>
            </div>
          </div>
        )}
      </div>

      {/* Rodapé com pré-visualização */}
      <div className="px-3.5 py-2.5 bg-slate-50 border-t border-slate-100 flex items-center justify-between text-[11px] text-slate-500">
        <span>Formato inserido:</span>
        <code className="px-2 py-0.5 bg-white border border-slate-200 rounded font-semibold text-[#1D4ED8]">
          [Nome do serviço selecionado]
        </code>
      </div>
    </div>
  );
};
