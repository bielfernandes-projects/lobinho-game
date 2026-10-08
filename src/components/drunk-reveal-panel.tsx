'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { CARD_CATALOG } from '@/lib/cards'

interface DrunkRevealPanelProps {
  roomId: string
  turnIndex: number
}

interface Row {
  id: string
  name: string
  role: string
  is_alive: boolean
}

// Host-only: from night 3 on, secretly pick the Drunk's real role.
export function DrunkRevealPanel({ roomId, turnIndex }: DrunkRevealPanelProps) {
  const [drunks, setDrunks] = useState<Row[]>([])
  const [role, setRole] = useState('villager')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const supabase = createClient()

  async function load() {
    try {
      const { data } = await supabase.rpc('fetch_roles_for_host', { p_room_id: roomId })
      if (data) setDrunks((data as Row[]).filter((r) => r.role === 'drunk' && r.is_alive))
    } catch {}
  }

  useEffect(() => {
    load()
  }, [roomId, turnIndex])

  if (turnIndex < 3 || drunks.length === 0) return null

  async function reveal(playerId: string) {
    setBusy(true)
    setError('')
    try {
      const { error: err } = await supabase.rpc('host_reveal_drunk', {
        p_room_id: roomId,
        p_player_id: playerId,
        p_role: role,
      })
      if (err) setError(err.message)
      else await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Erro inesperado')
    }
    setBusy(false)
  }

  return (
    <div className="w-full max-w-sm mx-auto rounded-xl border border-amber-800/50 bg-amber-950/10 p-3 space-y-2">
      <p className="text-amber-400 text-xs uppercase tracking-widest text-center">🍺 Revelar Bêbado</p>
      <select
        value={role}
        onChange={(e) => setRole(e.target.value)}
        className="w-full bg-neutral-900 border border-neutral-800 rounded-lg px-3 py-2 text-sm text-neutral-300"
      >
        {CARD_CATALOG.filter((c) => c.id !== 'drunk').map((c) => (
          <option key={c.id} value={c.id}>{c.name}</option>
        ))}
      </select>
      {drunks.map((d) => (
        <button
          key={d.id}
          onClick={() => reveal(d.id)}
          disabled={busy}
          className="w-full py-2 rounded-lg text-sm font-bold bg-amber-900/30 border border-amber-700/50 text-amber-400 disabled:opacity-40 cursor-pointer"
        >
          Revelar papel de {d.name}
        </button>
      ))}
      {error && <p className="text-red-500 text-xs text-center">{error}</p>}
    </div>
  )
}
