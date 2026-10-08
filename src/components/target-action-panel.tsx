'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useTargets } from '@/hooks/use-targets'

interface TargetActionPanelProps {
  roomId: string
  playerId: string
  actionType: string
  title: string
  prompt: string
  doneText: string
  onDone?: () => void
}

// Generic "pick one alive player" night action with no feedback (Dire Wolf companion, Old Witch pox).
export function TargetActionPanel({ roomId, playerId, actionType, title, prompt, doneText, onDone }: TargetActionPanelProps) {
  const [hasActed, setHasActed] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const supabase = createClient()
  const targets = useTargets(roomId, { selfId: playerId })

  async function handlePick(targetId: string) {
    setBusy(true)
    setError('')
    try {
      const res = await supabase.rpc('execute_night_action', {
        p_room_id: roomId,
        p_action_type: actionType,
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
        <p className="text-neutral-300 text-sm uppercase tracking-widest font-bold">{title}</p>
        <p className="text-neutral-400 text-sm">{doneText}</p>
      </div>
    )
  }

  return (
    <div className="w-full max-w-sm text-center space-y-4">
      <p className="text-neutral-300 text-sm uppercase tracking-widest font-bold">{title}</p>
      <p className="text-neutral-500 text-xs">{prompt}</p>
      <div className="space-y-2">
        {targets.map((t) => (
          <button
            key={t.id}
            onClick={() => handlePick(t.id)}
            disabled={busy}
            className="w-full py-3 px-4 rounded-xl text-sm font-medium bg-neutral-900 border border-neutral-800 text-neutral-300 hover:border-neutral-600 disabled:opacity-40 transition-all duration-200 cursor-pointer"
          >
            {t.name}
          </button>
        ))}
      </div>
      {error && <p className="text-red-500 text-xs text-center">{error}</p>}
    </div>
  )
}
