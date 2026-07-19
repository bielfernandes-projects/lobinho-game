'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'

interface MarksmanPanelProps {
  roomId: string
  playerId: string
  onShot?: () => void
}

export function MarksmanPanel({ roomId, playerId, onShot }: MarksmanPanelProps) {
  const [targets, setTargets] = useState<{ id: string; name: string }[]>([])
  const [hasActed, setHasActed] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [showModal, setShowModal] = useState(false)
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
              .filter((r) => r.id !== playerId && r.is_alive && !r.is_host)
              .map((r) => ({ id: r.id, name: r.name }))
          )
        }
      } catch {}
    })()
  }, [roomId, playerId])

  async function handleShoot(targetId: string) {
    setBusy(true)
    setError('')
    try {
      const { error: rpcErr } = await supabase.rpc('marksman_shoot', {
        p_room_id: roomId,
        p_target_id: targetId,
      })
      if (rpcErr) {
        setError(rpcErr.message)
        setShowModal(false)
        setBusy(false)
        return
      }
      setHasActed(true)
      setShowModal(false)
      onShot?.()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erro inesperado')
      setShowModal(false)
    }
    setBusy(false)
  }

  if (hasActed) {
    return (
      <div className="w-full max-w-sm text-center space-y-2">
        <p className="text-red-500 text-sm font-semibold">🎯 Tiro Disparado</p>
        <p className="text-neutral-500 text-xs">Seu poder foi usado. Agora participe da discussão.</p>
      </div>
    )
  }

  return (
    <>
      <button
        onClick={() => setShowModal(true)}
        className="
          w-full py-4 rounded-2xl font-bold text-lg tracking-wider
          bg-red-900/30 border border-red-700/50 text-red-400
          hover:bg-red-800/40 active:bg-red-800/60
          transition-all duration-200 cursor-pointer
        "
      >
        🎯 Atirar em Alguém
      </button>

      {showModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 px-6">
          <div className="w-full max-w-xs rounded-2xl border border-neutral-800 bg-neutral-950 p-6 text-center space-y-3">
            <p className="text-red-400 text-sm font-bold uppercase tracking-wider">🎯 Atirador</p>
            <p className="text-neutral-500 text-xs">Escolha seu alvo:</p>
            <div className="space-y-2 max-h-60 overflow-y-auto">
              {targets.map((t) => (
                <button
                  key={t.id}
                  onClick={() => handleShoot(t.id)}
                  disabled={busy}
                  className="w-full py-2.5 px-4 rounded-xl text-sm font-medium bg-neutral-900 border border-neutral-800 text-neutral-300 hover:border-red-700 hover:text-red-400 disabled:opacity-40 transition-all duration-200 cursor-pointer text-left"
                >
                  {t.name}
                </button>
              ))}
            </div>
            <button
              onClick={() => setShowModal(false)}
              className="text-neutral-600 text-xs underline cursor-pointer"
            >
              Cancelar
            </button>
          </div>
        </div>
      )}

      {error && (
        <p className="text-red-500 text-xs text-center">{error}</p>
      )}
    </>
  )
}
