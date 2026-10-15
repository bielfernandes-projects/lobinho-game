'use client'

import { useState, type Dispatch, type FormEvent } from 'react'
import { CARD_CATALOG } from '@/lib/cards'
import { ScenarioCardPicker } from '@/components/scenario-card-picker'
import { useScenarioCounts } from '@/hooks/use-scenario-counts'
import { isValidScenario } from '@/lib/scenario'
import {
  NAME_MAX,
  addName,
  drawRoles,
  pickDrunkRole,
  type Action,
  type CadernetaState,
} from '@/lib/caderneta/state'

interface SetupScreenProps {
  state: CadernetaState
  dispatch: Dispatch<Action>
}

export function SetupScreen({ state, dispatch }: SetupScreenProps) {
  const [counts, setCounts] = useScenarioCounts()
  const [drunkHidden, setDrunkHidden] = useState('random')
  const [nameInput, setNameInput] = useState('')
  const [error, setError] = useState('')

  const playerCount = state.names.length
  const valid = isValidScenario(counts, playerCount)
  const wolfCards = CARD_CATALOG.filter((c) => c.team === 'wolf').reduce(
    (sum, c) => sum + (counts[c.id] ?? 0),
    0,
  )
  const warnings: string[] = []
  if (wolfCards === 0) warnings.push('Sem lobos no cenário.')
  if ((counts.seer ?? 0) === 0) warnings.push('Sem Vidente no cenário.')

  function handleAdd(e: FormEvent) {
    e.preventDefault()
    const result = addName(state.names, nameInput)
    if (result.error) {
      setError(result.error)
      return
    }
    setError('')
    setNameInput('')
    dispatch({ type: 'setNames', names: result.names })
  }

  function handleRemove(name: string) {
    dispatch({ type: 'setNames', names: state.names.filter((n) => n !== name) })
  }

  function handleDeal() {
    if (!valid) return
    dispatch({
      type: 'deal',
      roles: drawRoles(counts),
      drunkHiddenRole: pickDrunkRole((counts.drunk ?? 0) > 0, drunkHidden),
    })
  }

  return (
    <div className="space-y-6">
      <header className="text-center space-y-1">
        <h1 className="font-display text-4xl tracking-widest text-red-600">CADERNETA DO MESTRE</h1>
        <p className="text-neutral-500 text-xs">
          Digite os jogadores, escolha as cartas e passe o celular de mão em mão.
        </p>
      </header>

      <section className="space-y-3">
        <h2 className="text-neutral-400 text-xs uppercase tracking-widest">Jogadores ({playerCount})</h2>
        <form onSubmit={handleAdd} className="flex gap-2">
          <input
            type="text"
            value={nameInput}
            maxLength={NAME_MAX}
            onChange={(e) => {
              setNameInput(e.target.value)
              setError('')
            }}
            placeholder="Nome do jogador"
            className="flex-1 px-4 py-3 rounded-xl text-sm bg-neutral-900 border border-neutral-800 text-neutral-200 placeholder-neutral-600 focus:outline-none focus:ring-2 focus:ring-red-700 focus:border-red-800 transition-all"
          />
          <button
            type="submit"
            className="px-4 rounded-xl font-bold text-sm bg-primary hover:bg-primary-hover active:bg-primary-active text-white cursor-pointer transition-all"
          >
            Adicionar
          </button>
        </form>
        {error && <p className="text-red-500 text-xs">{error}</p>}
        {state.names.length > 0 && (
          <ul className="flex flex-wrap gap-2">
            {state.names.map((name) => (
              <li
                key={name}
                className="flex items-center gap-2 pl-3 pr-1 py-1 rounded-full border border-neutral-800 bg-neutral-900/60 text-sm text-neutral-300"
              >
                {name}
                <button
                  type="button"
                  onClick={() => handleRemove(name)}
                  aria-label={`Remover ${name}`}
                  className="w-6 h-6 rounded-full text-neutral-500 hover:text-neutral-200 hover:bg-neutral-800 cursor-pointer"
                >
                  ×
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="space-y-3">
        <h2 className="text-neutral-400 text-xs uppercase tracking-widest">Cenário</h2>
        <ScenarioCardPicker
          playerCount={playerCount}
          counts={counts}
          onChange={setCounts}
          drunkHidden={drunkHidden}
          onDrunkHiddenChange={setDrunkHidden}
        />
      </section>

      {warnings.length > 0 && (
        <p className="text-amber-500 text-xs text-center">{warnings.join(' ')} Dá para jogar assim mesmo.</p>
      )}

      <button
        type="button"
        onClick={handleDeal}
        disabled={!valid}
        className="w-full py-4 rounded-2xl font-bold text-lg tracking-wider bg-red-700 text-white hover:bg-red-600 active:bg-red-800 disabled:opacity-40 disabled:cursor-not-allowed shadow-lg shadow-red-900/40 transition-all duration-200 cursor-pointer"
      >
        Sortear e entregar cartas
      </button>
    </div>
  )
}
