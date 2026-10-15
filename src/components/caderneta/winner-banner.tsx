'use client'

import { WINNER_VIEW, type Winner } from '@/lib/caderneta/winner'

interface WinnerBannerProps {
  winner: Winner
  /** When given, shows the button that ends the match (the host decides when). */
  onEnd?: () => void
}

export function WinnerBanner({ winner, onEnd }: WinnerBannerProps) {
  const view = WINNER_VIEW[winner]
  return (
    <div
      role="status"
      className="rounded-2xl border border-red-700 bg-red-950/30 px-4 py-5 text-center space-y-3 shadow-lg shadow-red-900/30"
    >
      <p className="text-5xl">{view.emoji}</p>
      <p className="font-display text-3xl tracking-widest text-red-500">{view.title}</p>
      {onEnd && (
        <>
          <p className="text-neutral-400 text-xs leading-relaxed">
            Pela contagem dos vivos, o jogo já tem vencedor. Você decide quando encerrar.
          </p>
          <button
            type="button"
            onClick={onEnd}
            className="w-full py-3 rounded-xl font-bold tracking-wider bg-red-700 text-white hover:bg-red-600 active:bg-red-800 cursor-pointer transition-all"
          >
            🏁 Encerrar e revelar papéis
          </button>
        </>
      )}
    </div>
  )
}
