'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'

interface HunterRetaliatePanelProps {
  roomId: string
  hunterId: string
  onDone?: () => void
}

export function HunterRetaliatePanel({ roomId, hunterId, onDone }: HunterRetaliatePanelProps) {
  const [targets, setTargets] = useState<{ id: string; name: string }[]>([])
  const [hasActed, setHasActed] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const supabase = createClient()

  useEffect(() => {
    ;(async () => {
      try {
        const { data } = await supabase
          .from('player_profiles')
          .select('id, name, is_alive, is_host')
          .eq('room_id', roomId)
        if (data) {
          setTargets(
            (data as any[])
              .filter((r) => r.id !== hunterId && r.is_alive && !r.is_host)
              .map((r) => ({ id: r.id, name: r.name }))
          )
        }
      } catch {}
    })()
  }, [roomId, hunterId])

  async function handleShoot(targetId: string, _targetName: string) {
    setBusy(true)
    setError('')
    try {
      const { error: rpcErr } = await supabase.rpc('hunter_retaliate', {
        p_room_id: roomId,
        p_target_id: targetId,
      })
      if (rpcErr) {
        setError(rpcErr.message)
        setBusy(false)
        return
      }
      setHasActed(true)
      onDone?.()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erro inesperado')
    }
    setBusy(false)
  }

  async function handleSkip() {
    setBusy(true)
    setError('')
    try {
      const { error: rpcErr } = await supabase.rpc('hunter_skip', {
        p_room_id: roomId,
      })
      if (rpcErr) {
        setError(rpcErr.message)
        setBusy(false)
        return
      }
      setHasActed(true)
      onDone?.()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erro inesperado')
    }
    setBusy(false)
  }

  if (hasActed) {
    return (
      <div className="w-full max-w-sm text-center space-y-2">
        <p className="text-orange-500 text-sm font-semibold">🔫 Tiro Registrado</p>
        <p className="text-neutral-500 text-xs">A noite continua...</p>
      </div>
    )
  }

  return (
    <div className="w-full max-w-sm text-center space-y-4">
      <div>
        <p className="text-orange-500 text-sm uppercase tracking-widest font-bold">
          🔫 Caçador
        </p>
        <p className="text-red-500 text-xs mt-2 animate-pulse">
          Você foi eliminado! Antes de morrer, escolha sua vingança:
        </p>
      </div>

      <div className="space-y-2">
        {targets.map((t) => (
          <button
            key={t.id}
            onClick={() => handleShoot(t.id, t.name)}
            disabled={busy}
            className="
              w-full py-3 px-4 rounded-xl text-sm font-medium
              bg-neutral-900 border border-neutral-800 text-neutral-300
              hover:border-orange-700 hover:text-orange-400
              active:bg-orange-950/20
              disabled:opacity-40
              transition-all duration-200
              cursor-pointer
            "
          >
            🔫 {t.name}
          </button>
        ))}
      </div>

      <button
        onClick={handleSkip}
        disabled={busy}
        className="
          w-full py-3 px-4 rounded-xl text-sm font-medium
          bg-neutral-900 border border-neutral-800 text-neutral-500
          hover:text-neutral-400 hover:border-neutral-700
          disabled:opacity-40
          transition-all duration-200
          cursor-pointer
        "
      >
        ✋ Não atirar
      </button>

      {error && (
        <p className="text-red-500 text-xs text-center">{error}</p>
      )}
    </div>
  )
}
