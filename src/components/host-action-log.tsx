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
  turn_index: number
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
  witch_skip: '🧪 pulou',
  priest_bless: '🙏 abençoou',
  bodyguard_protect: '🛡️ protegeu',
  aura_investigate: '👁️ investigou aura de',
  cult_convert: '🔮 converteu',
  cupid_match: '💘 uniu',
  alpha_infect: '🐺 infectou',
  sorceress_search: '🔮 procurou a Vidente em',
  mason_recognition: '🧱 reconheceu Maçons',
}

export function HostActionLog({ roomId, turnIndex }: HostActionLogProps) {
  const [actions, setActions] = useState<ActionEntry[]>([])
  const supabase = createClient()

  useEffect(() => {
    async function fetchActions() {
      const { data: raw } = await supabase
        .from('night_actions')
        .select('id, action_type, actor_id, target_id, result, created_at, turn_index')
        .eq('room_id', roomId)
        .order('turn_index', { ascending: true })
        .order('created_at', { ascending: true })

      if (!raw) return

      const actorNames: Record<string, string> = {}
      const targetNames: Record<string, string> = {}
      const missingIds = new Set<string>()

      for (const a of raw as { id: string; action_type: string; actor_id: string; target_id: string | null; result: boolean | null; created_at: string; turn_index: number }[]) {
        missingIds.add(a.actor_id)
        if (a.target_id) missingIds.add(a.target_id)
      }

      if (missingIds.size > 0) {
        try {
          const { data: profiles, error: profilesErr } = await supabase
            .from('player_profiles')
            .select('id, name')
            .in('id', [...missingIds])

          if (profilesErr) {
            console.error('[HostActionLog] player_profiles error:', profilesErr)
          }

          if (profiles) {
            for (const p of profiles as { id: string; name: string }[]) {
              actorNames[p.id] = p.name
              targetNames[p.id] = p.name
            }
          }
        } catch (err) {
          console.error('[HostActionLog] Failed to fetch names:', err)
        }
      }

      const entries: ActionEntry[] = raw.map((a: { id: string; action_type: string; actor_id: string; target_id: string | null; result: boolean | null; created_at: string; turn_index: number }) => ({
        id: a.id,
        action_type: a.action_type,
        actor_name: actorNames[a.actor_id] ?? '???',
        target_name: a.target_id ? (targetNames[a.target_id] ?? '???') : null,
        result: a.result,
        created_at: a.created_at,
        turn_index: a.turn_index,
      }))

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
  }, [roomId])

  if (actions.length === 0) return null

  const grouped = new Map<number, ActionEntry[]>()
  for (const a of actions) {
    const list = grouped.get(a.turn_index) ?? []
    list.push(a)
    grouped.set(a.turn_index, list)
  }

  const sortedTurns = [...grouped.keys()].sort((a, b) => a - b)

  return (
    <div className="w-full max-w-sm mx-auto space-y-4 py-4 border-t border-neutral-800">
      <p className="text-neutral-600 text-[10px] uppercase tracking-widest text-center">
        📜 Histórico Noturno
      </p>
      {sortedTurns.map((turn) => {
        const turnActions = grouped.get(turn)!
        const cupidEntry = findCupidPair(turnActions)
        const otherActions = turnActions.filter(a => a.action_type !== 'cupid_match')

        return (
          <div key={turn} className="space-y-1">
            {sortedTurns.length > 1 && (
              <p className="text-neutral-700 text-[10px] uppercase tracking-widest px-2">
                Noite {turn + 1}
              </p>
            )}
            <div className="space-y-1">
              {cupidEntry && (
                <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-neutral-900/60 border border-neutral-800 text-xs">
                  <span className="text-neutral-300 font-medium truncate">
                    {cupidEntry.actor_name}
                  </span>
                  <span className="text-neutral-500 shrink-0">
                    {ACTION_LABEL.cupid_match}
                  </span>
                  <span className="text-neutral-300 font-medium truncate">
                    {cupidEntry.targets[0]}
                  </span>
                  <span className="text-neutral-500">e</span>
                  <span className="text-neutral-300 font-medium truncate">
                    {cupidEntry.targets[1]}
                  </span>
                </div>
              )}
              {otherActions.map((a) => (
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
      })}
    </div>
  )
}

function findCupidPair(actions: ActionEntry[]): { actor_name: string; targets: [string, string] } | null {
  const cupids = actions.filter(a => a.action_type === 'cupid_match')
  if (cupids.length < 2) return null
  const targets = [cupids[0].target_name!, cupids[1].target_name!]
  return { actor_name: cupids[0].actor_name, targets: targets as [string, string] }
}
