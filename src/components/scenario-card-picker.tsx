'use client'

import { useState } from 'react'
import { CARD_CATALOG, DRUNK_ALLOWED, type CardDefinition } from '@/lib/cards'
import { RoleInfoModal } from '@/components/role-info-modal'
import {
  MAX_PLAYERS,
  MIN_PLAYERS,
  balanceOf,
  countCards,
  emptyCounts,
  isValidScenario,
  totalPoints,
  type ScenarioCounts,
} from '@/lib/scenario'

interface ScenarioCardPickerProps {
  playerCount: number
  counts: ScenarioCounts
  onChange: (counts: ScenarioCounts) => void
  drunkHidden: string
  onDrunkHiddenChange: (value: string) => void
}

const BALANCE_VIEW = {
  wolves: { label: '🐺 Vantagem dos Lobos', text: 'text-red-400', bar: 'bg-red-500' },
  balanced: { label: '⚖️ Equilibrado', text: 'text-yellow-400', bar: 'bg-yellow-500' },
  village: { label: '🌿 Vantagem da Aldeia', text: 'text-emerald-400', bar: 'bg-emerald-500' },
} as const

const GROUPS = [
  { key: 'village', label: '🌿 Time da Vila', color: 'text-emerald-500' },
  { key: 'wolf', label: '🐺 Time dos Lobos', color: 'text-red-500' },
  { key: 'independent', label: '⚖️ Independentes', color: 'text-purple-500' },
] as const

export function ScenarioCardPicker({
  playerCount,
  counts,
  onChange,
  drunkHidden,
  onDrunkHiddenChange,
}: ScenarioCardPickerProps) {
  const [modalCard, setModalCard] = useState<CardDefinition | null>(null)

  const totalCards = countCards(counts)
  const points = totalPoints(counts)
  const isValid = isValidScenario(counts, playerCount)
  const view = BALANCE_VIEW[balanceOf(points)]
  const maxBar = playerCount * Math.max(...CARD_CATALOG.map((c) => Math.abs(c.points)))
  const barPercent = maxBar > 0 ? Math.min(100, Math.abs(points) / (maxBar / 50)) : 0

  function setCount(id: string, delta: number) {
    onChange({ ...counts, [id]: Math.max(0, (counts[id] ?? 0) + delta) })
  }

  return (
    <div className="space-y-4">
      {(counts.drunk ?? 0) > 0 && (
        <div className="rounded-xl border border-amber-900/40 bg-amber-950/10 px-4 py-3 space-y-2">
          <p className="text-amber-500 text-[10px] uppercase tracking-widest font-bold">
            🍺 Papel oculto do Bêbado (carta reserva)
          </p>
          <select
            value={drunkHidden}
            onChange={(e) => onDrunkHiddenChange(e.target.value)}
            className="w-full bg-neutral-900 border border-neutral-800 rounded-lg px-3 py-2 text-sm text-neutral-300"
          >
            <option value="random">🎲 Sortear</option>
            {CARD_CATALOG.filter((c) => DRUNK_ALLOWED.includes(c.id)).map((c) => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </select>
          <p className="text-neutral-600 text-[10px] leading-tight">
            Não conta como jogador. Ele vira esse papel na 3ª noite; a Vidente já vê esse papel antes.
          </p>
        </div>
      )}

      {/* Termômetro: fica fixo no topo enquanto a lista de cartas rola. */}
      <div className="sticky top-[env(safe-area-inset-top,0px)] z-10 bg-midnight pt-1 pb-2">
        <div className="rounded-xl border border-neutral-800 bg-neutral-900 px-4 py-3 space-y-1.5">
          <p className={`text-xs font-bold tracking-wider uppercase ${view.text}`}>{view.label}</p>
          <div className="flex items-center gap-2">
            <div className="flex-1 h-1.5 rounded-full bg-neutral-800 overflow-hidden flex">
              <div
                className={`h-full rounded-full transition-all duration-300 ${view.bar} ${points < 0 ? 'ml-auto' : ''}`}
                style={{ width: `${barPercent}%` }}
              />
            </div>
            <span className="text-neutral-500 text-xs font-mono min-w-[4ch] text-right">{points}</span>
          </div>
        </div>
      </div>

      <button
        type="button"
        onClick={() => onChange(emptyCounts())}
        className="w-full rounded-xl border border-neutral-800 bg-neutral-900/60 px-4 py-3 text-sm text-neutral-400 hover:text-neutral-200 hover:border-neutral-700 transition-all cursor-pointer text-center"
      >
        ↺ Resetar Cenário
      </button>

      {GROUPS.map((group) => {
        const cards = CARD_CATALOG.filter((c) => c.team === group.key)
        if (cards.length === 0) return null
        return (
          <div key={group.key}>
            <div className={`px-1 py-2 text-xs font-bold tracking-wider uppercase ${group.color}`}>
              {group.label}
            </div>
            <div className="space-y-2">
              {cards.map((card) => {
                const count = counts[card.id] ?? 0
                return (
                  <div
                    key={card.id}
                    className="flex items-center gap-3 px-4 py-2.5 rounded-xl border border-neutral-800 bg-neutral-900/50"
                  >
                    <span className="flex-1 text-sm font-medium text-neutral-300 truncate flex items-center gap-2">
                      {card.name}
                      <span
                        className={`text-xs font-mono ${
                          card.points > 0 ? 'text-emerald-500' : card.points < 0 ? 'text-red-500' : 'text-yellow-500'
                        }`}
                      >
                        [{card.points > 0 ? '+' : ''}{card.points}]
                      </span>
                    </span>

                    <button
                      type="button"
                      onClick={() => setModalCard(card)}
                      aria-label={`Sobre ${card.name}`}
                      className="text-neutral-600 hover:text-neutral-400 text-xs transition-colors cursor-pointer"
                    >
                      ⓘ
                    </button>

                    <div className="flex items-center gap-1.5">
                      <button
                        type="button"
                        onClick={() => setCount(card.id, -1)}
                        disabled={count === 0}
                        aria-label={`Menos ${card.name}`}
                        className="w-6 h-6 rounded-md bg-neutral-800 text-neutral-400 hover:bg-neutral-700 hover:text-neutral-200 disabled:opacity-30 disabled:cursor-not-allowed text-sm font-bold transition-all cursor-pointer flex items-center justify-center"
                      >
                        −
                      </button>
                      <span className="w-6 text-center text-sm font-mono text-neutral-200">{count}</span>
                      <button
                        type="button"
                        onClick={() => setCount(card.id, 1)}
                        aria-label={`Mais ${card.name}`}
                        className="w-6 h-6 rounded-md bg-neutral-800 text-neutral-400 hover:bg-neutral-700 hover:text-neutral-200 text-sm font-bold transition-all cursor-pointer flex items-center justify-center"
                      >
                        +
                      </button>
                    </div>
                  </div>
                )
              })}
            </div>
          </div>
        )
      })}

      <div className="flex items-center justify-between px-1">
        <p className={`text-xs font-mono ${isValid ? 'text-emerald-500' : 'text-neutral-600'}`}>
          Cartas: {totalCards}/{playerCount} {isValid ? '✅' : ''}
        </p>
        {playerCount < MIN_PLAYERS && <p className="text-red-500 text-[10px]">Mínimo {MIN_PLAYERS} jogadores</p>}
        {playerCount > MAX_PLAYERS && <p className="text-red-500 text-[10px]">Máximo {MAX_PLAYERS} jogadores</p>}
      </div>

      <RoleInfoModal open={modalCard !== null} onClose={() => setModalCard(null)} card={modalCard} />
    </div>
  )
}
