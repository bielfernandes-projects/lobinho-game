'use client'

import { useEffect, useState } from 'react'
import Image from 'next/image'
import { CARD_CATALOG, ROLE_LABEL, ROLE_STYLE } from '@/lib/cards'
import type { CadernetaPlayer } from '@/lib/caderneta/state'

interface DealScreenProps {
  player: CadernetaPlayer
  isLast: boolean
  onNext: () => void
}

type Step = 'handoff' | 'view' | 'return'

// Render with `key={dealIndex}` so each player starts from the neutral hand-off screen.
export function DealScreen({ player, isLast, onNext }: DealScreenProps) {
  const [step, setStep] = useState<Step>('handoff')
  const [holding, setHolding] = useState(false)
  const [seen, setSeen] = useState(false)
  const card = CARD_CATALOG.find((c) => c.id === player.role)

  // Never leave the card face up if the tab is hidden or loses focus.
  useEffect(() => {
    const hide = () => setHolding(false)
    document.addEventListener('visibilitychange', hide)
    window.addEventListener('blur', hide)
    return () => {
      document.removeEventListener('visibilitychange', hide)
      window.removeEventListener('blur', hide)
    }
  }, [])

  if (step === 'handoff') {
    return (
      <div className="min-h-[70dvh] flex flex-col items-center justify-center gap-8 text-center">
        <p className="text-neutral-500 text-xs uppercase tracking-widest">Passe o celular para</p>
        <p className="font-display text-6xl tracking-widest text-red-600 break-words max-w-full">{player.name}</p>
        <button
          type="button"
          onClick={() => setStep('view')}
          className="w-full max-w-xs py-4 rounded-2xl font-bold tracking-wider bg-primary hover:bg-primary-hover active:bg-primary-active text-white shadow-lg shadow-red-900/30 cursor-pointer transition-all"
        >
          Estou com o celular
        </button>
      </div>
    )
  }

  if (step === 'return') {
    return (
      <div className="min-h-[70dvh] flex flex-col items-center justify-center gap-8 text-center">
        <p className="font-display text-5xl tracking-widest text-red-600">ENTREGUE AO MESTRE</p>
        <p className="text-neutral-500 text-sm">Todos já viram a carta. Devolva o celular ao mestre.</p>
        <button
          type="button"
          onClick={onNext}
          className="w-full max-w-xs py-4 rounded-2xl font-bold tracking-wider bg-primary hover:bg-primary-hover active:bg-primary-active text-white shadow-lg shadow-red-900/30 cursor-pointer transition-all"
        >
          Sou o mestre
        </button>
      </div>
    )
  }

  return (
    <div className="min-h-[70dvh] flex flex-col items-center justify-center gap-6 text-center">
      <p className="text-neutral-400 text-sm">
        <span className="text-neutral-200 font-bold">{player.name}</span>, segure a carta para ver.
      </p>

      <div
        className="relative w-64 aspect-[7/10] rounded-2xl overflow-hidden border border-neutral-800 touch-none select-none [-webkit-touch-callout:none] cursor-pointer"
        onPointerDown={(e) => {
          try {
            e.currentTarget.setPointerCapture(e.pointerId)
          } catch {}
          setHolding(true)
          setSeen(true)
        }}
        onPointerUp={() => setHolding(false)}
        onPointerCancel={() => setHolding(false)}
        onLostPointerCapture={() => setHolding(false)}
        onContextMenu={(e) => e.preventDefault()}
      >
        {holding ? (
          <div className="absolute inset-0 bg-neutral-900 p-5 flex flex-col items-center justify-center gap-4">
            <span
              className={`px-3 py-1.5 rounded-lg border text-lg font-bold ${ROLE_STYLE[player.role] ?? 'bg-neutral-200 text-neutral-800 border-neutral-400'}`}
            >
              {ROLE_LABEL[player.role] ?? player.role}
            </span>
            <p className="text-neutral-300 text-sm leading-relaxed">{card?.description}</p>
          </div>
        ) : (
          <Image
            src="/verse-card.jpeg"
            alt=""
            fill
            sizes="256px"
            draggable={false}
            className="object-cover pointer-events-none select-none [-webkit-touch-callout:none]"
          />
        )}
      </div>

      {seen && !holding && (
        <button
          type="button"
          onClick={() => (isLast ? setStep('return') : onNext())}
          className="w-full max-w-xs py-3.5 rounded-2xl font-bold tracking-wider bg-primary hover:bg-primary-hover active:bg-primary-active text-white shadow-lg shadow-red-900/30 cursor-pointer transition-all"
        >
          {isLast ? 'Devolver ao mestre' : 'Próximo'}
        </button>
      )}
    </div>
  )
}
