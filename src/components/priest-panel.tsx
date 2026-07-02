'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'

interface PriestPanelProps {
  roomId: string
  playerId: string
  turnIndex: number
  onDone?: () => void
}

export function PriestPanel({ roomId, playerId, turnIndex, onDone }: PriestPanelProps) {
  const [targets, setTargets] = useState<{ id: string; name: string }[]>([])
  const [hasActed, setHasActed] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
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
              .filter((r) => r.id !== playerId && r.is_alive && !r.is_host)
              .map((r) => ({ id: r.id, name: r.name }))
          )
        }
      })
  }, [roomId, playerId])

  async function handleBless(targetId: string) {
    setBusy(true)
    setError('')
    try {
      const { error: rpcErr } = await supabase.rpc('execute_night_action', {
        p_room_id: roomId,
        p_action_type: 'priest_bless',
        p_target_id: targetId,
      })
      if (rpcErr) {
        console.error('[PriestPanel] RPC error:', rpcErr)
        setError(rpcErr.message)
        setBusy(false)
        return
      }
      setHasActed(true)
      onDone?.()
    } catch (err) {
      console.error('[PriestPanel] Unexpected:', err)
      setError(err instanceof Error ? err.message : 'Erro inesperado')
    }
    setBusy(false)
  }

  if (hasActed) {
    return (
      <div className="w-full max-w-sm text-center space-y-2">
        <p className="text-neutral-500 text-sm font-semibold">✅ Bênção Concedida</p>
        <p className="text-neutral-700 text-xs">Aguarde a noite passar...</p>
      </div>
    )
  }

  return (
    <div className="w-full max-w-sm text-center space-y-4">
      <p className="text-sky-500 text-sm uppercase tracking-widest font-bold">
        🙏 Padre
      </p>
      <p className="text-neutral-500 text-xs">Abençoe um jogador (1 uso por jogo):</p>
      <div className="space-y-2">
        {targets.map((t) => (
          <button
            key={t.id}
            onClick={() => handleBless(t.id)}
            disabled={busy}
            className="
              w-full py-3 px-4 rounded-xl text-sm font-medium
              bg-neutral-900 border border-neutral-800 text-neutral-300
              hover:border-sky-700 hover:text-sky-400
              active:bg-sky-950/20
              disabled:opacity-40
              transition-all duration-200
              cursor-pointer
            "
          >
            {t.name}
          </button>
        ))}
      </div>
      {error && (
        <p className="text-red-500 text-xs text-center">{error}</p>
      )}
    </div>
  )
}
