'use client'

import type { Dispatch } from 'react'
import { ROLE_LABEL, ROLE_STYLE } from '@/lib/cards'
import { winnerOf, type Action, type CadernetaState } from '@/lib/caderneta/state'
import { WinnerBanner } from './winner-banner'

interface EndScreenProps {
  state: CadernetaState
  dispatch: Dispatch<Action>
}

export function EndScreen({ state, dispatch }: EndScreenProps) {
  const winner = winnerOf(state)
  return (
    <div className="space-y-6">
      <header className="text-center space-y-1">
        <h1 className="font-display text-5xl tracking-widest text-red-600">FIM DE JOGO</h1>
        <p className="text-neutral-500 text-xs">Os papéis de todos, na partida que acabou.</p>
      </header>

      {winner && <WinnerBanner winner={winner} />}

      <ul className="space-y-2">
        {state.players.map((p) => (
          <li
            key={p.id}
            className="flex items-center gap-3 px-4 py-3 rounded-xl border border-neutral-800 bg-neutral-900/50"
          >
            <span
              className={`flex-1 truncate text-sm ${p.alive ? 'text-neutral-200' : 'text-neutral-500 line-through'}`}
            >
              {p.name}
            </span>
            <span className={`px-2 py-0.5 rounded-md border text-[11px] font-medium ${ROLE_STYLE[p.role] ?? ''}`}>
              {ROLE_LABEL[p.role] ?? p.role}
            </span>
          </li>
        ))}
      </ul>

      <button
        type="button"
        onClick={() => dispatch({ type: 'cancel' })}
        className="w-full py-4 rounded-2xl font-bold text-lg tracking-wider bg-red-700 text-white hover:bg-red-600 active:bg-red-800 shadow-lg shadow-red-900/40 cursor-pointer transition-all"
      >
        Nova partida
      </button>
    </div>
  )
}
