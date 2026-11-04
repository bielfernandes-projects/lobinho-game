'use client'

import type { Dispatch } from 'react'
import { VoteTimerPanel } from '@/components/vote-timer-panel'
import type { Action, CadernetaState } from '@/lib/caderneta/state'

interface DayToolsProps {
  state: CadernetaState
  dispatch: Dispatch<Action>
}

export function DayTools({ dispatch }: DayToolsProps) {
  return (
    <section className="space-y-4">
      <VoteTimerPanel title="Manhã" label="⏱️ Tempo da manhã" defaultMinutes={5} />

      <button
        type="button"
        onClick={() => dispatch({ type: 'toNight' })}
        className="w-full py-3.5 rounded-2xl font-bold tracking-wider bg-primary hover:bg-primary-hover active:bg-primary-active text-white shadow-lg shadow-red-900/30 cursor-pointer transition-all"
      >
        🌙 Anoitecer
      </button>
    </section>
  )
}
