'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'

interface BodyguardPanelProps {
  roomId: string
  playerId: string
  turnIndex: number
  onDone?: () => void
}

const STORAGE_KEY_PREFIX = 'lobinho_bodyguard_last_target'

export function BodyguardPanel({ roomId, playerId, turnIndex, onDone }: BodyguardPanelProps) {
  const [targets, setTargets] = useState<{ id: string; name: string }[]>([])
  const [hasActed, setHasActed] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [lastTargetId, setLastTargetId] = useState<string | null>(null)
  const supabase = createClient()

  useEffect(() => {
    supabase
      .from('player_profiles')
      .select('id, name, is_alive, is_host')
      .eq('room_id', roomId)
      .then(({ data }) => {
        if (data) {
          setTargets(
            (data as any[])
              .filter((r) => r.is_alive && !r.is_host)
              .map((r) => ({ id: r.id, name: r.name }))
          )
        }
      })

    const stored = localStorage.getItem(`${STORAGE_KEY_PREFIX}_${roomId}_${playerId}`)
    if (stored) {
      setLastTargetId(stored)
    }
  }, [roomId, playerId])

  async function handleProtect(targetId: string) {
    setBusy(true)
    setError('')
    try {
      const { error: rpcErr } = await supabase.rpc('execute_night_action', {
        p_room_id: roomId,
        p_action_type: 'bodyguard_protect',
        p_target_id: targetId,
      })
      if (rpcErr) {
        console.error('[BodyguardPanel] RPC error:', rpcErr)
        setError(rpcErr.message)
        setBusy(false)
        return
      }
      localStorage.setItem(`${STORAGE_KEY_PREFIX}_${roomId}_${playerId}`, targetId)
      setHasActed(true)
      onDone?.()
    } catch (err) {
      console.error('[BodyguardPanel] Unexpected:', err)
      setError(err instanceof Error ? err.message : 'Erro inesperado')
    }
    setBusy(false)
  }

  if (hasActed) {
    return (
      <div className="w-full max-w-sm text-center space-y-2">
        <p className="text-neutral-500 text-sm font-semibold">✅ Proteção Registrada</p>
        <p className="text-neutral-700 text-xs">Aguarde a noite passar...</p>
      </div>
    )
  }

  return (
    <div className="w-full max-w-sm text-center space-y-4">
      <p className="text-amber-500 text-sm uppercase tracking-widest font-bold">
        🛡️ Guarda-costas
      </p>
      <p className="text-neutral-500 text-xs">Escolha alguém para proteger esta noite:</p>
      <div className="space-y-2">
        {targets.map((t) => {
          const blocked = t.id === lastTargetId
          return (
            <button
              key={t.id}
              onClick={() => handleProtect(t.id)}
              disabled={busy || blocked}
              className={`
                w-full py-3 px-4 rounded-xl text-sm font-medium
                transition-all duration-200 cursor-pointer
                ${blocked
                  ? 'bg-neutral-950 border border-neutral-800 text-neutral-700 line-through'
                  : 'bg-neutral-900 border border-neutral-800 text-neutral-300 hover:border-amber-700 hover:text-amber-400 active:bg-amber-950/20'
                }
                disabled:opacity-40
              `}
            >
              {t.name}
              {blocked && <span className="ml-2 text-neutral-700 text-[10px]">(protegido na noite anterior)</span>}
            </button>
          )
        })}
      </div>
      {error && (
        <p className="text-red-500 text-xs text-center">{error}</p>
      )}
    </div>
  )
}
