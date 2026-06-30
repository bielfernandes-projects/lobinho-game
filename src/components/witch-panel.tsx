'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'

interface WitchPanelProps {
  roomId: string
  playerId: string
  turnIndex: number
  victimName: string | null
}

type Step = 'save' | 'poison' | 'done'

export function WitchPanel({ roomId, playerId, turnIndex, victimName }: WitchPanelProps) {
  const [step, setStep] = useState<Step>('save')
  const [targets, setTargets] = useState<{ id: string; name: string; isHost: boolean }[]>([])
  const [poisonBusy, setPoisonBusy] = useState(false)
  const [usedLife, setUsedLife] = useState(false)
  const [usedDeath, setUsedDeath] = useState(false)
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
              .filter((r) => r.is_alive)
              .map((r) => ({ id: r.id, name: r.name, isHost: r.is_host }))
          )
        }
      })

    supabase
      .from('players')
      .select('has_used_life_potion, has_used_death_potion')
      .eq('id', playerId)
      .single()
      .then(({ data }) => {
        if (data) {
          setUsedLife(data.has_used_life_potion)
          setUsedDeath(data.has_used_death_potion)
        }
      })
  }, [roomId, playerId])

  async function handleSave(save: boolean) {
    if (save && !usedLife) {
      const { error } = await supabase.rpc('submit_night_action', {
        p_room_id: roomId,
        p_action_type: 'witch_save',
        p_target_id: null,
      })
      if (error) return
    }
    setStep('poison')
  }

  async function handlePoison(targetId: string | null) {
    setPoisonBusy(true)

    if (targetId && !usedDeath) {
      const { error } = await supabase.rpc('submit_night_action', {
        p_room_id: roomId,
        p_action_type: 'witch_poison',
        p_target_id: targetId,
      })
      if (error) { setPoisonBusy(false); return }
    }

    setStep('done')
    setPoisonBusy(false)
  }

  if (step === 'done') {
    return (
      <div className="text-center">
        <p className="text-green-600 text-sm font-semibold">✅ Decisão registrada</p>
        <p className="text-neutral-700 text-xs mt-1">Aguardando o dia...</p>
      </div>
    )
  }

  return (
    <div className="w-full max-w-sm text-center space-y-4">
      <p className="text-emerald-500 text-sm uppercase tracking-widest font-bold">
        🧪 Bruxa
      </p>

      {step === 'save' && (
        <>
          <p className="text-neutral-500 text-xs">
            Alguém foi atacado durante a noite:
          </p>

          {victimName ? (
            <div className="py-4">
              <p className="text-red-400 text-lg font-black tracking-wider">
                ☠️ {victimName}
              </p>
            </div>
          ) : (
            <div className="py-4">
              <p className="text-green-500 text-sm font-bold">
                Ninguém foi atacado
              </p>
            </div>
          )}

          <div className="flex gap-3 justify-center">
            {victimName && !usedLife && (
              <button
                onClick={() => handleSave(true)}
                className="
                  px-6 py-3 rounded-xl text-sm font-bold
                  bg-green-900/30 border border-green-700/50 text-green-400
                  hover:bg-green-800/40 active:bg-green-900/50
                  transition-all duration-200 cursor-pointer
                "
              >
                💚 Salvar
              </button>
            )}

            <button
              onClick={() => handleSave(false)}
              className="
                px-6 py-3 rounded-xl text-sm font-medium
                bg-neutral-900 border border-neutral-800 text-neutral-400
                hover:border-neutral-700 active:bg-neutral-800
                transition-all duration-200 cursor-pointer
              "
            >
              {victimName ? 'Deixar Morrer' : 'Continuar'}
            </button>
          </div>

          {usedLife && victimName && (
            <p className="text-neutral-600 text-[10px] uppercase tracking-wider">
              Poção da vida já usada
            </p>
          )}
        </>
      )}

      {step === 'poison' && (
        <>
          <p className="text-neutral-500 text-xs">
            Quer envenenar alguém?
          </p>

          <div className="space-y-2">
            {targets
              .filter((t) => t.id !== playerId && !t.isHost)
              .map((t) => (
                <button
                  key={t.id}
                  onClick={() => handlePoison(t.id)}
                  disabled={poisonBusy || usedDeath}
                  className="
                    w-full py-3 px-4 rounded-xl text-sm font-medium
                    bg-neutral-900 border border-neutral-800 text-neutral-300
                    hover:border-purple-700 hover:text-purple-400
                    active:bg-purple-950/20
                    disabled:opacity-30 disabled:cursor-not-allowed
                    transition-all duration-200 cursor-pointer
                  "
                >
                  {t.name}
                </button>
              ))}
          </div>

          <button
            onClick={() => handlePoison(null)}
            disabled={poisonBusy}
            className="
              text-neutral-600 text-xs hover:text-neutral-400
              transition-colors cursor-pointer disabled:opacity-30
            "
          >
            {usedDeath ? 'Poção já usada' : 'Pular (não envenenar)'}
          </button>
        </>
      )}
    </div>
  )
}
