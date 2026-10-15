'use client'

import { useState, type Dispatch } from 'react'
import { aliveCounts, type Action, type CadernetaState } from '@/lib/caderneta/state'
import { DayTools } from './day-tools'
import { NightStepsList } from './night-steps-list'
import { PlayersList } from './players-list'

interface PlayPanelProps {
  state: CadernetaState
  dispatch: Dispatch<Action>
}

export function PlayPanel({ state, dispatch }: PlayPanelProps) {
  const { alive, wolves, others } = aliveCounts(state)
  const [confirm, setConfirm] = useState<'end' | 'cancel' | null>(null)

  return (
    <div className="space-y-6">
      <header className="text-center space-y-1">
        <h1 className="font-display text-5xl tracking-widest text-red-600">
          {state.view === 'night' ? `NOITE ${state.turn}` : `DIA ${state.turn}`}
        </h1>
        <p className="text-neutral-500 text-xs">
          {alive} vivos · 🐺 {wolves} × {others} demais
        </p>
      </header>

      {state.view === 'night' ? (
        <NightStepsList key={state.turn} state={state} dispatch={dispatch} />
      ) : (
        <DayTools state={state} dispatch={dispatch} />
      )}

      <PlayersList state={state} dispatch={dispatch} />

      <footer className="space-y-2 pt-2 border-t border-neutral-800">
        {confirm ? (
          <div className="rounded-xl border border-neutral-700 px-4 py-3 space-y-3 text-center">
            <p className="text-sm text-neutral-300">
              {confirm === 'end'
                ? 'Encerrar a partida e revelar os papéis?'
                : 'Cancelar a partida e voltar à montagem? O sorteio atual se perde.'}
            </p>
            <div className="flex gap-3">
              <button
                type="button"
                onClick={() => {
                  dispatch({ type: confirm === 'end' ? 'end' : 'cancel' })
                  setConfirm(null)
                }}
                className="flex-1 py-2.5 rounded-xl text-sm font-bold bg-red-700 text-white hover:bg-red-600 cursor-pointer"
              >
                Confirmar
              </button>
              <button
                type="button"
                onClick={() => setConfirm(null)}
                className="flex-1 py-2.5 rounded-xl text-sm font-bold border border-neutral-700 text-neutral-300 hover:bg-neutral-800 cursor-pointer"
              >
                Voltar
              </button>
            </div>
          </div>
        ) : (
          <div className="flex gap-3">
            <button
              type="button"
              onClick={() => setConfirm('end')}
              className="flex-1 py-2.5 rounded-xl text-xs font-bold border border-neutral-800 text-neutral-400 hover:text-neutral-200 cursor-pointer"
            >
              Encerrar partida
            </button>
            <button
              type="button"
              onClick={() => setConfirm('cancel')}
              className="flex-1 py-2.5 rounded-xl text-xs font-bold border border-neutral-800 text-neutral-500 hover:text-neutral-300 cursor-pointer"
            >
              Cancelar partida
            </button>
          </div>
        )}
      </footer>
    </div>
  )
}
