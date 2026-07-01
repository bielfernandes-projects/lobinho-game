'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'

interface TribunalRevealProps {
  roomId: string
  turnIndex: number
}

export function TribunalReveal({ roomId, turnIndex }: TribunalRevealProps) {
  const [yesVotes, setYesVotes] = useState<{ name: string }[]>([])
  const [noVotes, setNoVotes] = useState<{ name: string }[]>([])
  const supabase = createClient()

  useEffect(() => {
    async function load() {
      const { data } = await supabase
        .from('votes')
        .select('vote_value, voter_id')
        .eq('room_id', roomId)
        .eq('turn_index', turnIndex)

      if (!data) return

      const yes: { name: string }[] = []
      const no: { name: string }[] = []

      for (const v of data as { vote_value: string; voter_id: string }[]) {
        const { data: profile } = await supabase
          .from('player_profiles')
          .select('name')
          .eq('id', v.voter_id)
          .single()

        const name = (profile as any)?.name ?? 'Desconhecido'
        if (v.vote_value === 'yes') yes.push({ name })
        else no.push({ name })
      }

      setYesVotes(yes)
      setNoVotes(no)
    }

    load()
  }, [roomId, turnIndex])

  return (
    <div className="flex flex-1 flex-col items-center px-6 gap-4 mt-4">
      <p className="text-neutral-500 text-xs uppercase tracking-widest text-center">
        📊 Resultado da Votação
      </p>

      <div className="w-full max-w-sm space-y-4">
        {/* Votos SIM */}
        <div className="rounded-xl border border-red-800/40 bg-red-950/10 p-4 space-y-2">
          <div className="flex items-center justify-between">
            <p className="text-red-400 text-sm font-bold uppercase tracking-wider">
              ✅ SIM ({yesVotes.length})
            </p>
          </div>
          <div className="space-y-1">
            {yesVotes.map((v, i) => (
              <p key={i} className="text-neutral-400 text-xs font-mono">
                {v.name}
              </p>
            ))}
            {yesVotes.length === 0 && (
              <p className="text-neutral-700 text-xs">Nenhum voto</p>
            )}
          </div>
        </div>

        {/* Votos NÃO */}
        <div className="rounded-xl border border-emerald-800/40 bg-emerald-950/10 p-4 space-y-2">
          <div className="flex items-center justify-between">
            <p className="text-emerald-400 text-sm font-bold uppercase tracking-wider">
              ❌ NÃO ({noVotes.length})
            </p>
          </div>
          <div className="space-y-1">
            {noVotes.map((v, i) => (
              <p key={i} className="text-neutral-400 text-xs font-mono">
                {v.name}
              </p>
            ))}
            {noVotes.length === 0 && (
              <p className="text-neutral-700 text-xs">Nenhum voto</p>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
