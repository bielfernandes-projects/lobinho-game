'use client'

import { useState, type Dispatch } from 'react'
import { DRUNK_ROLE_OPTIONS, ROLE_TRANSLATION } from '@/lib/cards'
import { nextStepId, nightSteps, type Action, type CadernetaState, type Tag } from '@/lib/caderneta/state'

interface NightStepsListProps {
  state: CadernetaState
  dispatch: Dispatch<Action>
}

// First-night steps where a role links players. The master taps who was chosen and the app
// reuses the existing tag (the soulmate tag feeds the win check).
// ponytail: Dire Wolf and Virginia Wolf share the 'companion' tag; both in one game show the same picks.
const CONNECTIONS: Record<string, { tag: Tag; max: number; hint: string }> = {
  cupid: { tag: 'soulmate', max: 2, hint: 'Anote os 2 apaixonados que o Cupido escolheu:' },
  dire_wolf: { tag: 'companion', max: 1, hint: 'Anote o companheiro que o Lobo Aproveitador escolheu:' },
  virginia_wolf: { tag: 'companion', max: 1, hint: 'Anote o par que a Virginia Wolf escolheu:' },
}

export function NightStepsList({ state, dispatch }: NightStepsListProps) {
  const [confirming, setConfirming] = useState(false)
  const [drunkChoice, setDrunkChoice] = useState<string | null>(null)
  const steps = nightSteps(state)
  const next = nextStepId(state)
  const pending = steps.filter((s) => !state.doneSteps.includes(s.id)).length

  function handleDawn() {
    if (pending > 0 && !confirming) {
      setConfirming(true)
      return
    }
    setConfirming(false)
    dispatch({ type: 'toDay' })
  }

  function revealDrunk() {
    const hidden = drunkChoice ?? state.drunkHiddenRole
    if (!hidden) return
    for (const p of state.players) {
      if (p.role === 'drunk') dispatch({ type: 'setRole', id: p.id, role: hidden })
    }
    dispatch({ type: 'toggleStep', step: 'drunk' })
  }

  return (
    <section className="space-y-3">
      <h2 className="text-neutral-400 text-xs uppercase tracking-widest">Ordem para acordar</h2>
      {steps.length === 0 ? (
        <p className="text-neutral-600 text-sm text-center py-3">Ninguém acorda nesta noite.</p>
      ) : (
        <ol className="space-y-2">
          {steps.map((step) => {
            const done = state.doneSteps.includes(step.id)
            const holders = state.players.filter((p) => step.roles.includes(p.role))
            const isNext = step.id === next
            return (
              <li
                key={step.id}
                className={`rounded-xl border px-4 py-3 space-y-2 ${
                  isNext
                    ? 'border-red-700 bg-red-950/20 animate-pulse'
                    : 'border-neutral-800 bg-neutral-900/50'
                } ${done ? 'opacity-50' : ''}`}
              >
                <div className="flex items-center gap-3">
                  <span
                    className={`flex-1 text-sm font-medium ${
                      done ? 'line-through text-neutral-500' : 'text-neutral-200'
                    }`}
                  >
                    {step.label}
                  </span>
                  <button
                    type="button"
                    onClick={() => dispatch({ type: 'toggleStep', step: step.id })}
                    className="px-3 py-1.5 rounded-lg text-xs font-bold bg-neutral-900 border border-neutral-800 text-green-400 hover:bg-green-900/30 cursor-pointer transition-all"
                  >
                    {done ? '↺ Desfazer' : '✓ Feito'}
                  </button>
                </div>
                <p className="text-[11px] text-neutral-500">
                  {holders.map((p) => (p.alive ? p.name : `${p.name} †`)).join(', ')}
                </p>
                {CONNECTIONS[step.id] && (() => {
                  const { tag, max, hint } = CONNECTIONS[step.id]
                  const picked = state.players.filter((p) => p.tags.includes(tag)).length
                  return (
                    <div className="space-y-1.5">
                      <p className="text-[11px] text-amber-400">
                        💡 {hint} ({picked}/{max})
                      </p>
                      <div className="flex flex-wrap gap-1.5">
                        {state.players.map((p) => {
                          const on = p.tags.includes(tag)
                          return (
                            <button
                              key={p.id}
                              type="button"
                              onClick={() => dispatch({ type: 'toggleTag', id: p.id, tag })}
                              disabled={!on && picked >= max}
                              aria-pressed={on}
                              className={`px-2.5 py-1 rounded-full border text-[11px] cursor-pointer transition-all disabled:opacity-30 disabled:cursor-not-allowed ${
                                on
                                  ? 'bg-red-900/30 border-red-800/60 text-red-300'
                                  : 'bg-neutral-900 border-neutral-800 text-neutral-400 hover:text-neutral-200'
                              }`}
                            >
                              {p.name}
                            </button>
                          )
                        })}
                      </div>
                    </div>
                  )
                })()}
                {step.id === 'drunk' && state.drunkHiddenRole && (
                  <div className="flex items-center gap-2">
                    <label className="flex-1 text-[11px] text-amber-500 space-y-1">
                      Novo papel
                      <select
                        value={drunkChoice ?? state.drunkHiddenRole}
                        onChange={(e) => setDrunkChoice(e.target.value)}
                        className="block w-full bg-neutral-900 border border-neutral-800 rounded-lg px-2 py-1.5 text-xs text-neutral-300"
                      >
                        {DRUNK_ROLE_OPTIONS.map((c) => (
                          <option key={c.id} value={c.id}>{ROLE_TRANSLATION[c.id] ?? c.name}</option>
                        ))}
                      </select>
                    </label>
                    <button
                      type="button"
                      onClick={revealDrunk}
                      className="px-3 py-1.5 rounded-lg text-xs font-bold bg-amber-950/30 border border-amber-900/50 text-amber-400 cursor-pointer"
                    >
                      Revelar e trocar papel
                    </button>
                  </div>
                )}
              </li>
            )
          })}
        </ol>
      )}

      <button
        type="button"
        onClick={handleDawn}
        className="w-full py-3.5 rounded-2xl font-bold tracking-wider bg-primary hover:bg-primary-hover active:bg-primary-active text-white shadow-lg shadow-red-900/30 cursor-pointer transition-all"
      >
        {confirming ? `Faltam ${pending} passo(s). Amanhecer mesmo?` : '☀️ Amanhecer'}
      </button>
    </section>
  )
}
