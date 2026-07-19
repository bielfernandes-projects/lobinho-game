'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'

interface HostTimerControlsProps {
  roomId: string
  isRunning: boolean
  hasTimer: boolean
}

export function HostTimerControls({ roomId, isRunning, hasTimer }: HostTimerControlsProps) {
  const [busy, setBusy] = useState(false)
  const [minutesInput, setMinutesInput] = useState('2')
  const [inputError, setInputError] = useState('')
  const supabase = createClient()

  function validateAndParse(): number | null {
    const trimmed = minutesInput.trim()
    if (!trimmed) {
      setInputError('Digite um valor')
      return null
    }
    const num = Number(trimmed)
    if (!Number.isFinite(num) || num <= 0) {
      setInputError('Valor inválido')
      return null
    }
    if (num < 0.5) {
      setInputError('Mínimo: 0.5 min')
      return null
    }
    if (num > 30) {
      setInputError('Máximo: 30 min')
      return null
    }
    setInputError('')
    return Math.round(num * 60)
  }

  async function handleStart() {
    const seconds = validateAndParse()
    if (seconds == null) return
    setBusy(true)
    await supabase.rpc('start_timer', {
      p_room_id: roomId,
      p_duration: seconds,
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
            Tempo de discussão (minutos)
          </p>
          <div className="flex items-center gap-2 justify-center">
            <input
              type="number"
              inputMode="decimal"
              step="0.5"
              min="0.5"
              max="30"
              value={minutesInput}
              onChange={(e) => {
                setMinutesInput(e.target.value)
                if (inputError) setInputError('')
              }}
              onKeyDown={(e) => {
                if (e.key === 'Enter') handleStart()
              }}
              placeholder="Minutos"
              className="
                w-24 px-3 py-2 rounded-lg text-sm font-bold text-center
                bg-neutral-900 text-red-400 border border-red-800/60
                focus:outline-none focus:border-red-600
                tabular-nums
                [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none
              "
            />
            <span className="text-neutral-500 text-xs font-medium">min</span>
          </div>
          {inputError && (
            <p className="text-red-500 text-[10px] text-center mt-1">
              {inputError}
            </p>
          )}
          <p className="text-neutral-600 text-[10px] text-center mt-1">
            Aceita decimais: 1.5 = 1min30s
          </p>
        </div>
      )}

      {/* Botoes de controle */}
      <div className="flex gap-2 justify-center flex-wrap">
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
