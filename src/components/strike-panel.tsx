'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'

interface PlayerRow {
  id: string
  name: string
  is_alive: boolean
  is_host: boolean
  strikes: number
}

interface StrikePanelProps {
  roomId: string
  players: { id: string; name: string; isHost: boolean; isAlive: boolean }[]
  onPlayerKilled?: () => void
}

const MAX_STRIKES = 3

export function StrikePanel({ roomId, players, onPlayerKilled }: StrikePanelProps) {
  const [strikes, setStrikes] = useState<Record<string, number>>({})
  const [confirmTarget, setConfirmTarget] = useState<{ id: string; name: string } | null>(null)
  const [busy, setBusy] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const supabase = createClient()

  // Sincronizar strikes iniciais dos jogadores
  useEffect(() => {
    async function fetchStrikes() {
      const { data, error } = await supabase
        .from('players')
        .select('id, strikes')
        .eq('room_id', roomId)

      if (data && !error) {
        const map: Record<string, number> = {}
        for (const p of data as Pick<PlayerRow, 'id' | 'strikes'>[]) {
          map[p.id] = p.strikes ?? 0
        }
        setStrikes(map)
      }
    }
    fetchStrikes()

    // Realtime para sincronizar strikes entre abas
    const channel = supabase
      .channel(`strikes:${roomId}`)
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'players',
          filter: `room_id=eq.${roomId}`,
        },
        (payload) => {
          const raw = payload.new as { id: string; strikes?: number }
          if (raw && typeof raw.strikes === 'number') {
            setStrikes((prev) => ({ ...prev, [raw.id]: raw.strikes! }))
          }
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, [roomId])

  async function addStrike(playerId: string) {
    setBusy(playerId)
    setError(null)
    const res = await supabase.rpc('add_strike', {
      p_room_id: roomId,
      p_player_id: playerId,
    })
    if (res.error) {
      setError(res.error.message)
    } else if (res.data?.reached_max) {
      const target = players.find((p) => p.id === playerId)
      if (target) setConfirmTarget({ id: playerId, name: target.name })
    }
    setBusy(null)
  }

  async function removeStrike(playerId: string) {
    setBusy(playerId)
    setError(null)
    const res = await supabase.rpc('remove_strike', {
      p_room_id: roomId,
      p_player_id: playerId,
    })
    if (res.error) setError(res.error.message)
    setBusy(null)
  }

  async function confirmInstaKill() {
    if (!confirmTarget) return
    setBusy(confirmTarget.id)
    setError(null)
    const res = await supabase.rpc('insta_kill', {
      p_room_id: roomId,
      p_player_id: confirmTarget.id,
    })
    if (res.error) {
      setError(res.error.message)
    } else {
      onPlayerKilled?.()
    }
    setBusy(null)
    setConfirmTarget(null)
  }

  const alivePlayers = players.filter((p) => !p.isHost && p.isAlive)

  return (
    <div className="w-full max-w-sm mx-auto py-4 border-t border-neutral-800 space-y-3">
      <p className="text-orange-500 text-[10px] uppercase tracking-widest text-center font-bold">
        ⚠️ Strikes
      </p>

      {error && (
        <p className="text-red-500 text-[10px] text-center">{error}</p>
      )}

      {alivePlayers.length === 0 ? (
        <p className="text-neutral-600 text-[10px] text-center">Nenhum jogador vivo.</p>
      ) : (
        <div className="space-y-2">
          {alivePlayers.map((p) => {
            const count = strikes[p.id] ?? 0
            const isAtMax = count >= MAX_STRIKES
            return (
              <div
                key={p.id}
                className={`
                  flex items-center gap-2 rounded-lg border px-3 py-2
                  ${isAtMax
                    ? 'border-red-600/60 bg-red-950/20'
                    : 'border-neutral-800 bg-neutral-900'
                  }
                `}
              >
                <span className="flex-1 text-sm text-neutral-300 truncate">
                  {p.name}
                </span>
                <div className="flex items-center gap-1">
                  {[0, 1, 2].map((i) => (
                    <span
                      key={i}
                      className={`
                        w-2 h-2 rounded-full
                        ${i < count ? 'bg-red-500' : 'bg-neutral-700'}
                      `}
                    />
                  ))}
                  <span
                    className={`
                      text-[10px] font-bold tabular-nums ml-1 min-w-[2.5ch] text-center
                      ${isAtMax ? 'text-red-400' : 'text-neutral-500'}
                    `}
                  >
                    {count}/3
                  </span>
                </div>
                <button
                  onClick={() => removeStrike(p.id)}
                  disabled={busy === p.id || count === 0}
                  className="
                    px-2 py-1 rounded-md text-xs font-bold
                    bg-neutral-800 border border-neutral-700 text-neutral-400
                    hover:text-neutral-200 hover:border-neutral-600
                    disabled:opacity-30 disabled:cursor-not-allowed
                    transition-all duration-200 cursor-pointer
                  "
                  title="Remover strike"
                >
                  −
                </button>
                <button
                  onClick={() => addStrike(p.id)}
                  disabled={busy === p.id || isAtMax}
                  className={`
                    px-2 py-1 rounded-md text-xs font-bold
                    ${isAtMax
                      ? 'bg-red-800/40 border border-red-700/50 text-red-300 animate-pulse'
                      : 'bg-neutral-800 border border-neutral-700 text-neutral-400 hover:text-red-300 hover:border-red-700/50'
                    }
                    disabled:opacity-30 disabled:cursor-not-allowed
                    transition-all duration-200 cursor-pointer
                  `}
                  title={isAtMax ? '3/3 — clique para eliminar' : 'Adicionar strike'}
                >
                  +
                </button>
              </div>
            )
          })}
        </div>
      )}

      {/* Modal de confirmação de insta-kill */}
      {confirmTarget && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/70 backdrop-blur-sm p-4">
          <div className="bg-neutral-900 border-2 border-red-700 rounded-2xl p-6 max-w-sm w-full space-y-4 shadow-2xl">
            <p className="text-center text-5xl">☠️</p>
            <p className="text-red-500 text-lg font-black text-center tracking-wider">
              Eliminar jogador?
            </p>
            <p className="text-neutral-300 text-sm text-center">
              <span className="font-bold text-red-400">{confirmTarget.name}</span>{' '}
              atingiu 3/3 strikes.
            </p>
            <p className="text-neutral-500 text-xs text-center">
              Esta ação é instantânea e irreversível.
            </p>
            <div className="flex gap-3 pt-2">
              <button
                onClick={() => setConfirmTarget(null)}
                disabled={busy === confirmTarget.id}
                className="
                  flex-1 py-3 rounded-xl text-sm font-bold
                  bg-neutral-800 border border-neutral-700 text-neutral-300
                  hover:bg-neutral-700
                  disabled:opacity-30 disabled:cursor-not-allowed
                  transition-all duration-200 cursor-pointer
                "
              >
                Cancelar
              </button>
              <button
                onClick={confirmInstaKill}
                disabled={busy === confirmTarget.id}
                className="
                  flex-1 py-3 rounded-xl text-sm font-bold
                  bg-red-800 border border-red-700 text-red-100
                  hover:bg-red-700
                  disabled:opacity-30 disabled:cursor-not-allowed
                  transition-all duration-200 cursor-pointer
                "
              >
                ☠️ Eliminar
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
