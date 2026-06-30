'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'

interface RoleRow {
  id: string
  role: string
}

interface PlayerProfile {
  id: string
  name: string
  is_alive: boolean
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
  const [rows, setRows] = useState<{ id: string; name: string; role: string; isAlive: boolean }[]>([])
  const [collapsed, setCollapsed] = useState(false)
  const supabase = createClient()

  useEffect(() => {
    if (!isHost) return

    async function load() {
      const [rolesRes, profilesRes] = await Promise.all([
        supabase.rpc('get_player_roles', { p_room_id: roomId }),
        supabase.from('player_profiles').select('id, name, is_alive').eq('room_id', roomId),
      ])

      const roles = (rolesRes.data ?? []) as RoleRow[]
      const profiles = (profilesRes.data ?? []) as PlayerProfile[]

      const merged = roles.map((r) => {
        const profile = profiles.find((p) => p.id === r.id)
        return {
          id: r.id,
          name: profile?.name ?? '???',
          role: r.role,
          isAlive: profile?.is_alive ?? true,
        }
      })

      setRows(merged)
    }

    load()

    const channel = supabase
      .channel(`host-roles:${roomId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'players', filter: `room_id=eq.${roomId}` }, load)
      .subscribe()

    return () => { supabase.removeChannel(channel) }
  }, [roomId, isHost])

  if (!isHost || rows.length === 0) return null

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
          <div className="divide-y divide-neutral-800">
            {rows.map((r) => (
              <div key={r.id} className="flex items-center gap-3 px-4 py-2.5">
                <span
                  className={`w-2 h-2 rounded-full shrink-0 ${
                    r.isAlive ? 'bg-green-500 shadow-[0_0_6px_rgba(34,197,94,0.5)]' : 'bg-red-800'
                  }`}
                />
                <span className={`flex-1 text-sm font-medium truncate ${r.isAlive ? 'text-neutral-200' : 'text-neutral-600 line-through'}`}>
                  {r.name}
                </span>
                <span className={`text-xs tracking-wider shrink-0 ${r.role === 'moderator' ? 'text-yellow-500' : r.role === 'werewolf' ? 'text-red-400' : r.role === 'seer' ? 'text-sky-400' : r.role === 'witch' ? 'text-emerald-400' : 'text-neutral-500'}`}>
                  {ROLE_LABEL[r.role] ?? r.role}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
