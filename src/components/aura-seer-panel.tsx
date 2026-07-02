'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'

interface AuraSeerPanelProps {
  roomId: string
  playerId: string
  turnIndex: number
  onDone?: () => void
}

export function AuraSeerPanel({ roomId, playerId, turnIndex, onDone }: AuraSeerPanelProps) {
  const [targets, setTargets] = useState<{ id: string; name: string }[]>([])
  const [resultText, setResultText] = useState('')
  const [targetName, setTargetName] = useState('')
  const [busy, setBusy] = useState(false)
  const [showResult, setShowResult] = useState(false)
  const [error, setError] = useState('')
  const supabase = createClient()

  useEffect(() => {
    supabase
      .from('player_profiles')
      .select('id, name, is_alive, is_host')
      .eq('room_id', roomId)
      .then(({ data }) => {
        if (data) {
          setTargets(
            (data as any[])
              .filter((r) => r.id !== playerId && r.is_alive && !r.is_host)
              .map((r) => ({ id: r.id, name: r.name }))
          )
        }
      })
  }, [roomId, playerId])

  async function handleInvestigate(targetId: string, name: string) {
    setBusy(true)
    setTargetName(name)
    setError('')
    try {
      const res = await supabase.rpc('execute_night_action', {
        p_room_id: roomId,
        p_action_type: 'aura_investigate',
        p_target_id: targetId,
      })
      if (res.error) {
        console.error('[AuraSeerPanel] RPC error:', res.error)
        setError(res.error.message)
        setBusy(false)
        return
      }
      if (res.data) {
        setResultText(res.data.has_special_role ? 'Tem um Papel Especial!' : 'É um cidadão comum')
        setShowResult(true)
        onDone?.()
      }
    } catch (err) {
      console.error('[AuraSeerPanel] Unexpected:', err)
      setError(err instanceof Error ? err.message : 'Erro inesperado')
    }
    setBusy(false)
  }

  if (showResult) {
    return (
      <div className="w-full max-w-sm text-center space-y-4">
        <p className="text-pink-500 text-sm uppercase tracking-widest font-bold">
          👁️ Vidente de Aura
        </p>
        <div
          className={`p-6 rounded-2xl border-2 ${
            resultText === 'Tem um Papel Especial!'
              ? 'border-purple-700 bg-purple-950/20'
              : 'border-green-700 bg-green-950/20'
          }`}
        >
          <p className="text-neutral-400 text-xs mb-2">{targetName}</p>
          <p
            className={`text-lg font-bold ${
              resultText === 'Tem um Papel Especial!' ? 'text-purple-500' : 'text-green-500'
            }`}
          >
            {resultText === 'Tem um Papel Especial!' ? '✨ TEM UM PAPEL ESPECIAL' : '✅ É UM CIDADÃO COMUM'}
          </p>
        </div>
      </div>
    )
  }

  return (
    <div className="w-full max-w-sm text-center space-y-4">
      <p className="text-pink-500 text-sm uppercase tracking-widest font-bold">
        👁️ Vidente de Aura
      </p>
      <p className="text-neutral-500 text-xs">Escolha alguém para ler a aura:</p>
      <div className="space-y-2">
        {targets.map((t) => (
          <button
            key={t.id}
            onClick={() => handleInvestigate(t.id, t.name)}
            disabled={busy || showResult}
            className="
              w-full py-3 px-4 rounded-xl text-sm font-medium
              bg-neutral-900 border border-neutral-800 text-neutral-300
              hover:border-pink-700 hover:text-pink-400
              active:bg-pink-950/20
              disabled:opacity-40
              transition-all duration-200
              cursor-pointer
            "
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
