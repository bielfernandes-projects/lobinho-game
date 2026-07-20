'use client'

import { useState, useEffect, useCallback } from 'react'
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

interface ConsensusVote {
  voter_id: string
  voter_name: string
  target_id: string | null
  target_name: string | null
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
  const [consensusVotes, setConsensusVotes] = useState<ConsensusVote[]>([])
  const supabase = createClient()

  // Fetch wolves + targets
  useEffect(() => {
    let cancelled = false

    async function load() {
      setError('')

      const { data: all, error: profilesErr } = await supabase
        .from('player_profiles')
        .select('id, name, is_host, is_alive, has_viewed_card, user_id')
        .eq('room_id', roomId)

      if (cancelled) return

      if (profilesErr || !all) {
        if (!cancelled) setError('Erro ao carregar jogadores.')
        return
      }

      const profiles = (all as any[]).map((r) => ({
        id: r.id,
        name: r.name,
        isHost: r.is_host,
        isAlive: r.is_alive,
        hasViewedCard: r.has_viewed_card,
        userId: r.user_id,
      }))

      const { data: wolvesData, error: wolvesErr } = await supabase.rpc(
        'get_werewolf_teammates',
        { p_room_id: roomId }
      )

      if (cancelled) return

      if (wolvesErr) {
        console.error('[WerewolfPanel] RPC error:', wolvesErr)
        if (!cancelled) setError('Erro ao carregar aliados.')
        return
      }

      const wolfIds = new Set(
        ((wolvesData ?? []) as { id: string; name: string }[]).map((w) => w.id)
      )

      if (!cancelled) {
        setWolves(profiles.filter((p) => wolfIds.has(p.id)))
        setTargets(
          profiles.filter(
            (p) =>
              p.isAlive && !wolfIds.has(p.id) && !p.isHost && p.id !== playerId
          )
        )
      }
    }

    load()
    return () => { cancelled = true }
  }, [roomId, playerId, wolvesFrenzy])

  // Fetch consensus votes
  const fetchConsensus = useCallback(async () => {
    try {
      const { data, error } = await supabase.rpc('get_wolf_consensus', {
        p_room_id: roomId,
      })
      if (!error && data) {
        setConsensusVotes(data as ConsensusVote[])
      }
    } catch {}
  }, [roomId])

  // Initial fetch + polling fallback
  useEffect(() => {
    if (isFirstNight) return
    fetchConsensus()
    const iv = setInterval(fetchConsensus, 3000)
    return () => clearInterval(iv)
  }, [fetchConsensus, isFirstNight])

