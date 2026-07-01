'use client'

import { useState, useEffect, useRef } from 'react'

interface TimerDisplayProps {
  remaining: number | null
  isRunning: boolean
  startedAt: string | null
}

function fmt(sec: number): string {
  const m = Math.floor(sec / 60)
  const s = sec % 60
  return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
}

export function TimerDisplay({ remaining, isRunning, startedAt }: TimerDisplayProps) {
  const [localSec, setLocalSec] = useState<number | null>(remaining)
  const prevRemainingRef = useRef(remaining)
  const clientStartRef = useRef<number | null>(null)

  // Capturar timestamp local quando o timer iniciar/retomar
  useEffect(() => {
    if (isRunning && startedAt) {
      clientStartRef.current = Date.now()
    } else {
      clientStartRef.current = null
    }
  }, [isRunning, startedAt])

  // Sincronizar com valor fresco do DB
  useEffect(() => {
    if (remaining !== prevRemainingRef.current) {
      prevRemainingRef.current = remaining
      // So atualiza se parado ou se veio atualizacao externa (pause/reset)
      if (!isRunning || !startedAt) {
        setLocalSec(remaining)
      }
    }
  }, [remaining, isRunning, startedAt])

  // Loop local quando estiver rodando
  useEffect(() => {
    if (!isRunning || remaining === null || !startedAt || clientStartRef.current === null) {
      setLocalSec(remaining)
      return
    }

    const calc = () => {
      const elapsed = Math.floor((Date.now() - clientStartRef.current!) / 1000)
      return Math.max(0, (remaining ?? 0) - elapsed)
    }

    setLocalSec(calc())

    const interval = setInterval(() => {
      const val = calc()
      setLocalSec(val)
    }, 200)

    return () => clearInterval(interval)
  }, [isRunning, remaining, startedAt])

  const display = localSec ?? remaining
  if (display === null) return null

  const expired = display <= 0

  return (
    <div className="flex flex-col items-center gap-2">
      <div
        className={`
          text-5xl font-black tracking-[0.15em] tabular-nums select-none
          transition-colors duration-300
          ${expired
            ? 'text-red-600 animate-pulse drop-shadow-[0_0_20px_rgba(220,38,38,0.6)]'
            : isRunning
            ? 'text-red-400 drop-shadow-[0_0_10px_rgba(248,113,113,0.3)]'
            : 'text-neutral-400'
          }
        `}
      >
        {fmt(display)}
      </div>

      {expired && (
        <p className="text-red-500 text-sm font-bold uppercase tracking-widest animate-pulse">
          ⏰ Tempo Esgotado!
        </p>
      )}

      {!expired && !isRunning && display > 0 && (
        <p className="text-neutral-600 text-[10px] uppercase tracking-widest">
          ⏸️ Pausado
        </p>
      )}
    </div>
  )
}
