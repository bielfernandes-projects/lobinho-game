'use client'

import { useState, type Dispatch } from 'react'
import { VoteTimerPanel } from '@/components/vote-timer-panel'
import { MAX_STRIKES, type Action, type CadernetaState } from '@/lib/caderneta/state'

interface DayToolsProps {
  state: CadernetaState
  dispatch: Dispatch<Action>
}

export function DayTools({ state, dispatch }: DayToolsProps) {
  const [pendingKill, setPendingKill] = useState<string | null>(null)
  const alive = state.players.filter((p) => p.alive)
  const target = state.players.find((p) => p.id === pendingKill)

  return (
    <section className="space-y-4">
      <VoteTimerPanel />

      <div className="space-y-2">
        <h2 className="text-neutral-400 text-xs uppercase tracking-widest">Strikes</h2>
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
      </div>

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
