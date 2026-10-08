'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useTargets } from '@/hooks/use-targets'

interface ChupacabraPanelProps {
  roomId: string
  playerId: string
  onDone?: () => void
}

export function ChupacabraPanel({ roomId, playerId, onDone }: ChupacabraPanelProps) {
  const [hasActed, setHasActed] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const supabase = createClient()
  const targets = useTargets(roomId, { selfId: playerId })

  async function handleKill(targetId: string) {
    setBusy(true)
    setError('')
    try {
      const res = await supabase.rpc('execute_night_action', {
        p_room_id: roomId,
        p_action_type: 'chupacabra_kill',
        p_target_id: targetId,
      })
      if (res.error) {
        setError(res.error.message)
      } else {
        // No feedback by design: the Chupacu never learns whether the target was a wolf.
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
        <p className="text-lime-500 text-sm uppercase tracking-widest font-bold">🦇 Chupacu</p>
        <p className="text-neutral-400 text-sm">Alvo escolhido. Volte a dormir...</p>
      </div>
    )
  }

  return (
    <div className="w-full max-w-sm text-center space-y-4">
      <p className="text-lime-500 text-sm uppercase tracking-widest font-bold">🦇 Chupacu</p>
      <p className="text-neutral-500 text-xs">Escolha quem atacar:</p>
      <div className="space-y-2">
        {targets.map((t) => (
          <button
            key={t.id}
            onClick={() => handleKill(t.id)}
            disabled={busy}
            className="w-full py-3 px-4 rounded-xl text-sm font-medium bg-neutral-900 border border-neutral-800 text-neutral-300 hover:border-lime-700 hover:text-lime-400 active:bg-lime-950/20 disabled:opacity-40 transition-all duration-200 cursor-pointer"
          >
            {t.name}
          </button>
        ))}
      </div>
      {error && <p className="text-red-500 text-xs text-center">{error}</p>}
    </div>
  )
}
