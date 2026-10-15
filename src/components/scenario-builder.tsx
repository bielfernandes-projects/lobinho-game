'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { DRUNK_ALLOWED } from '@/lib/cards'
import { ScenarioCardPicker } from '@/components/scenario-card-picker'
import { useScenarioCounts } from '@/hooks/use-scenario-counts'
import { isValidScenario, rolesFromCounts } from '@/lib/scenario'
import type { RevealMode } from '@/lib/reveal'

interface ScenarioBuilderProps {
  roomId: string
  playerCount: number
}

export function ScenarioBuilder({ roomId, playerCount }: ScenarioBuilderProps) {
  const [counts, setCounts] = useScenarioCounts()
  const [revealMode, setRevealMode] = useState<RevealMode>('team')
  const [drunkHidden, setDrunkHidden] = useState('random')
  const [ghostVariant, setGhostVariant] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const supabase = createClient()

  const isValid = isValidScenario(counts, playerCount)

  async function handleStart() {
    if (!isValid) return
    setBusy(true)
    setError('')

    const roles = rolesFromCounts(counts)

    const hiddenRole =
      (counts.drunk ?? 0) > 0
        ? drunkHidden === 'random'
          ? DRUNK_ALLOWED[Math.floor(Math.random() * DRUNK_ALLOWED.length)]
          : drunkHidden
        : null

    const { error: revealError } = await supabase
      .from('rooms')
      .update({
        reveal_mode: revealMode,
        drunk_hidden_role: hiddenRole,
        ghost_enabled: ghostVariant && (counts.ghost ?? 0) === 0,
      })
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
            { value: 'team' as const, label: '👥 Apenas Time Vila', desc: 'Mostra se a vítima era da Vila ou não.' },
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

      <label className="flex items-start gap-3 rounded-xl border border-neutral-800 bg-neutral-900/60 px-4 py-3 cursor-pointer">
        <input
          type="checkbox"
          checked={ghostVariant && (counts.ghost ?? 0) === 0}
          disabled={(counts.ghost ?? 0) > 0}
          onChange={(e) => setGhostVariant(e.target.checked)}
          className="mt-0.5 accent-red-600 cursor-pointer"
        />
        <div className="flex flex-col">
          <span className="text-neutral-300 text-sm font-medium">👻 Variante Fantasma</span>
          <span className="text-neutral-600 text-[10px] leading-tight">
            {(counts.ghost ?? 0) > 0
              ? 'A carta do Fantasma está no cenário (ela tem prioridade).'
              : 'O primeiro jogador a morrer vira Fantasma: mantém o time e escreve uma letra por dia.'}
          </span>
        </div>
      </label>

      <ScenarioCardPicker
        playerCount={playerCount}
        counts={counts}
        onChange={setCounts}
        drunkHidden={drunkHidden}
        onDrunkHiddenChange={setDrunkHidden}
      />

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
    </div>
  )
}
