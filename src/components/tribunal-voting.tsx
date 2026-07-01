'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'

interface TribunalVotingProps {
  roomId: string
  playerId: string
  isAlive: boolean
  isAccused: boolean
}

export function TribunalVoting({ roomId, playerId, isAlive, isAccused }: TribunalVotingProps) {
  const [voted, setVoted] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const supabase = createClient()

  if (!isAlive) {
    return (
      <div className="flex flex-1 flex-col items-center justify-center px-6">
        <p className="text-neutral-700 text-lg font-bold">💀 Você está morto</p>
        <p className="text-neutral-800 text-xs mt-2">Assista o desenrolar...</p>
      </div>
    )
  }

  if (isAccused) {
    return (
      <div className="flex flex-1 flex-col items-center justify-center px-6">
        <p className="text-neutral-500 text-xs uppercase tracking-widest text-center">
          ⏳ Aguardando votos da vila...
        </p>
      </div>
    )
  }

  if (voted) {
    return (
      <div className="flex flex-1 flex-col items-center justify-center px-6">
        <p className="text-green-600 text-sm font-semibold">✅ Voto registrado</p>
        <p className="text-neutral-500 text-xs mt-2">Aguardando resultado...</p>
      </div>
    )
  }

  async function handleVote(value: 'yes' | 'no') {
    setBusy(true)
    setError('')
    const { error: e } = await supabase.rpc('submit_tribunal_vote', {
      p_room_id: roomId,
      p_vote_value: value,
    })
    if (e) {
      setError(e.message)
      setBusy(false)
      return
    }
    setVoted(true)
    setBusy(false)
  }

  return (
    <div className="flex flex-1 flex-col items-center justify-center px-6 gap-4">
      <p className="text-neutral-500 text-xs uppercase tracking-widest text-center">
        🗳️ Condenar ou Absolver?
      </p>

      <div className="w-full max-w-sm space-y-3">
        <button
          onClick={() => handleVote('yes')}
          disabled={busy}
          className="w-full py-5 rounded-2xl font-bold text-lg tracking-wider bg-red-900/30 border-2 border-red-700/50 text-red-400 hover:bg-red-800/40 active:bg-red-800/60 disabled:opacity-40 transition-all duration-200 cursor-pointer"
        >
          ✅ Votar SIM (Linchamento)
        </button>

        <button
          onClick={() => handleVote('no')}
          disabled={busy}
          className="w-full py-5 rounded-2xl font-bold text-lg tracking-wider bg-emerald-900/30 border-2 border-emerald-700/50 text-emerald-400 hover:bg-emerald-800/40 active:bg-emerald-800/60 disabled:opacity-40 transition-all duration-200 cursor-pointer"
        >
          ❌ Votar NÃO (Absolvição)
        </button>
      </div>

      {error && <p className="text-red-500 text-xs text-center">{error}</p>}
    </div>
  )
}