  // Realtime subscription for consensus votes
  useEffect(() => {
    if (isFirstNight) return

    const channel = supabase
      .channel(`consensus:${roomId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'consensus_votes',
          filter: `room_id=eq.${roomId}`,
        },
        () => {
          fetchConsensus()
        }
      )
      .subscribe()

    return () => { supabase.removeChannel(channel) }
  }, [roomId, isFirstNight, fetchConsensus])

  // Compute consensus state
  const aliveWolves = wolves.filter((w) => w.isAlive)
  const expectedVoters = aliveWolves.length

  function computeConsensus(): { hasConsensus: boolean; consensusTarget: string | null; consensusTargetName: string | null } {
    const validVotes = consensusVotes.filter((v) => v.target_id != null)
    if (validVotes.length < expectedVoters || expectedVoters === 0) {
      return { hasConsensus: false, consensusTarget: null, consensusTargetName: null }
    }

    // Check if all votes are for the same target
    const firstTargetId = validVotes[0].target_id
    const allSame = validVotes.every((v) => v.target_id === firstTargetId)
    if (allSame) {
      return {
        hasConsensus: true,
        consensusTarget: firstTargetId,
        consensusTargetName: validVotes[0].target_name,
      }
    }

    return { hasConsensus: false, consensusTarget: null, consensusTargetName: null }
  }

  const { hasConsensus, consensusTarget, consensusTargetName } = computeConsensus()

  // My vote
  const myVote = consensusVotes.find((v) => v.voter_id === playerId)

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

  async function handleVote(targetId: string) {
    setError('')
    try {
      const { error: rpcErr } = await supabase.rpc('upsert_consensus_vote', {
        p_room_id: roomId,
        p_target_id: targetId,
      })
      if (rpcErr) throw new Error(rpcErr.message)
    } catch (err) {
      console.error('[WerewolfPanel] vote error:', err)
      setError(err instanceof Error ? err.message : 'Erro ao votar')
    }
  }

  async function handleConsensusConfirm() {
    if (!consensusTarget) return
    setBusy(true)
    setError('')
    try {
      await submitKill(consensusTarget, infectTarget)
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

  async function handleFrenzyVote(targetId: string) {
    setError('')
    setSelectedTargets((prev) => {
      if (prev.includes(targetId)) {
        return prev.filter((t) => t !== targetId)
      }
      if (prev.length >= 2) return prev
      return [...prev, targetId]
    })
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

        {aliveWolves.length > 1 && (
          <div>
            <p className="text-neutral-600 text-[10px] uppercase tracking-wider mb-2">
              Seus aliados (vivos)
            </p>
            <div className="flex flex-wrap justify-center gap-2">
              {aliveWolves
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

  // ── FRENZY MODE ────────────────────────────────────────────
  if (wolvesFrenzy) {
    return (
      <div className="w-full max-w-sm text-center space-y-4">
        <p className="text-red-500 text-sm uppercase tracking-widest font-bold">
          🐺 Lobisomens
        </p>

        <p className="text-yellow-400 text-xs uppercase tracking-wider font-bold animate-pulse">
          🔥 FRENESI — Matem 2 vítimas esta noite!
        </p>

        {aliveWolves.length > 1 && (
          <div>
            <p className="text-neutral-600 text-[10px] uppercase tracking-wider mb-2">
              Seus aliados (vivos)
            </p>
            <div className="flex flex-wrap justify-center gap-2">
              {aliveWolves
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
                  onClick={() => handleFrenzyVote(t.id)}
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
        </div>

        {error && (
          <p className="text-red-500 text-xs text-center">{error}</p>
        )}
      </div>
    )
  }

  // ── NORMAL MODE (with consensus voting) ────────────────────
  return (
    <div className="w-full max-w-sm text-center space-y-4">
      <p className="text-red-500 text-sm uppercase tracking-widest font-bold">
        🐺 Lobisomens
      </p>

      {aliveWolves.length > 1 && (
        <div>
          <p className="text-neutral-600 text-[10px] uppercase tracking-wider mb-2">
            Seus aliados (vivos)
          </p>
          <div className="flex flex-wrap justify-center gap-2">
            {aliveWolves
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

      {/* Consensus vote display */}
      {aliveWolves.length > 1 && (
        <div className="rounded-xl border border-neutral-800 bg-neutral-900/60 px-4 py-3 space-y-2">
          <p className="text-neutral-500 text-[10px] uppercase tracking-widest font-bold">
            🗳️ Votos
          </p>
          <div className="space-y-1.5">
            {consensusVotes.map((v) => (
              <div key={v.voter_id} className="flex items-center justify-between text-xs">
                <span className="text-neutral-400">
                  {v.voter_id === playerId ? (
                    <span className="text-red-400 font-bold">Você</span>
                  ) : (
                    v.voter_name
                  )}
                </span>
                <span className="text-neutral-300">
                  {v.target_name ? (
                    <>→ <span className="text-red-400">{v.target_name}</span></>
                  ) : (
                    <span className="text-neutral-600">—</span>
                  )}
                </span>
              </div>
            ))}
            {/* Show wolves who haven't voted yet */}
            {aliveWolves
              .filter((w) => !consensusVotes.some((v) => v.voter_id === w.id))
              .map((w) => (
                <div key={w.id} className="flex items-center justify-between text-xs">
                  <span className="text-neutral-400">
                    {w.id === playerId ? (
                      <span className="text-red-400 font-bold">Você</span>
                    ) : (
                      w.name
                    )}
                  </span>
                  <span className="text-neutral-600">aguardando...</span>
                </div>
              ))}
          </div>
        </div>
      )}

      {/* Target selection */}
      <div>
        <p className="text-neutral-500 text-xs mb-3">
          {aliveWolves.length > 1
            ? myVote?.target_id
              ? 'Seu voto — clique para mudar:'
              : 'Escolha seu voto:'
            : 'Escolha a vítima:'}
        </p>
        <div className="space-y-2">
          {targets.map((t) => {
            const isMyVote = myVote?.target_id === t.id
            return (
              <button
                key={t.id}
                onClick={() => handleVote(t.id)}
                disabled={busy}
                className={`
                  w-full py-3 px-4 rounded-xl text-sm font-medium
                  transition-all duration-200 cursor-pointer
                  ${isMyVote
                    ? 'bg-red-900/30 border border-red-700/50 text-red-300'
                    : 'bg-neutral-900 border border-neutral-800 text-neutral-300 hover:border-red-800 hover:text-red-400'
                  }
                  disabled:opacity-40
                `}
              >
                {isMyVote ? `✓ ${t.name}` : t.name}
              </button>
            )
          })}
        </div>
      </div>

      {/* Alpha wolf infection option */}
      {isAlpha && alphaHasPower && hasConsensus && consensusTarget && (
        <label className="flex items-center justify-center gap-2 px-3 py-2 rounded-lg bg-neutral-900/40 border border-neutral-800 cursor-pointer hover:bg-neutral-800/40 transition-colors">
          <input
            type="checkbox"
            checked={infectTarget}
            onChange={(e) => setInfectTarget(e.target.checked)}
            className="accent-red-600 cursor-pointer"
          />
          <span className="text-neutral-400 text-xs">
            🐺 Infectar {consensusTargetName} (Poder do Lobo Alfa — Uso Único)
          </span>
        </label>
      )}

      {/* Consensus status + confirm button */}
      {aliveWolves.length > 1 && (
        <div className="space-y-2">
          {hasConsensus ? (
            <p className="text-emerald-500 text-xs font-bold uppercase tracking-wider">
              ✅ Consenso — todos votaram em {consensusTargetName}
            </p>
          ) : (
            <p className="text-yellow-500 text-xs uppercase tracking-wider">
              ⚠️ Aguardando consenso...
            </p>
          )}

          <button
            onClick={handleConsensusConfirm}
            disabled={busy || !hasConsensus}
            className="w-full py-3 px-4 rounded-xl text-sm font-bold bg-red-900/30 border border-red-700/50 text-red-400 hover:bg-red-800/40 disabled:opacity-30 disabled:cursor-not-allowed transition-all duration-200 cursor-pointer"
          >
            {busy ? 'Atacando...' : hasConsensus ? `⚔️ Confirmar Ataque a ${consensusTargetName}` : '⚔️ Confirmar (consenso necessário)'}
          </button>
        </div>
      )}

      {/* Single wolf — direct confirm */}
      {aliveWolves.length <= 1 && myVote?.target_id && (
        <button
          onClick={handleConsensusConfirm}
          disabled={busy}
          className="w-full py-3 px-4 rounded-xl text-sm font-bold bg-red-900/30 border border-red-700/50 text-red-400 hover:bg-red-800/40 disabled:opacity-40 transition-all duration-200 cursor-pointer"
        >
          {busy ? 'Atacando...' : `⚔️ Confirmar Ataque a ${myVote.target_name}`}
        </button>
      )}

      {error && (
        <p className="text-red-500 text-xs text-center">{error}</p>
      )}
    </div>
  )
}
