import Image from 'next/image'
import Link from 'next/link'
import { InstallButton } from '@/components/install-button'
import { SupportFooter } from '@/components/support-footer'

export default function EntryScreen() {
  return (
    <div className="flex flex-1 flex-col items-center justify-center px-6 min-h-dvh">
      <div className="w-full max-w-xs flex flex-col items-center gap-10">
        <div className="text-center">
          <div className="relative w-24 h-24 mx-auto mb-5">
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
          <p className="text-neutral-600 text-xs tracking-widest uppercase mt-2">
            A Werewolf Game Based
          </p>
        </div>

        <div className="w-full flex flex-col gap-4">
          <Link
            href="/caderneta"
            className="
              w-full py-4 rounded-2xl font-bold text-base tracking-wider text-center
              bg-primary hover:bg-primary-hover active:bg-primary-active text-white
              shadow-lg shadow-red-900/30
              transition-all duration-200
            "
          >
            Caderneta do Mestre
          </Link>
          <p className="text-neutral-500 text-xs text-center leading-relaxed">
            Um celular só, o mestre conduz. Cada jogador vê a própria carta sem precisar de conta.
          </p>

          <div className="flex justify-center mt-2">
            <InstallButton />
          </div>

          <SupportFooter />

          <Link
            href="/online"
            className="text-neutral-600 hover:text-neutral-400 text-[11px] text-center underline underline-offset-2"
          >
            Jogar online (criar ou entrar em uma sala)
          </Link>
        </div>
      </div>
    </div>
  )
}
