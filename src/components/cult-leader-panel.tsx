'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'

interface CultLeaderPanelProps {
  roomId: string
  playerId: string
  onDone?: () => void
}

export function CultLeaderPanel({ roomId, playerId, onDone }: CultLeaderPanelProps) {
  const [targets, setTargets] = useState<{ id: string; name: string }[]>([])
  const [hasActed, setHasActed] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const supabase = createClient()

  useEffect(() => {
    async function load() {
      try {
        const { data } = await supabase.rpc('get_cult_targets', {
          p_room_id: roomId,
        })

        if (data) {
          setTargets(data as { id: string; name: string }[])
        }
      } catch {}
    }

    load()
  }, [roomId, playerId])

  async function handleConvert(targetId: string) {
    setBusy(true)
    setError('')
    try {
      const { error: rpcErr } = await supabase.rpc('execute_night_action', {
        p_room_id: roomId,
        p_action_type: 'cult_convert',
        p_target_id: targetId,
      })
      if (rpcErr) {
        console.error('[CultLeaderPanel] RPC error:', rpcErr)
        setError(rpcErr.message)
        setBusy(false)
        return
      }
      setHasActed(true)
      onDone?.()
    } catch (err) {
      console.error('[CultLeaderPanel] Unexpected:', err)
      setError(err instanceof Error ? err.message : 'Erro inesperado')
    }
    setBusy(false)
  }

  if (hasActed) {
    return (
      <div className="w-full max-w-sm text-center space-y-2">
        <p className="text-neutral-500 text-sm font-semibold">✅ Conversão Realizada</p>
        <p className="text-neutral-700 text-xs">Aguarde a noite passar...</p>
      </div>
    )
  }

  return (
    <div className="w-full max-w-sm text-center space-y-4">
      <p className="text-violet-500 text-sm uppercase tracking-widest font-bold">
        🔮 Líder de Culto
      </p>

      <div>
        <p className="text-neutral-500 text-xs mb-3">Escolha alguém para converter:</p>
        <div className="space-y-2">
          {targets.map((t) => (
            <button
              key={t.id}
              onClick={() => handleConvert(t.id)}
              disabled={busy}
              className="
                w-full py-3 px-4 rounded-xl text-sm font-medium
                bg-neutral-900 border border-neutral-800 text-neutral-300
                hover:border-violet-800 hover:text-violet-400
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
        {targets.length === 0 && (
          <p className="text-neutral-600 text-xs">Ninguém disponível para converter.</p>
        )}
      </div>

      {error && (
        <p className="text-red-500 text-xs text-center">{error}</p>
      )}
    </div>
  )
}
