'use client'

import { useState, type Dispatch } from 'react'
import { hoodlumDone } from '@/lib/caderneta/winner'
import { aliveCounts, bombTargets, pendingBombers, winnerOf, type Action, type CadernetaState } from '@/lib/caderneta/state'
import { DayTools } from './day-tools'
import { NightStepsList } from './night-steps-list'
import { PlayersList } from './players-list'
import { WinnerBanner } from './winner-banner'

interface PlayPanelProps {
  state: CadernetaState
  dispatch: Dispatch<Action>
}

export function PlayPanel({ state, dispatch }: PlayPanelProps) {
  const { alive, wolves, others } = aliveCounts(state)
  const winner = winnerOf(state)
  const hoodlumId = hoodlumDone(state.players)?.id
  const hoodlum = state.players.find((p) => p.id === hoodlumId)
  const bombers = pendingBombers(state)
  const marked = state.players.filter((p) => p.alive && p.tags.includes('marked'))
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

      {winner && <WinnerBanner winner={winner} onEnd={() => dispatch({ type: 'end' })} />}

      {bombers.map((b) => {
        const victims = bombTargets(state.players, b.id)
          .map((id) => state.players.find((p) => p.id === id)?.name)
          .filter(Boolean)
          .join(' e ')
        return (
          <div key={b.id} className="rounded-xl border border-orange-800/60 bg-orange-950/20 px-4 py-3 space-y-2 text-xs text-orange-200">
            <p>
              💣 <b>{b.name}</b> (Mad Bomber) morreu.{' '}
              {victims ? <>Leva junto: <b>{victims}</b>.</> : 'Não há ninguém vivo ao lado.'}
            </p>
            <div className="flex gap-2">
              {victims && (
                <button
                  type="button"
                  onClick={() => dispatch({ type: 'bomb', id: b.id })}
                  className="flex-1 py-2 rounded-lg font-bold bg-orange-700 text-white hover:bg-orange-600 cursor-pointer"
                >
                  💥 Eliminar os vizinhos
                </button>
              )}
              <button
                type="button"
                onClick={() => dispatch({ type: 'bombSkip', id: b.id })}
                className="flex-1 py-2 rounded-lg font-bold border border-neutral-700 text-neutral-300 hover:bg-neutral-800 cursor-pointer"
              >
                Já resolvi
              </button>
            </div>
          </div>
        )
      })}

      {hoodlum && (
        <p className="rounded-xl border border-neutral-600 bg-neutral-900 px-4 py-3 text-xs text-neutral-300">
          🎯 <b>{hoodlum.name}</b> (Bandido) cumpriu o objetivo: os 2 alvos morreram e ele está vivo. Você decide se
          fala agora ou não; o jogo continua.
        </p>
      )}

      {state.view === 'day' && marked.length > 0 && (
        <p className="rounded-xl border border-fuchsia-800/50 bg-fuchsia-950/20 px-4 py-3 text-xs text-fuchsia-300">
          🧛 Marcado pelos vampiros: <b>{marked.map((p) => p.name).join(', ')}</b>. Se for indicado hoje, morre na hora.
        </p>
      )}

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
