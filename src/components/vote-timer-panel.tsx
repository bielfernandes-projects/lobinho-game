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

  function handlePlay() {
    if (remaining <= 0) return
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
    setRemaining(60)
  }

  const expired = remaining <= 0

  return (
    <div className="w-full max-w-sm mx-auto">
      <p className="text-neutral-500 text-[10px] uppercase tracking-wider mb-1 text-center">{label}</p>
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
      <VoteTimer label="Tempo de Acusação" />
      <VoteTimer label="Tempo de Apoio" />
      <VoteTimer label="Tempo de Defesa" />
    </div>
  )
}
