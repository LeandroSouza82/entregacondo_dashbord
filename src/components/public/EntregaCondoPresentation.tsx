import { ArrowRight, ClipboardCheck, MapPinned, Route } from 'lucide-react';
import { EntregaCondoLogo } from '../common/EntregaCondoLogo';

const features = [
  { icon: Route, title: 'Uma rota mais organizada', description: 'Entregas, coletas e serviços reunidos em uma sequência clara para o motorista.' },
  { icon: MapPinned, title: 'A chegada, acompanhada', description: 'O cliente recebe um link para acompanhar o atendimento e consultar a previsão de chegada quando disponível.' },
  { icon: ClipboardCheck, title: 'Cada atendimento registrado', description: 'Comprovantes, fotos e informações de recebimento para a empresa consultar depois.' },
];

export default function EntregaCondoPresentation() {
  return (
    <main className="min-h-screen bg-[#FAF8F5] text-slate-900">
      <div className="mx-auto max-w-5xl px-5 py-6 sm:px-8 sm:py-8">
        <header className="flex flex-wrap items-center justify-between gap-4">
          <EntregaCondoLogo height={36} wordmarkColor="#0F1B2D" />
          <a href="/#/cadastro" className="inline-flex min-h-11 items-center rounded-xl border border-slate-300 bg-white px-4 text-sm font-semibold focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-700">
            Testar grátis
          </a>
        </header>
        <section className="py-14 sm:py-20" aria-labelledby="presentation-title">
          <p className="text-sm font-semibold uppercase tracking-widest text-orange-800">EntregaCondo</p>
          <h1 id="presentation-title" className="mt-4 max-w-3xl text-4xl font-extrabold leading-tight tracking-tight sm:text-6xl">
            Entregas e coletas com mais organização.
          </h1>
          <p className="mt-6 max-w-2xl text-lg leading-relaxed text-slate-600">
            Da organização da rota ao registro do atendimento, conecte a empresa, o motorista e quem está esperando a chegada.
          </p>
          <a href="/#/cadastro" className="mt-8 inline-flex min-h-12 items-center gap-3 rounded-xl bg-orange-700 px-5 py-3 font-bold text-white hover:bg-orange-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-700">
            Experimente grátis por 30 dias <ArrowRight size={18} aria-hidden="true" />
          </a>
          <p className="mt-4 text-sm text-slate-600">Sem cartão. Depois, R$ 149,90/mês por empresa · até 3 motoristas ativos e 1.000 atendimentos por mês.</p>
        </section>
        <section className="grid gap-4 sm:grid-cols-3" aria-label="O que o EntregaCondo oferece">
          {features.map(({ icon: Icon, title, description }) => (
            <article key={title} className="rounded-2xl border border-slate-200 bg-white p-6">
              <div className="inline-flex rounded-xl bg-orange-50 p-3 text-orange-800"><Icon size={23} aria-hidden="true" /></div>
              <h2 className="mt-5 text-lg font-bold">{title}</h2>
              <p className="mt-2 text-sm leading-relaxed text-slate-600">{description}</p>
            </article>
          ))}
        </section>
        <footer className="pb-4 pt-12 text-sm text-slate-500">EntregaCondo · Mais clareza em cada atendimento.</footer>
      </div>
    </main>
  );
}
