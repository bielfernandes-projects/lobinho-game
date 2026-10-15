'use client'

import Link from 'next/link'
import { useCaderneta } from '@/hooks/use-caderneta'
import { SetupScreen } from '@/components/caderneta/setup-screen'
import { DealScreen } from '@/components/caderneta/deal-screen'
import { PlayPanel } from '@/components/caderneta/play-panel'
import { EndScreen } from '@/components/caderneta/end-screen'

export default function CadernetaPage() {
  const { state, dispatch, hydrated } = useCaderneta()

  if (!hydrated) return <main className="min-h-dvh" />

  const dealing = state.phase === 'deal' ? state.players[state.dealIndex] : undefined

  return (
    <main className="mx-auto w-full max-w-sm min-h-dvh px-4 py-6">
      {state.phase === 'setup' && (
        <>
          <Link href="/" className="inline-block mb-4 text-neutral-500 hover:text-neutral-300 text-xs">
            ← Início
          </Link>
          <SetupScreen state={state} dispatch={dispatch} />
        </>
      )}
      {dealing && (
        <DealScreen
          key={state.dealIndex}
          player={dealing}
          isLast={state.dealIndex === state.players.length - 1}
          onNext={() => dispatch({ type: 'nextDeal' })}
        />
      )}
      {state.phase === 'play' && <PlayPanel state={state} dispatch={dispatch} />}
      {state.phase === 'ended' && <EndScreen state={state} dispatch={dispatch} />}
    </main>
  )
}
