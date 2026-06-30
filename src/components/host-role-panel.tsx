'use client'

import { useEffect, useState, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'

interface RoleRow {
  id: string
  name: string
  role: string
  is_alive: boolean
  has_viewed_card: boolean
}

interface HostRolePanelProps {
  roomId: string
  isHost: boolean
}

const ROLE_LABEL: Record<string, string> = {
  werewolf: '🐺 Lobisomem',
  seer: '🔮 Vidente',
  witch: '🧙 Bruxa',
  villager: '🌿 Aldeão',
  moderator: '🎙️ Mestre',
}

export function HostRolePanel({ roomId, isHost }: HostRolePanelProps) {
  const [rows, setRows] = useState<RoleRow[]>([])
  const [collapsed, setCollapsed] = useState(false)
  const [error, setError] = useState('')
  const supabase = createClient()

  const fetchPlayers = useCallback(async () => {
    if (!isHost) return

    setError('')

    const { data, error: rpcError } = await supabase.rpc('get_player_roles', { p_room_id: roomId })

    if (rpcError) {
      console.error('get_player_roles error:', rpcError)
      setError(rpcError.message)
      return
    }

    if (data) {
      setRows(data as RoleRow[])
    }
  }, [roomId, isHost])

  useEffect(() => {
    if (!isHost) return

    fetchPlayers()

    const handleChange = () => {
      fetchPlayers().catch((e) => {
        console.error('Realtime refresh error:', e)
        setError(e instanceof Error ? e.message : 'Erro ao atualizar lista')
      })
    }

    const channel = supabase
      .channel(`host-roles:${roomId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'players', filter: `room_id=eq.${roomId}` }, handleChange)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'game_state', filter: `room_id=eq.${roomId}` }, handleChange)
      .subscribe()

    return () => { supabase.removeChannel(channel) }
  }, [roomId, isHost, fetchPlayers])

  if (!isHost) return null

  return (
    <div className="w-full max-w-sm mx-auto">
      <button
        onClick={() => setCollapsed((c) => !c)}
        className="w-full flex items-center justify-between px-4 py-2 rounded-xl bg-neutral-900/80 border border-neutral-800 text-xs uppercase tracking-widest text-neutral-500 hover:text-neutral-400 transition-colors cursor-pointer mb-2"
      >
        <span>🎙️ Painel do Mestre</span>
        <span className="text-neutral-600">{collapsed ? '▼' : '▲'}</span>
      </button>

      {!collapsed && (
        <div className="rounded-xl border border-neutral-800 bg-neutral-900/60 overflow-hidden">
          {error && (
            <div className="px-4 py-2 bg-red-950/30 border-b border-red-900/30">
              <p className="text-red-500 text-xs">{error}</p>
            </div>
          )}
          <div className="divide-y divide-neutral-800">
            {rows.map((r) => (
              <div key={r.id} className="flex items-center gap-3 px-4 py-2.5">
                <span
                  className={`w-2 h-2 rounded-full shrink-0 ${
                    r.is_alive ? 'bg-green-500 shadow-[0_0_6px_rgba(34,197,94,0.5)]' : 'bg-red-800'
                  }`}
                />
                <span className={`flex-1 text-sm font-medium truncate ${r.is_alive ? 'text-neutral-200' : 'text-neutral-600 line-through'}`}>
                  {r.has_viewed_card && <span className="mr-1 opacity-70">👁</span>}
                  {r.name}
                </span>
                <span className={`text-xs tracking-wider shrink-0 ${r.role === 'moderator' ? 'text-yellow-500' : r.role === 'werewolf' ? 'text-red-400' : r.role === 'seer' ? 'text-sky-400' : r.role === 'witch' ? 'text-emerald-400' : 'text-neutral-500'}`}>
                  {ROLE_LABEL[r.role] ?? r.role}
                </span>
              </div>
            ))}
            {rows.length === 0 && !error && (
              <div className="px-4 py-6 text-center">
                <p className="text-neutral-700 text-xs">Nenhum jogador encontrado</p>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
