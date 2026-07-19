'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { CARD_CATALOG, ROLE_STYLE, ROLE_TRANSLATION } from '@/lib/cards'
import { getRevealedRoleText } from '@/lib/reveal'
import { useGameState } from '@/hooks/use-room'

interface ScenarioExplanationProps {
  roomId: string
  isHost: boolean
  playerId: string | null
  onStart: () => void
  onBackToLobby: () => void
}

interface PlayerRole {
  id: string
  role: string | null
  is_host: boolean
}

export function ScenarioExplanation({
  roomId,
  isHost,
  playerId,
  onStart,
  onBackToLobby,
}: ScenarioExplanationProps) {
  const supabase = createClient()
  const [roles, setRoles] = useState<PlayerRole[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    async function load() {
      const { data, error } = await supabase
        .from('players')
        .select('id, role, is_host')
        .eq('room_id', roomId)

      if (data && !error) {
        setRoles(data as PlayerRole[])
      }
      setLoading(false)
    }
    load()
  }, [roomId])

  // Calcular composição do cenário
  const composition = new Map<string, number>()
  for (const p of roles) {
    if (p.is_host) continue
    const r = p.role ?? 'unknown'
    composition.set(r, (composition.get(r) ?? 0) + 1)
  }

  const sortedEntries = Array.from(composition.entries())
    .filter(([role]) => CARD_CATALOG.some((c) => c.id === role))
    .sort((a, b) => {
      const ca = CARD_CATALOG.find((c) => c.id === a[0])!
      const cb = CARD_CATALOG.find((c) => c.id === b[0])!
      // Aldeia → Lobisomens → Independentes
      const order = { village: 0, wolf: 1, independent: 2 }
      const oa = order[ca.team as keyof typeof order] ?? 3
      const ob = order[cb.team as keyof typeof order] ?? 3
      if (oa !== ob) return oa - ob
      return cb.points - ca.points
    })

  if (loading) {
    return (
      <div className="flex flex-1 flex-col items-center justify-center min-h-dvh">
        <p className="text-neutral-500 text-sm">Carregando cenário...</p>
      </div>
    )
  }

  return (
    <div className="flex flex-1 flex-col items-center min-h-dvh px-4 py-8 gap-6">
      <div className="text-center max-w-2xl">
        <p className="text-neutral-500 text-[10px] uppercase tracking-widest mb-2">
          Antes de começar
        </p>
        <h2 className="text-2xl font-black text-red-500 tracking-wider mb-2">
          📜 Cenário do Jogo
        </h2>
        <p className="text-neutral-400 text-sm max-w-md mx-auto">
          {isHost
            ? 'Estes são os papéis deste jogo. Explique cada um para os jogadores antes de iniciar.'
            : 'O mestre vai apresentar os papéis. Aguarde a explicação...'}
        </p>
      </div>

      <div className="w-full max-w-3xl space-y-3">
        {sortedEntries.length === 0 ? (
          <p className="text-neutral-600 text-sm text-center">
            Nenhum papel encontrado.
          </p>
        ) : (
          sortedEntries.map(([roleId, count]) => {
            const card = CARD_CATALOG.find((c) => c.id === roleId)!
            const ptName = ROLE_TRANSLATION[roleId] ?? card.name
            return (
              <div
                key={roleId}
                className={`
                  rounded-2xl border-2 p-4
                  ${ROLE_STYLE[roleId] ?? 'bg-neutral-100 text-neutral-700 border-neutral-300'}
                `}
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="flex-1">
                    <div className="flex items-center gap-2 mb-1">
                      <h3 className="font-bold text-base">
                        {card.name}
                        {ptName !== card.name && (
                          <span className="text-xs opacity-70 ml-1">({ptName})</span>
                        )}
                      </h3>
                      {count > 1 && (
                        <span className="text-[10px] font-black tracking-widest uppercase opacity-80">
                          ×{count}
                        </span>
                      )}
                    </div>
                    <p className="text-xs opacity-90 leading-relaxed">
                      {getRevealedRoleText(roleId, 'total')}
                    </p>
                  </div>
                </div>
              </div>
            )
          })
        )}
      </div>

      {isHost ? (
        <div className="w-full max-w-md space-y-2 pt-4">
          <button
            onClick={onStart}
            className="
              w-full py-4 rounded-xl text-base font-black tracking-wider
              bg-green-800/40 border-2 border-green-700/60 text-green-300
              hover:bg-green-700/50
              transition-all duration-200 cursor-pointer
            "
          >
            ▶ Iniciar Jogo
          </button>
          <button
            onClick={onBackToLobby}
            className="
              w-full py-3 rounded-xl text-sm font-medium tracking-wider
              bg-neutral-900 border border-neutral-800 text-neutral-400
              hover:bg-neutral-800
              transition-all duration-200 cursor-pointer
            "
          >
            ↩ Voltar para o Lobby
          </button>
        </div>
      ) : (
        <div className="text-center pt-4">
          <p className="text-neutral-500 text-xs uppercase tracking-widest">
            ⏳ Aguardando o mestre iniciar...
          </p>
        </div>
      )}
    </div>
  )
}
