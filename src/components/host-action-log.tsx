'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'

interface ActionEntry {
  id: string
  action_type: string
  actor_name: string
  target_name: string | null
  result: boolean | null
  created_at: string
}

interface HostActionLogProps {
  roomId: string
  turnIndex: number
}

const ACTION_LABEL: Record<string, string> = {
  werewolf_kill: '🐺 matou',
  seer_investigate: '🔮 investigou',
  witch_save: '💚 salvou',
  witch_poison: '☠️ envenenou',
}

export function HostActionLog({ roomId, turnIndex }: HostActionLogProps) {
  const [actions, setActions] = useState<ActionEntry[]>([])
  const supabase = createClient()

  useEffect(() => {
    async function fetchActions() {
      const { data: raw } = await supabase
        .from('night_actions')
        .select('id, action_type, actor_id, target_id, result, created_at')
        .eq('room_id', roomId)
        .eq('turn_index', turnIndex)
        .order('created_at', { ascending: true })

      if (!raw) return

      const entries: ActionEntry[] = []

      for (const a of raw as { id: string; action_type: string; actor_id: string; target_id: string | null; result: boolean | null; created_at: string }[]) {
        const [actorRes, targetRes] = await Promise.all([
          supabase.from('player_profiles').select('name').eq('id', a.actor_id).single(),
          a.target_id ? supabase.from('player_profiles').select('name').eq('id', a.target_id).single() : Promise.resolve({ data: null }),
        ])

        entries.push({
          id: a.id,
          action_type: a.action_type,
          actor_name: (actorRes.data as any)?.name ?? '???',
          target_name: (targetRes.data as any)?.name ?? null,
          result: a.result,
          created_at: a.created_at,
        })
      }

      setActions(entries)
    }

    fetchActions()

    const channel = supabase
      .channel(`night-actions:${roomId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'night_actions',
          filter: `room_id=eq.${roomId}`,
        },
        () => fetchActions()
      )
      .subscribe()

    return () => { supabase.removeChannel(channel) }
  }, [roomId, turnIndex])

  if (actions.length === 0) return null

  return (
    <div className="w-full max-w-sm mx-auto space-y-2 py-4 border-t border-neutral-800">
      <p className="text-neutral-600 text-[10px] uppercase tracking-widest text-center">
        📜 Histórico Noturno
      </p>
      <div className="space-y-1">
        {actions.map((a) => (
          <div
            key={a.id}
            className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-neutral-900/60 border border-neutral-800 text-xs"
          >
            <span className="text-neutral-300 font-medium truncate">
              {a.actor_name}
            </span>
            <span className="text-neutral-500 shrink-0">
              {ACTION_LABEL[a.action_type] ?? a.action_type}
            </span>
            {a.target_name && (
              <span className="text-neutral-300 font-medium truncate">
                {a.target_name}
              </span>
            )}
            {a.result !== null && (
              <span className={`shrink-0 font-bold ${a.result ? 'text-red-400' : 'text-green-400'}`}>
                {a.result ? '🐺' : '👤'}
              </span>
            )}
          </div>
        ))}
      </div>
    </div>
  )
}
