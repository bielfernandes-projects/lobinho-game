'use client'

import { useState, useEffect, useRef, useCallback } from 'react'

function fmt(sec: number): string {
  const m = Math.floor(sec / 60)
  const s = sec % 60
  return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
}

interface VoteTimerProps {
  label: string
}

function VoteTimer({ label }: VoteTimerProps) {
  const [remaining, setRemaining] = useState(60)
  const [running, setRunning] = useState(false)
  const [minutesInput, setMinutesInput] = useState('1')
  const [inputError, setInputError] = useState('')
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null)

  const stop = useCallback(() => {
    if (intervalRef.current) {
      clearInterval(intervalRef.current)
      intervalRef.current = null
    }
    setRunning(false)
  }, [])

  useEffect(() => {
    return () => { if (intervalRef.current) clearInterval(intervalRef.current) }
  }, [])

  function parseMinutes(): number | null {
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
    if (num > 10) {
      setInputError('Máximo: 10 min')
      return null
    }
    setInputError('')
    return Math.round(num * 60)
  }

  function handlePlay() {
    if (running) return
    if (remaining <= 0) {
      // Tentar reiniciar com novo valor do input
      const sec = parseMinutes()
      if (sec == null) return
      setRemaining(sec)
      setRunning(true)
      intervalRef.current = setInterval(() => {
        setRemaining((prev) => {
          if (prev <= 1) { stop(); return 0 }
          return prev - 1
        })
      }, 1000)
      return
    }
    setRunning(true)
    intervalRef.current = setInterval(() => {
      setRemaining((prev) => {
        if (prev <= 1) { stop(); return 0 }
        return prev - 1
      })
    }, 1000)
  }

  function handlePause() { stop() }

  function handleReset() {
    stop()
    const sec = parseMinutes()
    if (sec != null) {
      setRemaining(sec)
    } else {
      setRemaining(60)
    }
  }

  const expired = remaining <= 0

  return (
    <div className="w-full max-w-sm mx-auto">
      <p className="text-neutral-500 text-[10px] uppercase tracking-wider mb-1 text-center">{label}</p>
      <div className="flex items-center gap-2 justify-center mb-2">
        <input
          type="number"
          inputMode="decimal"
          step="0.5"
          min="0.5"
          max="10"
          value={minutesInput}
          onChange={(e) => {
            setMinutesInput(e.target.value)
            if (inputError) setInputError('')
          }}
          placeholder="Min"
          className="
            w-16 px-2 py-1 rounded-md text-xs font-bold text-center
            bg-neutral-900 text-red-400 border border-red-800/60
            focus:outline-none focus:border-red-600
            tabular-nums
            [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none
          "
        />
        <span className="text-neutral-500 text-[10px]">min</span>
      </div>
      {inputError && (
        <p className="text-red-500 text-[10px] text-center mb-1">
          {inputError}
        </p>
      )}
      <div className="flex items-center gap-3 justify-center">
        <span
          className={`text-3xl font-black tracking-widest tabular-nums select-none min-w-[5ch] text-center ${
            expired
              ? 'text-red-600 animate-pulse'
              : running
              ? 'text-red-400'
              : 'text-neutral-400'
          }`}
        >
          {fmt(remaining)}
        </span>
        <div className="flex gap-1">
          {!running ? (
            <button
              onClick={handlePlay}
              disabled={expired}
              className="px-3 py-1.5 rounded-lg text-xs font-bold bg-neutral-900 border border-neutral-800 text-green-400 hover:bg-green-900/30 disabled:opacity-30 cursor-pointer transition-all duration-200"
            >
              ▶
            </button>
          ) : (
            <button
              onClick={handlePause}
              className="px-3 py-1.5 rounded-lg text-xs font-bold bg-neutral-900 border border-neutral-800 text-yellow-400 hover:bg-yellow-900/30 cursor-pointer transition-all duration-200"
            >
              ⏸
            </button>
          )}
          <button
            onClick={handleReset}
            className="px-3 py-1.5 rounded-lg text-xs font-bold bg-neutral-900 border border-neutral-800 text-neutral-500 hover:text-neutral-400 cursor-pointer transition-all duration-200"
          >
            ↺
          </button>
        </div>
      </div>
    </div>
  )
}

export function VoteTimerPanel() {
  return (
    <div className="w-full max-w-sm mx-auto space-y-4 py-4 border-t border-neutral-800">
      <p className="text-neutral-600 text-[10px] uppercase tracking-widest text-center">Tribunal</p>
      <VoteTimer label="⏱️ Tempo do Tribunal" />
    </div>
  )
}
