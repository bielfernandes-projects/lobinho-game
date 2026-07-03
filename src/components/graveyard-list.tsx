'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { getRevealedRoleText, type RevealMode } from '@/lib/reveal'

interface GraveyardPlayer {
  id: string
  name: string
  role: string
}

interface GraveyardListProps {
  roomId: string
  revealMode: RevealMode
}

export function GraveyardList({ roomId, revealMode }: GraveyardListProps) {
  const [deadPlayers, setDeadPlayers] = useState<GraveyardPlayer[]>([])
  const [open, setOpen] = useState(false)
  const supabase = createClient()

  useEffect(() => {
    async function poll() {
      const { data } = await supabase.rpc('get_graveyard_info', { p_room_id: roomId })
      if (data) {
        setDeadPlayers((data as any[]) ?? [])
      }
    }
    poll()
    const iv = setInterval(poll, 5000)
    return () => clearInterval(iv)
  }, [roomId, supabase])

  if (deadPlayers.length === 0) return null

  return (
    <div className="w-full max-w-sm mx-auto px-6 pb-4">
      <button
        onClick={() => setOpen(!open)}
        className="w-full flex items-center gap-2 px-3 py-2 rounded-lg bg-neutral-900/40 border border-neutral-800 text-neutral-500 hover:text-neutral-400 hover:bg-neutral-800/40 transition-all duration-200 cursor-pointer text-xs"
      >
        <span>☠️ Cemitério ({deadPlayers.length})</span>
        <span className="ml-auto">{open ? '▲' : '▼'}</span>
      </button>
      {open && (
        <div className="mt-2 space-y-1.5">
          {deadPlayers.map((p) => (
            <div
              key={p.id}
              className="flex items-center justify-between px-3 py-2 rounded-lg bg-neutral-900/20 border border-neutral-800/50"
            >
              <span className="text-neutral-400 text-sm">{p.name}</span>
              <span className="text-neutral-600 text-[10px] uppercase tracking-wider">
                {getRevealedRoleText(p.role, revealMode)}
              </span>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
