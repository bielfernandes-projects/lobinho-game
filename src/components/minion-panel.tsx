'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'

interface MinionPanelProps {
  roomId: string
  onDone?: () => void
}

export function MinionPanel({ roomId, onDone }: MinionPanelProps) {
  const [wolves, setWolves] = useState<{ id: string; name: string }[]>([])
  const [done, setDone] = useState(false)
  const supabase = createClient()

  useEffect(() => {
    ;(async () => {
      try {
        const { data } = await supabase.rpc('get_wolves_for_sorceress', { p_room_id: roomId })
        if (data) setWolves(data as { id: string; name: string }[])
      } catch {}
    })()
  }, [roomId])

  return (
    <div className="w-full max-w-sm text-center space-y-4">
      <p className="text-red-500 text-sm uppercase tracking-widest font-bold">😈 Lacaio</p>
      <div className="p-3 rounded-xl border border-red-900 bg-red-950/20 text-left">
        <p className="text-red-400 text-xs uppercase tracking-widest mb-1">🐺 Os lobos</p>
        {wolves.map((w) => (
          <p key={w.id} className="text-sm text-neutral-200">{w.name}</p>
        ))}
      </div>
      <button
        onClick={() => { setDone(true); onDone?.() }}
        disabled={done}
        className="w-full py-3 rounded-xl text-sm font-medium bg-neutral-900 border border-neutral-800 text-neutral-300 hover:border-red-700 disabled:opacity-40 cursor-pointer"
      >
        Entendi
      </button>
    </div>
  )
}
