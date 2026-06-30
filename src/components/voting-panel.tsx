'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'

interface VotingPanelProps {
  roomId: string
  playerId: string
  isAlive: boolean
  turnIndex: number
}

export function VotingPanel({ roomId, playerId, isAlive, turnIndex }: VotingPanelProps) {
  const [targets, setTargets] = useState<{ id: string; name: string }[]>([])
  const [votedFor, setVotedFor] = useState<string | null>(null)
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

  async function handleVote(targetId: string) {
    setBusy(true)
    setError('')
    try {
      const { error: rpcErr } = await supabase.rpc('submit_vote', {
        p_room_id: roomId,
        p_turn_index: turnIndex,
        p_target_id: targetId,
      })
      if (rpcErr) {
        console.error('[VotingPanel] RPC error:', rpcErr)
        setError(rpcErr.message)
        setBusy(false)
        return
      }
      setVotedFor(targetId)
    } catch (err) {
      console.error('[VotingPanel] Unexpected:', err)
      setError(err instanceof Error ? err.message : 'Erro inesperado')
    }
    setBusy(false)
  }

  if (!isAlive) {
    return (
      <div className="flex flex-1 flex-col items-center justify-center px-6">
        <p className="text-neutral-700 text-lg font-bold">💀 Você está morto</p>
        <p className="text-neutral-800 text-xs mt-2">Assista o desenrolar...</p>
      </div>
    )
  }

  if (votedFor) {
    const targetName = targets.find((t) => t.id === votedFor)?.name ?? ''
    return (
      <div className="flex flex-1 flex-col items-center justify-center px-6">
        <div className="text-center">
          <p className="text-green-600 text-sm font-semibold">✅ Voto registrado</p>
          <p className="text-neutral-500 text-xs mt-1">Você votou em {targetName}</p>
          <p className="text-neutral-700 text-xs mt-4">Aguardando resultado...</p>
        </div>
      </div>
    )
  }

  return (
    <div className="flex flex-1 flex-col items-center justify-center px-6 gap-6">
      <p className="text-neutral-500 text-xs uppercase tracking-widest text-center">
        🗳️ Vote em quem deve ser linchado
      </p>

      <div className="w-full max-w-sm space-y-2">
        {targets.map((t) => (
          <button
            key={t.id}
            onClick={() => handleVote(t.id)}
            disabled={busy}
            className="
              w-full py-3 px-4 rounded-xl text-sm font-medium
              bg-neutral-900 border border-neutral-800 text-neutral-300
              hover:border-red-700 hover:text-red-400
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

        {error && (
          <p className="text-red-500 text-xs text-center">{error}</p>
        )}
      </div>
  )
}
