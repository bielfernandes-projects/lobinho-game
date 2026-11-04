'use client'

import { useState, type Dispatch } from 'react'
import { MAX_STRIKES, type Action, type CadernetaState } from '@/lib/caderneta/state'

interface StrikesPanelProps {
  state: CadernetaState
  dispatch: Dispatch<Action>
}

// Strikes (0 to 3) of the living players. Lives below the players list in a closed accordion;
// it opens by itself when a player reaches the 3rd strike so the master sees the confirmation.
export function StrikesPanel({ state, dispatch }: StrikesPanelProps) {
  const [pendingKill, setPendingKill] = useState<string | null>(null)
  const alive = state.players.filter((p) => p.alive)
  const target = state.players.find((p) => p.id === pendingKill)

  return (
    <details open={target ? true : undefined} className="rounded-xl border border-neutral-800 bg-neutral-900/30">
      <summary className="px-4 py-3 text-xs uppercase tracking-widest text-neutral-400 cursor-pointer select-none">
        Strikes
      </summary>
      <div className="px-3 pb-3 space-y-2">
        {alive.map((p) => (
          <div
            key={p.id}
            className="flex items-center gap-2 px-3 py-2 rounded-xl border border-neutral-800 bg-neutral-900/50"
          >
            <span className="flex-1 truncate text-sm text-neutral-300">{p.name}</span>
            <span className="text-xs font-mono text-neutral-500 w-10 text-center">
              {p.strikes}/{MAX_STRIKES}
            </span>
            <button
              type="button"
              onClick={() => dispatch({ type: 'removeStrike', id: p.id })}
              disabled={p.strikes === 0}
              aria-label={`Tirar strike de ${p.name}`}
              className="w-7 h-7 rounded-md bg-neutral-800 text-neutral-400 hover:bg-neutral-700 disabled:opacity-30 disabled:cursor-not-allowed font-bold cursor-pointer"
            >
              −
            </button>
            {p.strikes >= MAX_STRIKES ? (
              <button
                type="button"
                onClick={() => setPendingKill(p.id)}
                aria-label={`Eliminar ${p.name}`}
                className="w-7 h-7 rounded-md bg-red-900/40 text-red-300 hover:bg-red-900/60 font-bold cursor-pointer"
              >
                ☠️
              </button>
            ) : (
              <button
                type="button"
                onClick={() => {
                  dispatch({ type: 'addStrike', id: p.id })
                  if (p.strikes + 1 >= MAX_STRIKES) setPendingKill(p.id)
                }}
                aria-label={`Dar strike em ${p.name}`}
                className="w-7 h-7 rounded-md bg-neutral-800 text-neutral-400 hover:bg-neutral-700 font-bold cursor-pointer"
              >
                +
              </button>
            )}
          </div>
        ))}

        {target && (
          <div className="rounded-xl border border-red-800 bg-red-950/30 px-4 py-3 space-y-3 text-center">
            <p className="text-sm text-neutral-200">
              Eliminar <span className="font-bold">{target.name}</span> com 3 strikes?
            </p>
            <div className="flex gap-3">
              <button
                type="button"
                onClick={() => {
                  dispatch({ type: 'setAlive', id: target.id, alive: false })
                  setPendingKill(null)
                }}
                className="flex-1 py-2.5 rounded-xl text-sm font-bold bg-red-700 text-white hover:bg-red-600 cursor-pointer"
              >
                Eliminar
              </button>
              <button
                type="button"
                onClick={() => setPendingKill(null)}
                className="flex-1 py-2.5 rounded-xl text-sm font-bold border border-neutral-700 text-neutral-300 hover:bg-neutral-800 cursor-pointer"
              >
                Manter
              </button>
            </div>
          </div>
        )}
      </div>
    </details>
  )
}
