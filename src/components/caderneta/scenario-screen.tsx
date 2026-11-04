'use client'

import { CARD_CATALOG, ROLE_STYLE, ROLE_TRANSLATION } from '@/lib/cards'
import type { ScenarioCounts } from '@/lib/scenario'

interface ScenarioScreenProps {
  counts: ScenarioCounts
  onConfirm: () => void
  onBack: () => void
}

// Aldeia → Lobos → Independentes, like the online scenario screen.
const TEAM_ORDER = { village: 0, wolf: 1, independent: 2 } as const

export function ScenarioScreen({ counts, onConfirm, onBack }: ScenarioScreenProps) {
  const entries = CARD_CATALOG.filter((c) => (counts[c.id] ?? 0) > 0).sort(
    (a, b) => TEAM_ORDER[a.team] - TEAM_ORDER[b.team] || b.points - a.points,
  )

  return (
    <div className="space-y-6">
      <header className="text-center space-y-1">
        <p className="text-neutral-500 text-[10px] uppercase tracking-widest">Antes de começar</p>
        <h1 className="font-display text-4xl tracking-widest text-red-600">CENÁRIO DO JOGO</h1>
        <p className="text-neutral-400 text-xs">
          Explique cada papel para a mesa antes de distribuir as cartas.
        </p>
      </header>

      <ul className="space-y-3">
        {entries.map((card) => (
          <li
            key={card.id}
            className={`rounded-2xl border-2 p-4 ${ROLE_STYLE[card.id] ?? 'bg-neutral-100 text-neutral-700 border-neutral-300'}`}
          >
            <h2 className="font-bold text-base">
              {card.name}
              {ROLE_TRANSLATION[card.id] && ROLE_TRANSLATION[card.id] !== card.name && (
                <span className="text-xs opacity-70 ml-1">({ROLE_TRANSLATION[card.id]})</span>
              )}
              <span className="text-sm opacity-80 ml-1">({counts[card.id]})</span>
            </h2>
            <p className="text-xs opacity-90 leading-relaxed mt-1">{card.description}</p>
          </li>
        ))}
      </ul>

      <div className="space-y-2">
        <button
          type="button"
          onClick={onConfirm}
          className="w-full py-4 rounded-2xl font-bold text-lg tracking-wider bg-red-700 text-white hover:bg-red-600 active:bg-red-800 shadow-lg shadow-red-900/40 transition-all duration-200 cursor-pointer"
        >
          Sortear e entregar cartas
        </button>
        <button
          type="button"
          onClick={onBack}
          className="w-full py-3 rounded-xl text-sm font-medium border border-neutral-800 text-neutral-400 hover:bg-neutral-800 cursor-pointer transition-all"
        >
          ↩ Voltar para a montagem
        </button>
      </div>
    </div>
  )
}
