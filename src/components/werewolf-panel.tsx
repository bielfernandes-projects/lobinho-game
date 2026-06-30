'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import type { RoomProfile } from '@/hooks/use-room'

interface WerewolfPanelProps {
  roomId: string
  playerId: string
  turnIndex: number
}

export function WerewolfPanel({ roomId, playerId, turnIndex }: WerewolfPanelProps) {
  const [wolves, setWolves] = useState<RoomProfile[]>([])
  const [targets, setTargets] = useState<RoomProfile[]>([])
  const [voted, setVoted] = useState(false)
  const [busy, setBusy] = useState(false)
  const supabase = createClient()

  useEffect(() => {
    async function load() {
      const { data: all } = await supabase
        .from('player_profiles')
        .select('id, name, is_host, is_alive, has_viewed_card, user_id')
        .eq('room_id', roomId)

      if (!all) return

      const profiles = (all as any[]).map((r) => ({
        id: r.id,
        name: r.name,
        isHost: r.is_host,
        isAlive: r.is_alive,
        hasViewedCard: r.has_viewed_card,
        userId: r.user_id,
      }))

      const { data: wolves } = await supabase.rpc('get_werewolf_teammates', {
        p_room_id: roomId,
      })

      if (wolves) {
        const wolfIds = new Set(
          (wolves as { id: string; name: string }[]).map((w) => w.id)
        )

        setWolves(profiles.filter((p) => wolfIds.has(p.id)))
        setTargets(profiles.filter((p) => p.isAlive && !wolfIds.has(p.id) && !p.isHost))
      }
    }

    load()
  }, [roomId, playerId])

  async function handleKill(targetId: string) {
    setBusy(true)
    const { error } = await supabase.rpc('submit_night_action', {
      p_room_id: roomId,
      p_action_type: 'werewolf_kill',
      p_target_id: targetId,
    })
    if (!error) setVoted(true)
    setBusy(false)
  }

  if (voted) {
    return (
      <div className="text-center">
        <p className="text-green-600 text-sm font-semibold">✅ Voto registrado</p>
        <p className="text-neutral-700 text-xs mt-1">Aguardando os outros lobos...</p>
      </div>
    )
  }

  return (
    <div className="w-full max-w-sm text-center space-y-4">
      <p className="text-red-500 text-sm uppercase tracking-widest font-bold">
        🐺 Lobisomens
      </p>

      {wolves.length > 1 && (
        <div>
          <p className="text-neutral-600 text-[10px] uppercase tracking-wider mb-2">
            Seus aliados
          </p>
          <div className="flex flex-wrap justify-center gap-2">
            {wolves
              .filter((w) => w.id !== playerId)
              .map((w) => (
                <span
                  key={w.id}
                  className="px-3 py-1 rounded-full bg-red-950/40 border border-red-900/30 text-red-400 text-xs"
                >
                  {w.name}
                </span>
              ))}
          </div>
        </div>
      )}

      <div>
        <p className="text-neutral-500 text-xs mb-3">Escolha a vítima:</p>
        <div className="space-y-2">
          {targets.map((t) => (
            <button
              key={t.id}
              onClick={() => handleKill(t.id)}
              disabled={busy}
              className="
                w-full py-3 px-4 rounded-xl text-sm font-medium
                bg-neutral-900 border border-neutral-800 text-neutral-300
                hover:border-red-800 hover:text-red-400
                active:bg-red-950/20
                disabled:opacity-40
                transition-all duration-200
                cursor-pointer
              "
            >
              {t.name}
            </button>
          ))}
        </div>
      </div>
    </div>
  )
}
