'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import type { RoomProfile } from '@/hooks/use-room'

interface WerewolfPanelProps {
  roomId: string
  playerId: string
  turnIndex: number
  isFirstNight?: boolean
  isAlpha?: boolean
  alphaHasPower?: boolean
  wolvesFrenzy?: boolean
  onDone?: () => void
}

export function WerewolfPanel({
  roomId,
  playerId,
  turnIndex,
  isFirstNight = false,
  isAlpha = false,
  alphaHasPower = false,
  wolvesFrenzy = false,
  onDone,
}: WerewolfPanelProps) {
  const [wolves, setWolves] = useState<RoomProfile[]>([])
  const [targets, setTargets] = useState<RoomProfile[]>([])
  const [hasActed, setHasActed] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [selectedTargets, setSelectedTargets] = useState<string[]>([])
  const [infectTarget, setInfectTarget] = useState(false)
  const supabase = createClient()

  useEffect(() => {
    async function load() {
      const { data: all } = await supabase
        .from('player_profiles')
        .select('id, name, is_host, is_alive, has_viewed_card, user_id')
        .eq('room_id', roomId)

      if (!all) return

      const profiles = (all as any[]).map((r) => ({
        id: r.id,
        name: r.name,
        isHost: r.is_host,
        isAlive: r.is_alive,
        hasViewedCard: r.has_viewed_card,
        userId: r.user_id,
      }))

      const { data: wolvesData } = await supabase.rpc('get_werewolf_teammates', {
        p_room_id: roomId,
      })

      if (wolvesData) {
        const wolfIds = new Set(
          (wolvesData as { id: string; name: string }[]).map((w) => w.id)
        )

        setWolves(profiles.filter((p) => wolfIds.has(p.id)))
        setTargets(profiles.filter((p) => p.isAlive && !wolfIds.has(p.id) && !p.isHost && p.id !== playerId))
      }
    }

    load()
  }, [roomId, playerId, wolvesFrenzy])

  const expectedTargets = wolvesFrenzy ? 2 : 1

  async function submitKill(targetId: string, shouldInfect: boolean) {
    const { error: rpcErr } = await supabase.rpc('execute_night_action', {
      p_room_id: roomId,
      p_action_type: 'werewolf_kill',
      p_target_id: targetId,
    })
    if (rpcErr) throw new Error(rpcErr.message)

    if (shouldInfect) {
      const { error: infectErr } = await supabase.rpc('execute_night_action', {
        p_room_id: roomId,
        p_action_type: 'alpha_infect',
        p_target_id: targetId,
      })
      if (infectErr) throw new Error(infectErr.message)
    }
  }

  async function handleNormalKill(targetId: string) {
    setBusy(true)
    setError('')
    try {
      await submitKill(targetId, infectTarget)
      setHasActed(true)
      onDone?.()
    } catch (err) {
      console.error('[WerewolfPanel] RPC error:', err)
      setError(err instanceof Error ? err.message : 'Erro inesperado')
    }
    setBusy(false)
  }

  async function handleFrenzyConfirm() {
    if (selectedTargets.length !== 2) return
    setBusy(true)
    setError('')
    try {
      await submitKill(selectedTargets[0], infectTarget)
      await submitKill(selectedTargets[1], false)
      setHasActed(true)
      onDone?.()
    } catch (err) {
      console.error('[WerewolfPanel] RPC error:', err)
      setError(err instanceof Error ? err.message : 'Erro inesperado')
    }
    setBusy(false)
  }

  async function handleFirstNightConfirm() {
    setBusy(true)
    setError('')
    try {
      const { error: rpcErr } = await supabase.rpc('execute_night_action', {
        p_room_id: roomId,
        p_action_type: 'werewolf_kill',
        p_target_id: null,
      })
      if (rpcErr) {
        console.error('[WerewolfPanel] RPC error:', rpcErr)
        setError(rpcErr.message)
        setBusy(false)
        return
      }
      setHasActed(true)
      onDone?.()
    } catch (err) {
      console.error('[WerewolfPanel] Unexpected:', err)
      setError(err instanceof Error ? err.message : 'Erro inesperado')
    }
    setBusy(false)
  }

  function toggleTargetSelection(id: string) {
    setSelectedTargets((prev) => {
      if (prev.includes(id)) {
        return prev.filter((t) => t !== id)
      }
      if (prev.length >= 2) return prev
      return [...prev, id]
    })
  }

  if (hasActed) {
    return (
      <div className="w-full max-w-sm text-center space-y-2">
        <p className="text-neutral-500 text-sm font-semibold">✅ Ação Registrada</p>
        <p className="text-neutral-700 text-xs">Aguarde a noite passar...</p>
      </div>
    )
  }

  if (isFirstNight) {
    return (
      <div className="w-full max-w-sm text-center space-y-4">
        <p className="text-red-500 text-sm uppercase tracking-widest font-bold">
          🐺 Lobisomens
        </p>

        {wolves.length > 1 && (
          <div>
            <p className="text-neutral-600 text-[10px] uppercase tracking-wider mb-2">
              Seus aliados
            </p>
            <div className="flex flex-wrap justify-center gap-2">
              {wolves
                .filter((w) => w.id !== playerId)
                .map((w) => (
                  <span
                    key={w.id}
                    className="px-3 py-1 rounded-full bg-red-950/40 border border-red-900/30 text-red-400 text-xs"
                  >
                    {w.name}
                  </span>
                ))}
            </div>
          </div>
        )}

        <p className="text-neutral-400 text-sm leading-relaxed">
          🐺 Primeira Noite: Os lobisomens apenas abrem os olhos e se reconhecem em silêncio. Eles não matam ninguém hoje.
        </p>

        <button
          onClick={handleFirstNightConfirm}
          disabled={busy}
          className="w-full py-3 px-4 rounded-xl text-sm font-medium bg-neutral-900 border border-neutral-800 text-neutral-300 hover:border-red-800 hover:text-red-400 disabled:opacity-40 transition-all duration-200 cursor-pointer"
        >
          Confirmar
        </button>

        {error && (
          <p className="text-red-500 text-xs text-center">{error}</p>
        )}
      </div>
    )
  }

  return (
    <div className="w-full max-w-sm text-center space-y-4">
      <p className="text-red-500 text-sm uppercase tracking-widest font-bold">
        🐺 Lobisomens
      </p>

      {wolvesFrenzy && (
        <p className="text-yellow-400 text-xs uppercase tracking-wider font-bold animate-pulse">
          🔥 FRENESI — Matem 2 vítimas esta noite!
        </p>
      )}

      {wolves.length > 1 && (
        <div>
          <p className="text-neutral-600 text-[10px] uppercase tracking-wider mb-2">
            Seus aliados
          </p>
          <div className="flex flex-wrap justify-center gap-2">
            {wolves
              .filter((w) => w.id !== playerId)
              .map((w) => (
                <span
                  key={w.id}
                  className="px-3 py-1 rounded-full bg-red-950/40 border border-red-900/30 text-red-400 text-xs"
                >
                  {w.name}
                </span>
              ))}
          </div>
        </div>
      )}

      <div>
        {wolvesFrenzy ? (
          <>
            <p className="text-neutral-500 text-xs mb-3">
              {selectedTargets.length === 0
                ? 'Selecione o 1º alvo:'
                : selectedTargets.length === 1
                  ? 'Selecione o 2º alvo:'
                  : 'Alvos definidos:'}
            </p>
            <div className="space-y-2">
              {targets.map((t) => {
                const isSelected = selectedTargets.includes(t.id)
                return (
                  <button
                    key={t.id}
                    onClick={() => toggleTargetSelection(t.id)}
                    disabled={busy}
                    className={`
                      w-full py-3 px-4 rounded-xl text-sm font-medium
                      transition-all duration-200 cursor-pointer
                      ${isSelected
                        ? 'bg-red-900/30 border border-red-700/50 text-red-300'
                        : 'bg-neutral-900 border border-neutral-800 text-neutral-300 hover:border-red-800 hover:text-red-400'
                      }
                      disabled:opacity-40
                    `}
                  >
                    {isSelected ? `✓ ${t.name}` : t.name}
                  </button>
                )
              })}
            </div>

            {isAlpha && alphaHasPower && selectedTargets.length >= 1 && (
              <label className="flex items-center justify-center gap-2 mt-3 px-3 py-2 rounded-lg bg-neutral-900/40 border border-neutral-800 cursor-pointer hover:bg-neutral-800/40 transition-colors">
                <input
                  type="checkbox"
                  checked={infectTarget}
                  onChange={(e) => setInfectTarget(e.target.checked)}
                  className="accent-red-600 cursor-pointer"
                />
                <span className="text-neutral-400 text-xs">
                  🐺 Infectar {targets.find((t) => t.id === selectedTargets[0])?.name ?? 'o 1º alvo'} (Poder do Lobo Alfa)
                </span>
              </label>
            )}

            {selectedTargets.length === 2 && (
              <button
                onClick={handleFrenzyConfirm}
                disabled={busy}
                className="w-full mt-3 py-3 px-4 rounded-xl text-sm font-bold bg-red-900/30 border border-red-700/50 text-red-400 hover:bg-red-800/40 disabled:opacity-40 transition-all duration-200 cursor-pointer"
              >
                {busy ? 'Atacando...' : `⚔️ Atacar ${selectedTargets.length} alvos`}
              </button>
            )}
          </>
        ) : (
          <>
            <p className="text-neutral-500 text-xs mb-3">Escolha a vítima:</p>
            <div className="space-y-2">
              {targets.map((t) => (
                <button
                  key={t.id}
                  onClick={() => handleNormalKill(t.id)}
                  disabled={busy}
                  className="
                    w-full py-3 px-4 rounded-xl text-sm font-medium
                    bg-neutral-900 border border-neutral-800 text-neutral-300
                    hover:border-red-800 hover:text-red-400
                    active:bg-red-950/20
                    disabled:opacity-40
                    transition-all duration-200
                    cursor-pointer
                  "
                >
                  {t.name}
                </button>
              ))}
            </div>

            {isAlpha && alphaHasPower && (
              <label className="flex items-center justify-center gap-2 mt-3 px-3 py-2 rounded-lg bg-neutral-900/40 border border-neutral-800 cursor-pointer hover:bg-neutral-800/40 transition-colors">
                <input
                  type="checkbox"
                  checked={infectTarget}
                  onChange={(e) => setInfectTarget(e.target.checked)}
                  className="accent-red-600 cursor-pointer"
                />
                <span className="text-neutral-400 text-xs">
                  🐺 Infectar em vez de matar (Poder do Lobo Alfa — Uso Único)
                </span>
              </label>
            )}
          </>
        )}
      </div>

      {error && (
        <p className="text-red-500 text-xs text-center">{error}</p>
      )}
    </div>
  )
}
