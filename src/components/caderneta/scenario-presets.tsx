'use client'

import { useState, type FormEvent } from 'react'
import { useSavedScenarios } from '@/hooks/use-saved-scenarios'
import {
  PRESETS,
  SAVED_NAME_MAX,
  describeCounts,
  summarize,
  type SavedScenario,
  type ScenarioPreset,
} from '@/lib/caderneta/presets'
import { countCards, emptyCounts, type Balance, type ScenarioCounts } from '@/lib/scenario'

interface ScenarioPresetsProps {
  counts: ScenarioCounts
  onApply: (counts: ScenarioCounts) => void
}

const BALANCE_LABEL: Record<Balance, string> = {
  wolves: '🐺 Vantagem dos Lobos',
  balanced: '⚖️ Equilibrado',
  village: '🌿 Vantagem da Aldeia',
}

function Row({
  name,
  counts,
  onApply,
  onRemove,
}: {
  name: string
  counts: ScenarioCounts
  onApply: () => void
  onRemove?: () => void
}) {
  const { cards, balance } = summarize(counts)
  return (
    <li className="flex items-stretch gap-2">
      <button
        type="button"
        onClick={onApply}
        className="flex-1 min-w-0 text-left rounded-xl border border-neutral-800 bg-neutral-900/50 px-4 py-3 hover:border-neutral-600 cursor-pointer transition-all"
      >
        <span className="flex items-baseline justify-between gap-2">
          <span className="text-sm font-medium text-neutral-200 truncate">{name}</span>
          <span className="shrink-0 text-[11px] text-neutral-500">
            {cards} cartas · {BALANCE_LABEL[balance]}
          </span>
        </span>
        <span className="block mt-1 text-[11px] leading-relaxed text-neutral-500">{describeCounts(counts)}</span>
      </button>
      {onRemove && (
        <button
          type="button"
          onClick={onRemove}
          aria-label={`Apagar ${name}`}
          className="shrink-0 px-3 rounded-xl border border-neutral-800 text-neutral-500 hover:text-red-400 hover:border-red-900 cursor-pointer transition-all"
        >
          🗑
        </button>
      )}
    </li>
  )
}

export function ScenarioPresets({ counts, onApply }: ScenarioPresetsProps) {
  const { list, save, remove } = useSavedScenarios()
  const [name, setName] = useState('')
  const [error, setError] = useState('')

  const apply = (c: ScenarioCounts) => onApply({ ...emptyCounts(), ...c })

  function handleSave(e: FormEvent) {
    e.preventDefault()
    const err = save(name, counts)
    setError(err ?? '')
    if (!err) setName('')
  }

  return (
    <details open className="rounded-xl border border-neutral-800 bg-neutral-900/30">
      <summary className="px-4 py-3 text-sm font-medium text-neutral-300 cursor-pointer select-none">
        📋 Cenários prontos e salvos
      </summary>
      <div className="px-3 pb-3 space-y-3">
        <p className="text-[11px] text-neutral-500 leading-relaxed">
          Toque para preencher as cartas. Se o total não bater com os jogadores, ajuste (o contador mostra a
          diferença).
        </p>

        <ul className="space-y-2">
          {PRESETS.map((p: ScenarioPreset) => (
            <Row key={p.id} name={p.name} counts={p.counts} onApply={() => apply(p.counts)} />
          ))}
        </ul>

        {list.length > 0 && (
          <div className="space-y-2">
            <h3 className="text-neutral-400 text-[10px] uppercase tracking-widest">Salvos por você</h3>
            <ul className="space-y-2">
              {list.map((s: SavedScenario) => (
                <Row
                  key={s.name}
                  name={s.name}
                  counts={s.counts}
                  onApply={() => apply(s.counts)}
                  onRemove={() => remove(s.name)}
                />
              ))}
            </ul>
          </div>
        )}

        <form onSubmit={handleSave} className="space-y-1.5">
          <div className="flex gap-2">
            <input
              type="text"
              value={name}
              maxLength={SAVED_NAME_MAX}
              autoComplete="off"
              onChange={(e) => {
                setName(e.target.value)
                setError('')
              }}
              placeholder="Nome para salvar o cenário atual"
              className="flex-1 min-w-0 px-3 py-2.5 rounded-xl text-xs bg-neutral-900 border border-neutral-800 text-neutral-200 placeholder-neutral-600 focus:outline-none focus:border-red-800"
            />
            <button
              type="submit"
              disabled={countCards(counts) === 0}
              className="px-4 rounded-xl text-xs font-bold bg-neutral-800 text-neutral-200 hover:bg-neutral-700 disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer transition-all"
            >
              Salvar
            </button>
          </div>
          {error && <p className="text-red-500 text-[11px]">{error}</p>}
          <p className="text-neutral-600 text-[10px]">Os salvos ficam só neste aparelho/navegador.</p>
        </form>
      </div>
    </details>
  )
}
