'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'

interface MartyrPanelProps {
  roomId: string
  martyrId: string | null
  martyrName: string | null
  canVolunteer: boolean
}

// Shown during the tribunal "reveal" step: public notice once the Martyr volunteers,
// plus the volunteer button for the alive Martyr.
export function MartyrPanel({ roomId, martyrId, martyrName, canVolunteer }: MartyrPanelProps) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const supabase = createClient()

  async function handleVolunteer() {
    setBusy(true)
    setError('')
    try {
      const { error: err } = await supabase.rpc('martyr_volunteer', { p_room_id: roomId })
      if (err) setError(err.message)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Erro inesperado')
    }
    setBusy(false)
  }

  if (martyrId) {
    return (
      <p className="text-amber-400 text-sm text-center font-semibold">
        ⚖️ {martyrName ?? 'O Mártir'} se ofereceu para morrer no lugar do acusado!
      </p>
    )
  }

  if (!canVolunteer) return null

  return (
    <div className="w-full max-w-sm mx-auto text-center space-y-2">
      <button
        onClick={handleVolunteer}
        disabled={busy}
        className="w-full py-3 rounded-xl text-sm font-bold bg-amber-900/30 border border-amber-700/50 text-amber-400 hover:bg-amber-800/40 disabled:opacity-40 cursor-pointer"
      >
        ⚖️ Morrer no lugar do acusado
      </button>
      {error && <p className="text-red-500 text-xs">{error}</p>}
    </div>
  )
}
