'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'

interface SorceressPanelProps {
  roomId: string
  playerId: string
  onDone?: () => void
}

export function SorceressPanel({ roomId, playerId, onDone }: SorceressPanelProps) {
  const [targets, setTargets] = useState<{ id: string; name: string }[]>([])
  const [resultText, setResultText] = useState('')
  const [targetName, setTargetName] = useState('')
  const [hasActed, setHasActed] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const supabase = createClient()

  useEffect(() => {
    ;(async () => {
      try {
        const { data } = await supabase
          .from('player_profiles')
          .select('id, name, is_alive, is_host')
          .eq('room_id', roomId)
        if (data) {
          setTargets(
            (data as { id: string; name: string; is_alive: boolean; is_host: boolean }[])
              .filter((r) => r.id !== playerId && r.is_alive && !r.is_host)
              .map((r) => ({ id: r.id, name: r.name }))
          )
        }
      } catch {}
    })()
  }, [roomId, playerId])

  async function handleSearch(targetId: string, name: string) {
    setBusy(true)
    setTargetName(name)
    setError('')
    try {
      const res = await supabase.rpc('execute_night_action', {
        p_room_id: roomId,
        p_action_type: 'sorceress_search',
        p_target_id: targetId,
      })
      if (res.error) {
        console.error('[SorceressPanel] RPC error:', res.error)
        setError(res.error.message)
        setBusy(false)
        return
      }
      if (res.data) {
        setResultText(res.data.is_seer ? 'É a Vidente!' : 'Não é a Vidente')
        setHasActed(true)
        onDone?.()
      }
    } catch (err) {
      console.error('[SorceressPanel] Unexpected:', err)
      setError(err instanceof Error ? err.message : 'Erro inesperado')
    }
    setBusy(false)
  }

  if (hasActed) {
    return (
      <div className="w-full max-w-sm text-center space-y-4">
        <p className="text-purple-500 text-sm uppercase tracking-widest font-bold">
          🔮 Feiticeira
        </p>
        <div
          className={`p-6 rounded-2xl border-2 ${
            resultText === 'É a Vidente!'
              ? 'border-yellow-700 bg-yellow-950/20'
              : 'border-neutral-700 bg-neutral-950/20'
          }`}
        >
          <p className="text-neutral-400 text-xs mb-2">{targetName}</p>
          <p
            className={`text-lg font-bold ${
              resultText === 'É a Vidente!' ? 'text-yellow-500' : 'text-neutral-500'
            }`}
          >
            {resultText === 'É a Vidente!' ? '👁️ É A VIDENTE' : '❌ NÃO É A VIDENTE'}
          </p>
        </div>
      </div>
    )
  }

  return (
    <div className="w-full max-w-sm text-center space-y-4">
      <p className="text-purple-500 text-sm uppercase tracking-widest font-bold">
        🔮 Feiticeira
      </p>
      <p className="text-neutral-500 text-xs">Procure pela Vidente:</p>
      <div className="space-y-2">
        {targets.map((t) => (
          <button
            key={t.id}
            onClick={() => handleSearch(t.id, t.name)}
            disabled={busy || hasActed}
            className="w-full py-3 px-4 rounded-xl text-sm font-medium bg-neutral-900 border border-neutral-800 text-neutral-300 hover:border-purple-700 hover:text-purple-400 active:bg-purple-950/20 disabled:opacity-40 transition-all duration-200 cursor-pointer"
          >
            {t.name}
          </button>
        ))}
      </div>
      {error && (
        <p className="text-red-500 text-xs text-center">{error}</p>
      )}
    </div>
  )
}
