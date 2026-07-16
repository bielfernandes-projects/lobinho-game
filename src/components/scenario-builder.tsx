'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { CARD_CATALOG, type CardDefinition } from '@/lib/cards'
import { RoleInfoModal } from '@/components/role-info-modal'
import type { RevealMode } from '@/lib/reveal'

interface ScenarioBuilderProps {
  roomId: string
  playerCount: number
}

const STORAGE_KEY = 'lobinho_last_scenario'

function getInitialCounts(): Record<string, number> {
  const zeros = Object.fromEntries(CARD_CATALOG.map((c) => [c.id, 0]))
  if (typeof window === 'undefined') return zeros
  try {
    const saved = localStorage.getItem(STORAGE_KEY)
    if (saved) {
      const parsed = JSON.parse(saved)
      return { ...zeros, ...parsed }
    }
  } catch {}
  return zeros
}

export function ScenarioBuilder({ roomId, playerCount }: ScenarioBuilderProps) {
  const [counts, setCounts] = useState<Record<string, number>>(getInitialCounts)
  const [revealMode, setRevealMode] = useState<RevealMode>('team')
  const [modalCard, setModalCard] = useState<CardDefinition | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const supabase = createClient()

  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(counts))
  }, [counts])

  const totalCards = Object.values(counts).reduce((a, b) => a + b, 0)
  const totalPoints = CARD_CATALOG.reduce(
    (sum, c) => sum + c.points * (counts[c.id] ?? 0),
    0
  )
  const isValid = totalCards === playerCount && playerCount >= 6 && playerCount <= 77

  function inc(id: string) {
    setCounts((prev) => ({ ...prev, [id]: (prev[id] ?? 0) + 1 }))
  }

  function dec(id: string) {
    setCounts((prev) => ({
      ...prev,
      [id]: Math.max(0, (prev[id] ?? 0) - 1),
    }))
  }

  function getThermometer(): { label: string; color: string } {
    if (totalPoints < -3) return { label: '🐺 Vantagem dos Lobos', color: 'text-red-400' }
    if (totalPoints > 3) return { label: '🌿 Vantagem da Aldeia', color: 'text-emerald-400' }
    return { label: '⚖️ Equilibrado', color: 'text-yellow-400' }
  }

  const thermo = getThermometer()
  const maxBar = playerCount * Math.max(...CARD_CATALOG.map((c) => Math.abs(c.points)))
  const barPercent = maxBar > 0 ? Math.min(100, Math.abs(totalPoints) / (maxBar / 50)) : 0

  async function handleStart() {
    if (!isValid) return
    setBusy(true)
    setError('')

    const roles: string[] = []
    for (const card of CARD_CATALOG) {
      for (let i = 0; i < (counts[card.id] ?? 0); i++) {
        roles.push(card.id)
      }
    }

    const { error: revealError } = await supabase
      .from('rooms')
      .update({ reveal_mode: revealMode })
      .eq('id', roomId)
    if (revealError) {
      setError(revealError.message)
      setBusy(false)
      return
    }

    const { error: e } = await supabase.rpc('start_game', {
      p_room_id: roomId,
      p_roles: roles,
    })
    if (e) {
      setError(e.message)
      setBusy(false)
    }
  }

  return (
    <div className="w-full max-w-sm mx-auto mt-6 space-y-4">
      {/* Header */}
      <div className="flex items-center gap-2">
        <h2 className="text-neutral-400 text-xs uppercase tracking-widest">
          Construir Cenário
        </h2>
        <span className="flex-1 h-px bg-neutral-800" />
      </div>

      {/* Configurações da Partida */}
      <div className="rounded-xl border border-neutral-800 bg-neutral-900/60 px-4 py-3 space-y-2">
        <p className="text-neutral-500 text-[10px] uppercase tracking-widest font-bold">
          Configurações da Partida
        </p>
        <div className="space-y-1.5">
          {[
            { value: 'total' as const, label: '🃏 Revelação Total', desc: 'Todos os papéis são revelados exatamente como são.' },
            { value: 'team' as const, label: '👥 Apenas o Time', desc: 'Mostra apenas Time da Vila, Time dos Lobos ou Facção Independente.' },
            { value: 'hidden' as const, label: '❓ Identidade Oculta', desc: 'Nenhuma informação sobre a identidade é revelada.' },
          ].map((opt) => (
            <label
              key={opt.value}
              className={`flex items-start gap-3 px-3 py-2 rounded-lg cursor-pointer transition-colors ${
                revealMode === opt.value
                  ? 'bg-red-900/20 border border-red-800/40'
                  : 'bg-neutral-900/40 border border-transparent hover:bg-neutral-800/40'
              }`}
            >
              <input
                type="radio"
                name="revealMode"
                value={opt.value}
                checked={revealMode === opt.value}
                onChange={() => setRevealMode(opt.value)}
                className="mt-0.5 accent-red-600 cursor-pointer"
              />
              <div className="flex flex-col">
                <span className="text-neutral-300 text-sm font-medium">{opt.label}</span>
                <span className="text-neutral-600 text-[10px] leading-tight">{opt.desc}</span>
              </div>
            </label>
          ))}
        </div>
      </div>

      {/* Termômetro */}
      <div className="rounded-xl border border-neutral-800 bg-neutral-900/60 px-4 py-3 space-y-1.5">
        <p className={`text-xs font-bold tracking-wider uppercase ${thermo.color}`}>
          {thermo.label}
        </p>
        <div className="flex items-center gap-2">
          <div className="flex-1 h-1.5 rounded-full bg-neutral-800 overflow-hidden">
            <div
              className={`h-full rounded-full transition-all duration-300 ${
                totalPoints < -3
                  ? 'bg-red-500'
                  : totalPoints > 3
                    ? 'bg-emerald-500'
                    : 'bg-yellow-500'
              }`}
              style={{
                width: `${barPercent}%`,
                marginLeft: totalPoints < 0 ? 'auto' : undefined,
                float: totalPoints < 0 ? 'right' : 'left',
              }}
            />
          </div>
          <span className="text-neutral-500 text-xs font-mono min-w-[4ch] text-right">
            {totalPoints}
          </span>
        </div>
      </div>

      {/* Resetar cenário */}
      <button
        type="button"
        onClick={() => setCounts(Object.fromEntries(CARD_CATALOG.map((c) => [c.id, 0])))}
        className="w-full rounded-xl border border-neutral-800 bg-neutral-900/60 px-4 py-3 text-sm text-neutral-400 hover:text-neutral-200 hover:border-neutral-700 transition-all cursor-pointer text-center"
      >
        ↺ Resetar Cenário
      </button>

      {/* Lista de cartas agrupada por time */}
      {([
        { key: 'village', label: '🌿 Time da Vila', color: 'text-emerald-500', border: 'border-emerald-800/30' },
        { key: 'wolf', label: '🐺 Time dos Lobos', color: 'text-red-500', border: 'border-red-800/30' },
        { key: 'independent', label: '⚖️ Independentes', color: 'text-purple-500', border: 'border-purple-800/30' },
      ] as const).map((group) => {
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
                    {/* Nome + pontos */}
                    <span className="flex-1 text-sm font-medium text-neutral-300 truncate flex items-center gap-2">
                      {card.name}
                      <span className={`text-xs font-mono ${
                        card.points > 0 ? 'text-emerald-500'
                          : card.points < 0 ? 'text-red-500'
                          : 'text-yellow-500'
                      }`}>
                        [{card.points > 0 ? '+' : ''}{card.points}]
                      </span>
                    </span>

                    <button
                      type="button"
                      onClick={() => setModalCard(card)}
                      className="text-neutral-600 hover:text-neutral-400 text-xs transition-colors cursor-pointer"
                    >
                      ⓘ
                    </button>

                    {/* Controles +/- */}
                    <div className="flex items-center gap-1.5">
                      <button
                        type="button"
                        onClick={() => dec(card.id)}
                        disabled={count === 0}
                        className="w-6 h-6 rounded-md bg-neutral-800 text-neutral-400 hover:bg-neutral-700 hover:text-neutral-200 disabled:opacity-30 disabled:cursor-not-allowed text-sm font-bold transition-all cursor-pointer flex items-center justify-center"
                      >
                        −
                      </button>
                      <span className="w-6 text-center text-sm font-mono text-neutral-200">
                        {count}
                      </span>
                      <button
                        type="button"
                        onClick={() => inc(card.id)}
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

      {/* Validação */}
      <div className="flex items-center justify-between px-1">
        <p
          className={`text-xs font-mono ${
            isValid ? 'text-emerald-500' : 'text-neutral-600'
          }`}
        >
          Cartas: {totalCards}/{playerCount} {isValid ? '✅' : ''}
        </p>
        {playerCount < 6 && (
          <p className="text-red-500 text-[10px]">Mínimo 6 jogadores</p>
        )}
        {playerCount > 77 && (
          <p className="text-red-500 text-[10px]">Máximo 77 jogadores</p>
        )}
      </div>

      {/* Botão Iniciar */}
      <button
        onClick={handleStart}
        disabled={!isValid || busy}
        className="w-full py-4 rounded-2xl font-bold text-lg tracking-wider bg-red-700 text-white hover:bg-red-600 active:bg-red-800 disabled:opacity-40 disabled:cursor-not-allowed shadow-lg shadow-red-900/40 transition-all duration-200 cursor-pointer disabled:animate-none"
      >
        {busy ? 'Iniciando...' : 'Iniciar Jogo'}
      </button>

      {error && (
        <p className="text-red-500 text-xs text-center">{error}</p>
      )}

      <RoleInfoModal open={modalCard !== null} onClose={() => setModalCard(null)} card={modalCard} />
    </div>
  )
}
