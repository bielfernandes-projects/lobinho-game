'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { CARD_CATALOG, ROLE_LABEL } from '@/lib/cards'

interface DrunkSoberPanelProps {
  roomId: string
  onRevealed?: (role: string) => void
  onDone?: () => void
}

export function DrunkSoberPanel({ roomId, onRevealed, onDone }: DrunkSoberPanelProps) {
  const [role, setRole] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const supabase = createClient()

  async function handleReveal() {
    setBusy(true)
    setError('')
    try {
      const { data, error: err } = await supabase.rpc('drunk_sober_up', { p_room_id: roomId })
      if (err) {
        setError(err.message)
      } else {
        const r = (data as { role: string }).role
        setRole(r)
        onRevealed?.(r)
        onDone?.()
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Erro inesperado')
    }
    setBusy(false)
  }

  if (role) {
    const card = CARD_CATALOG.find((c) => c.id === role)
    return (
      <div className="w-full max-w-sm text-center space-y-3">
        <p className="text-amber-400 text-sm uppercase tracking-widest font-bold">🍺 A bebedeira passou!</p>
        <p className="text-neutral-200 text-xl font-bold">{ROLE_LABEL[role] ?? role}</p>
        {card && <p className="text-neutral-400 text-xs">{card.description}</p>}
        <p className="text-neutral-600 text-xs">Feche os olhos e aguarde o mestre.</p>
      </div>
    )
  }

  return (
    <div className="w-full max-w-sm text-center space-y-4">
      <p className="text-amber-400 text-sm uppercase tracking-widest font-bold">🍺 Bêbado</p>
      <p className="text-neutral-500 text-xs">A bebedeira passou. Descubra quem você realmente é.</p>
      <button
        onClick={handleReveal}
        disabled={busy}
        className="w-full py-3 rounded-xl text-sm font-bold bg-amber-900/30 border border-amber-700/50 text-amber-400 disabled:opacity-40 cursor-pointer"
      >
        Revelar meu papel
      </button>
      {error && <p className="text-red-500 text-xs">{error}</p>}
    </div>
  )
}
