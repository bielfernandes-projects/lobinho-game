'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'

interface DoppelgangerPanelProps {
  roomId: string
  playerId: string
  onDone?: () => void
}

export function DoppelgangerPanel({ roomId, playerId, onDone }: DoppelgangerPanelProps) {
  const [targets, setTargets] = useState<{ id: string; name: string }[]>([])
  const [selected, setSelected] = useState(false)
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

  async function handleSelect(targetId: string, name: string) {
    setBusy(true)
    setError('')
    try {
      const res = await supabase.rpc('doppelganger_select', {
        p_room_id: roomId,
        p_target_id: targetId,
      })
      if (res.error) {
        console.error('[DoppelgangerPanel] RPC error:', res.error)
        setError(res.error.message)
        setBusy(false)
        return
      }
      if (res.data?.success) {
        setSelected(true)
        onDone?.()
      }
    } catch (err) {
      console.error('[DoppelgangerPanel] Unexpected:', err)
      setError(err instanceof Error ? err.message : 'Erro inesperado')
    }
    setBusy(false)
  }

  if (selected) {
    return (
      <div className="w-full max-w-sm text-center space-y-4">
        <p className="text-violet-500 text-sm uppercase tracking-widest font-bold">
          🎭 Doppelgänger
        </p>
        <div className="p-6 rounded-2xl border-2 border-violet-700 bg-violet-950/20">
          <p className="text-neutral-400 text-xs mb-2">Você escolheu seu alvo.</p>
          <p className="text-violet-400 text-sm font-bold">
            Quando ele morrer, você assumirá seu papel.
          </p>
        </div>
      </div>
    )
  }

  return (
    <div className="w-full max-w-sm text-center space-y-4">
      <p className="text-violet-500 text-sm uppercase tracking-widest font-bold">
        🎭 Doppelgänger
      </p>
      <p className="text-neutral-500 text-xs">Escolha um jogador para ser seu alvo:</p>
      <div className="space-y-2">
        {targets.map((t) => (
          <button
            key={t.id}
            onClick={() => handleSelect(t.id, t.name)}
            disabled={busy || selected}
            className="
              w-full py-3 px-4 rounded-xl text-sm font-medium
              bg-neutral-900 border border-neutral-800 text-neutral-300
              hover:border-violet-700 hover:text-violet-400
              active:bg-violet-950/20
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
