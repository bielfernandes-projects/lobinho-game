'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import type { RoomProfile } from '@/hooks/use-room'

interface CupidPanelProps {
  roomId: string
  playerId: string
  onDone?: () => void
}

export function CupidPanel({ roomId, playerId, onDone }: CupidPanelProps) {
  const [players, setPlayers] = useState<RoomProfile[]>([])
  const [targetA, setTargetA] = useState<string | null>(null)
  const [targetB, setTargetB] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [hasActed, setHasActed] = useState(false)
  const supabase = createClient()

  useEffect(() => {
    async function load() {
      try {
        const { data: all } = await supabase
          .from('player_profiles')
          .select('id, name, is_host, is_alive, has_viewed_card, user_id')
          .eq('room_id', roomId)

        if (!all) return

        setPlayers(
          (all as any[])
            .filter((r) => r.id !== playerId && r.is_alive && !r.is_host)
            .map((r) => ({
              id: r.id,
              name: r.name,
              isHost: r.is_host,
              isAlive: r.is_alive,
              hasViewedCard: r.has_viewed_card,
              userId: r.user_id,
            }))
        )
      } catch {}
    }

    load()
  }, [roomId, playerId])

  async function handleMatch() {
    if (!targetA || !targetB || targetA === targetB) return
    setBusy(true)
    setError('')
    try {
      const { error: rpcErr } = await supabase.rpc('submit_cupid_match', {
        p_room_id: roomId,
        p_target_a: targetA,
        p_target_b: targetB,
      })
      if (rpcErr) {
        console.error('[CupidPanel] RPC error:', rpcErr)
        setError(rpcErr.message)
        setBusy(false)
        return
      }
      setHasActed(true)
      onDone?.()
    } catch (err) {
      console.error('[CupidPanel] Unexpected:', err)
      setError(err instanceof Error ? err.message : 'Erro inesperado')
    }
    setBusy(false)
  }

  if (hasActed) {
    return (
      <div className="w-full max-w-sm text-center space-y-2">
        <p className="text-neutral-500 text-sm font-semibold">✅ Almas Gêmeas Unidas</p>
        <p className="text-neutral-700 text-xs">Aguarde a noite passar...</p>
      </div>
    )
  }

  return (
    <div className="w-full max-w-sm text-center space-y-4">
      <p className="text-pink-500 text-sm uppercase tracking-widest font-bold">
        💘 Cupido
      </p>
      <p className="text-neutral-400 text-xs">
        {!targetA
          ? 'Escolha o primeiro jogador:'
          : !targetB
            ? 'Escolha o segundo jogador:'
            : 'Confirme sua escolha:'}
      </p>

      {(!targetA || !targetB) && (
        <div className="space-y-2">
          {players
            .filter((p) => p.id !== targetA)
            .map((p) => (
              <button
                key={p.id}
                onClick={() => {
                  if (!targetA) setTargetA(p.id)
                  else if (!targetB && p.id !== targetA) setTargetB(p.id)
                }}
                disabled={busy}
                className={`w-full py-3 px-4 rounded-xl text-sm font-medium transition-all duration-200 cursor-pointer ${
                  targetA === p.id || targetB === p.id
                    ? 'bg-pink-900/40 border border-pink-600/50 text-pink-300'
                    : 'bg-neutral-900 border border-neutral-800 text-neutral-300 hover:border-pink-800 hover:text-pink-400'
                }`}
              >
                {p.name}
              </button>
            ))}
        </div>
      )}

      {targetA && targetB && (
        <div className="space-y-3">
          <div className="rounded-xl border border-pink-800/40 bg-pink-950/20 px-4 py-3 text-center">
            <p className="text-pink-400 text-xs font-semibold">
              💕 {players.find((p) => p.id === targetA)?.name} & {players.find((p) => p.id === targetB)?.name}
            </p>
          </div>
          <button
            onClick={handleMatch}
            disabled={busy}
            className="w-full py-3 px-4 rounded-xl text-sm font-bold bg-pink-900/30 border border-pink-700/50 text-pink-400 hover:bg-pink-800/40 transition-all duration-200 cursor-pointer"
          >
            Unir Almas Gêmeas
          </button>
        </div>
      )}

      {error && (
        <p className="text-red-500 text-xs text-center">{error}</p>
      )}
    </div>
  )
}
