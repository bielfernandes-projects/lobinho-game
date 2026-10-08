'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useTargets } from '@/hooks/use-targets'

interface HuntressPanelProps {
  roomId: string
  playerId: string
  onDone?: () => void
}

export function HuntressPanel({ roomId, playerId, onDone }: HuntressPanelProps) {
  const [hasActed, setHasActed] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const supabase = createClient()
  const targets = useTargets(roomId, { selfId: playerId })

  async function handleShoot(targetId: string) {
    setBusy(true)
    setError('')
    try {
      const res = await supabase.rpc('execute_night_action', {
        p_room_id: roomId,
        p_action_type: 'huntress_kill',
        p_target_id: targetId,
      })
      if (res.error) {
        setError(res.error.message)
      } else {
        setHasActed(true)
        onDone?.()
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erro inesperado')
    }
    setBusy(false)
  }

  if (hasActed) {
    return (
      <div className="w-full max-w-sm text-center space-y-2">
        <p className="text-rose-500 text-sm uppercase tracking-widest font-bold">🏹 Caçadora</p>
        <p className="text-neutral-400 text-sm">Tiro disparado. Volte a dormir...</p>
      </div>
    )
  }

  return (
    <div className="w-full max-w-sm text-center space-y-4">
      <p className="text-rose-500 text-sm uppercase tracking-widest font-bold">🏹 Caçadora</p>
      <p className="text-neutral-500 text-xs">Uma vez por jogo, você pode eliminar alguém:</p>
      <div className="space-y-2">
        {targets.map((t) => (
          <button
            key={t.id}
            onClick={() => handleShoot(t.id)}
            disabled={busy}
            className="w-full py-3 px-4 rounded-xl text-sm font-medium bg-neutral-900 border border-neutral-800 text-neutral-300 hover:border-rose-700 hover:text-rose-400 disabled:opacity-40 transition-all duration-200 cursor-pointer"
          >
            {t.name}
          </button>
        ))}
      </div>
      <button
        onClick={() => onDone?.()}
        disabled={busy}
        className="w-full py-2 text-xs text-neutral-500 hover:text-neutral-300 cursor-pointer"
      >
        Não usar agora
      </button>
      {error && <p className="text-red-500 text-xs text-center">{error}</p>}
    </div>
  )
}
