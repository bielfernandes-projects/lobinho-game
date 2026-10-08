'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'

export interface Target {
  id: string
  name: string
}

interface Options {
  /** the acting player: never a target of their own action */
  selfId: string
  /** leave out the player the Old Witch sent away today (day-time attacks: Marksman, Hunter) */
  excludePoxed?: boolean
}

/**
 * Valid targets for a "pick a player" action: alive, not the host, not yourself
 * (and optionally not the poxed player). The one place that rule lives.
 */
export function useTargets(roomId: string, { selfId, excludePoxed = false }: Options): Target[] {
  const [targets, setTargets] = useState<Target[]>([])

  useEffect(() => {
    const supabase = createClient()
    let cancelled = false
    ;(async () => {
      try {
        let poxedId: string | null = null
        if (excludePoxed) {
          const { data: gs } = await supabase.from('game_state').select('poxed_id').eq('room_id', roomId).single()
          poxedId = (gs as { poxed_id: string | null } | null)?.poxed_id ?? null
        }
        const { data } = await supabase
          .from('player_profiles')
          .select('id, name, is_alive, is_host')
          .eq('room_id', roomId)
        if (!data || cancelled) return
        setTargets(
          (data as { id: string; name: string; is_alive: boolean; is_host: boolean }[])
            .filter((r) => r.is_alive && !r.is_host && r.id !== selfId && r.id !== poxedId)
            .map((r) => ({ id: r.id, name: r.name }))
        )
      } catch {}
    })()
    return () => { cancelled = true }
  }, [roomId, selfId, excludePoxed])

  return targets
}
