import { ArrowUpRight } from 'lucide-react';
import { EntregaCondoLogo } from '../common/EntregaCondoLogo';

export function CustomerTrackingBrand() {
  return (
    <footer className="border-t border-slate-200 pt-5 text-center" aria-label="Sobre o EntregaCondo">
      <div className="flex justify-center"><EntregaCondoLogo height={26} wordmarkColor="#0F1B2D" /></div>
      <p className="mx-auto mt-3 max-w-sm text-sm leading-relaxed text-slate-500">
        Mais organização para quem entrega. Mais clareza para quem recebe.
      </p>
      <a
        href="/#/conheca"
        target="_blank"
        rel="noopener noreferrer"
        className="mt-2 inline-flex min-h-11 items-center gap-1 rounded-lg px-3 text-sm font-semibold text-orange-800 underline-offset-4 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-700"
      >
        Conheça o EntregaCondo <ArrowUpRight size={16} aria-hidden="true" />
      </a>
    </footer>
  );
}
