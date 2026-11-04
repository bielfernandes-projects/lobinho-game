import type { Metadata } from 'next'
import Image from 'next/image'
import Link from 'next/link'
import { InstallButton } from '@/components/install-button'
import { SupportFooter } from '@/components/support-footer'
import { HowItWorks } from '@/components/landing/how-it-works'

export const metadata: Metadata = {
  title: 'Lobinho — o mestre de Werewolf no seu bolso',
  description:
    'Um celular só conduz o jogo: sorteia e entrega as cartas, organiza a noite e avisa quem venceu. Sem conta, sem sala.',
}

const BENEFITS = [
  { title: 'Um celular só, sem conta', text: 'O mestre conduz tudo. Ninguém precisa instalar nada nem criar login.' },
  { title: 'Mais de 40 papéis', text: 'Monte o cenário e veja na hora se ele pende para a Vila ou para os Lobos.' },
  { title: 'Noite organizada', text: 'Ordem de acordar pronta e as escolhas de cada papel anotadas por você.' },
]

const CTA =
  'inline-block w-full max-w-xs py-4 rounded-2xl font-bold text-base tracking-wider text-center bg-primary hover:bg-primary-hover active:bg-primary-active text-white shadow-lg shadow-red-900/30 transition-all duration-200'

export default function Landing() {
  return (
    <div className="flex flex-col items-center min-h-dvh">
      <header className="w-full max-w-xl px-6 pt-16 pb-8 flex flex-col items-center gap-6 text-center">
        <div className="relative w-24 h-24">
          <Image
            src="/logo.png"
            alt="Lobinho"
            fill
            sizes="96px"
            priority
            className="rounded-3xl shadow-lg shadow-red-900/30"
          />
        </div>
        <h1 className="font-display text-6xl tracking-[0.18em] text-red-600 drop-shadow-[0_0_20px_rgba(220,38,38,0.3)]">
          LOBINHO
        </h1>
        <p className="text-neutral-200 text-xl font-bold">O mestre de Werewolf no seu bolso</p>
        <p className="text-neutral-500 text-sm leading-relaxed max-w-sm">
          Um celular só sorteia e entrega as cartas, organiza a noite e avisa quem venceu. A mesa continua olho no
          olho.
        </p>
        <Link href="/caderneta" className={CTA}>
          Começar
        </Link>
        <InstallButton />
      </header>

      <HowItWorks />

      <section className="w-full max-w-5xl px-6 pb-16">
        <h2 className="font-display text-4xl tracking-widest text-red-600 text-center mb-10">POR QUE USAR</h2>
        <ul className="grid gap-4 sm:grid-cols-3">
          {BENEFITS.map((b) => (
            <li key={b.title} className="rounded-2xl border border-neutral-800 bg-neutral-900/50 p-5 space-y-2">
              <h3 className="font-bold text-neutral-200">{b.title}</h3>
              <p className="text-neutral-500 text-sm leading-relaxed">{b.text}</p>
            </li>
          ))}
        </ul>
      </section>

      <section className="w-full max-w-xl px-6 pb-16 flex flex-col items-center gap-4 text-center">
        <p className="text-neutral-300 text-lg font-bold">Pronto para a próxima partida?</p>
        <Link href="/caderneta" className={CTA}>
          Começar
        </Link>
      </section>

      <footer className="w-full max-w-xs px-6 pb-10 flex flex-col gap-4">
        <SupportFooter />
        <Link
          href="/online"
          className="text-neutral-600 hover:text-neutral-400 text-[11px] text-center underline underline-offset-2"
        >
          Jogar online (criar ou entrar em uma sala)
        </Link>
      </footer>
    </div>
  )
}
