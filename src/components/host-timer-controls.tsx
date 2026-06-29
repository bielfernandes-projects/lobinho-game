'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'

interface HostTimerControlsProps {
  roomId: string
  isRunning: boolean
  hasTimer: boolean
}

const PRESETS = [
  { label: '1min', value: 60 },
  { label: '2min', value: 120 },
  { label: '3min', value: 180 },
  { label: '5min', value: 300 },
  { label: '10min', value: 600 },
]

export function HostTimerControls({ roomId, isRunning, hasTimer }: HostTimerControlsProps) {
  const [busy, setBusy] = useState(false)
  const [selected, setSelected] = useState(120)
  const supabase = createClient()

  async function handleStart() {
    setBusy(true)
    await supabase.rpc('start_timer', {
      p_room_id: roomId,
      p_duration: selected,
    })
    setBusy(false)
  }

  async function handlePause() {
    setBusy(true)
    await supabase.rpc('pause_timer', { p_room_id: roomId })
    setBusy(false)
  }

  async function handleResume() {
    setBusy(true)
    await supabase.rpc('resume_timer', { p_room_id: roomId })
    setBusy(false)
  }

  async function handleReset() {
    setBusy(true)
    await supabase.rpc('reset_timer', { p_room_id: roomId })
    setBusy(false)
  }

  return (
    <div className="w-full max-w-sm mx-auto space-y-3">
      {/* Seletor de tempo (so aparece se ainda nao iniciou) */}
      {!hasTimer && (
        <div>
          <p className="text-neutral-500 text-[10px] uppercase tracking-wider mb-2 text-center">
            Tempo de discussão
          </p>
          <div className="flex gap-2 justify-center">
            {PRESETS.map((p) => (
              <button
                key={p.value}
                onClick={() => setSelected(p.value)}
                className={`
                  px-3 py-2 rounded-lg text-xs font-bold tracking-wider transition-all duration-200 cursor-pointer
                  ${
                    selected === p.value
                      ? 'bg-red-900/40 text-red-400 border border-red-800/60'
                      : 'bg-neutral-900 text-neutral-500 border border-neutral-800 hover:text-neutral-400'
                  }
                `}
              >
                {p.label}
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Botoes de controle */}
      <div className="flex gap-2 justify-center">
        {!hasTimer && (
          <button
            onClick={handleStart}
            disabled={busy}
            className="
              px-6 py-3 rounded-xl text-sm font-bold tracking-wider
              bg-green-800/40 border border-green-700/50 text-green-400
              hover:bg-green-700/50 active:bg-green-800/60
              disabled:opacity-30 disabled:cursor-not-allowed
              transition-all duration-200 cursor-pointer
            "
          >
            ▶ Iniciar
          </button>
        )}

        {hasTimer && isRunning && (
          <button
            onClick={handlePause}
            disabled={busy}
            className="
              px-6 py-3 rounded-xl text-sm font-bold tracking-wider
              bg-yellow-800/40 border border-yellow-700/50 text-yellow-400
              hover:bg-yellow-700/50 active:bg-yellow-800/60
              disabled:opacity-30 disabled:cursor-not-allowed
              transition-all duration-200 cursor-pointer
            "
          >
            ⏸ Pausar
          </button>
        )}

        {hasTimer && !isRunning && (
          <button
            onClick={handleResume}
            disabled={busy}
            className="
              px-6 py-3 rounded-xl text-sm font-bold tracking-wider
              bg-green-800/40 border border-green-700/50 text-green-400
              hover:bg-green-700/50 active:bg-green-800/60
              disabled:opacity-30 disabled:cursor-not-allowed
              transition-all duration-200 cursor-pointer
            "
          >
            ▶ Retomar
          </button>
        )}

        {hasTimer && (
          <button
            onClick={handleReset}
            disabled={busy}
            className="
              px-4 py-3 rounded-xl text-xs font-medium tracking-wider
              bg-neutral-900 border border-neutral-800 text-neutral-500
              hover:text-neutral-400 hover:border-neutral-700
              disabled:opacity-30 disabled:cursor-not-allowed
              transition-all duration-200 cursor-pointer
            "
          >
            ↺ Reset
          </button>
        )}
      </div>
    </div>
  )
}
