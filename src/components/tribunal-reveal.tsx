'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'

interface VoterInfo {
  name: string
  role: string
}

interface TribunalRevealProps {
  roomId: string
  turnIndex: number
}

export function TribunalReveal({ roomId, turnIndex }: TribunalRevealProps) {
  const [yesVotes, setYesVotes] = useState<VoterInfo[]>([])
  const [noVotes, setNoVotes] = useState<VoterInfo[]>([])
  const supabase = createClient()

  useEffect(() => {
    async function load() {
      const { data } = await supabase
        .from('votes')
        .select('vote_value, voter_id')
        .eq('room_id', roomId)
        .eq('turn_index', turnIndex)

      if (!data) return

      const rows = data as { vote_value: string; voter_id: string }[]
      if (rows.length === 0) return

      const voterIds = rows.map((r) => r.voter_id)

      const { data: profiles } = await supabase
        .from('player_profiles')
        .select('id, name')
        .in('id', voterIds)

      const { data: playerRoles } = await supabase
        .from('players')
        .select('id, role')
        .in('id', voterIds)

      const nameMap = new Map<string, string>()
      if (profiles) {
        for (const p of profiles as { id: string; name: string }[]) {
          nameMap.set(p.id, p.name)
        }
      }

      const roleMap = new Map<string, string>()
      if (playerRoles) {
        for (const p of playerRoles as { id: string; role: string }[]) {
          roleMap.set(p.id, p.role)
        }
      }

      const yes: VoterInfo[] = []
      const no: VoterInfo[] = []

      for (const v of rows) {
        const name = nameMap.get(v.voter_id) ?? 'Desconhecido'
        const role = roleMap.get(v.voter_id) ?? ''
        if (v.vote_value === 'yes') yes.push({ name, role })
        else no.push({ name, role })
      }

      setYesVotes(yes)
      setNoVotes(no)
    }

    load()
  }, [roomId, turnIndex])

  const yesWeighted = yesVotes.reduce((s, v) => s + (v.role === 'mayor' ? 2 : 1), 0)
  const noWeighted = noVotes.reduce((s, v) => s + (v.role === 'mayor' ? 2 : 1), 0)

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
              ✅ SIM ({yesWeighted})
            </p>
          </div>
          <div className="space-y-1">
            {yesVotes.map((v, i) => (
              <p key={i} className="text-neutral-400 text-xs font-mono flex items-center gap-1">
                {v.name}
                {v.role === 'mayor' && (
                  <span className="text-yellow-600 text-[10px] font-bold">x2</span>
                )}
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
              ❌ NÃO ({noWeighted})
            </p>
          </div>
          <div className="space-y-1">
            {noVotes.map((v, i) => (
              <p key={i} className="text-neutral-400 text-xs font-mono flex items-center gap-1">
                {v.name}
                {v.role === 'mayor' && (
                  <span className="text-yellow-600 text-[10px] font-bold">x2</span>
                )}
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
