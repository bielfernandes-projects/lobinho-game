'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'

interface SeerPanelProps {
  roomId: string
  playerId: string
  turnIndex: number
}

export function SeerPanel({ roomId, playerId, turnIndex }: SeerPanelProps) {
  const [targets, setTargets] = useState<{ id: string; name: string }[]>([])
  const [result, setResult] = useState<boolean | null>(null)
  const [targetName, setTargetName] = useState('')
  const [busy, setBusy] = useState(false)
  const [done, setDone] = useState(false)
  const supabase = createClient()

  useEffect(() => {
    supabase
      .from('player_profiles')
      .select('id, name, is_alive')
      .eq('room_id', roomId)
      .then(({ data }) => {
        if (data) {
          setTargets(
            (data as any[])
              .filter((r) => r.id !== playerId && r.is_alive)
              .map((r) => ({ id: r.id, name: r.name }))
          )
        }
      })
  }, [roomId, playerId])

  async function handleInvestigate(targetId: string, name: string) {
    setBusy(true)
    setTargetName(name)

    const { data, error } = await supabase.rpc('submit_night_action', {
      p_room_id: roomId,
      p_action_type: 'seer_investigate',
      p_target_id: targetId,
    })

    if (!error && data) {
      setResult(data.result)
      setDone(true)
    }
    setBusy(false)
  }

  if (done && result !== null) {
    return (
      <div className="w-full max-w-sm text-center space-y-4">
        <p className="text-purple-500 text-sm uppercase tracking-widest font-bold">
          🔮 Vidente
        </p>
        <div
          className={`p-6 rounded-2xl border-2 ${
            result
              ? 'border-red-700 bg-red-950/20'
              : 'border-green-700 bg-green-950/20'
          }`}
        >
          <p className="text-neutral-400 text-xs mb-2">{targetName}</p>
          <p
            className={`text-lg font-bold ${
              result ? 'text-red-500' : 'text-green-500'
            }`}
          >
            {result ? '🐺 É UM LOBISOMEM' : '✅ NÃO É LOBISOMEM'}
          </p>
        </div>
      </div>
    )
  }

  return (
    <div className="w-full max-w-sm text-center space-y-4">
      <p className="text-purple-500 text-sm uppercase tracking-widest font-bold">
        🔮 Vidente
      </p>
      <p className="text-neutral-500 text-xs">Escolha alguém para investigar:</p>

      <div className="space-y-2">
        {targets.map((t) => (
          <button
            key={t.id}
            onClick={() => handleInvestigate(t.id, t.name)}
            disabled={busy}
            className="
              w-full py-3 px-4 rounded-xl text-sm font-medium
              bg-neutral-900 border border-neutral-800 text-neutral-300
              hover:border-purple-700 hover:text-purple-400
              active:bg-purple-950/20
              disabled:opacity-40
              transition-all duration-200
              cursor-pointer
            "
          >
            {t.name}
          </button>
        ))}
      </div>
    </div>
  )
}
