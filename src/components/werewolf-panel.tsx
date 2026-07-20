'use client'

import { useState, useEffect, useCallback, useRef } from 'react'
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
  target_index: number
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
  const [infectTarget, setInfectTarget] = useState(false)
  const [consensusVotes, setConsensusVotes] = useState<ConsensusVote[]>([])
  const [frenzyPhase, setFrenzyPhase] = useState<1 | 2>(1)
  const [wolvesLoaded, setWolvesLoaded] = useState(false)
  const prevTurnRef = useRef(turnIndex)
  const supabase = createClient()

  // Reset frenzy phase + consensus when turn changes
  useEffect(() => {
    if (prevTurnRef.current !== turnIndex) {
      prevTurnRef.current = turnIndex
      setFrenzyPhase(1)
      setConsensusVotes([])
      setHasActed(false)
    }
  }, [turnIndex])

  // Clear stale consensus when frenzy toggles on/off
  useEffect(() => {
    setConsensusVotes([])
    setFrenzyPhase(1)
    setWolvesLoaded(false)
  }, [wolvesFrenzy])

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
        setWolvesLoaded(true)
      }
    }

    load()
    return () => { cancelled = true; setWolvesLoaded(false) }
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

  // Initial fetch + polling fallback — ONLY after wolves loaded
  useEffect(() => {
    if (isFirstNight || !wolvesLoaded) return
    fetchConsensus()
    const iv = setInterval(fetchConsensus, 1500)
    return () => clearInterval(iv)
  }, [fetchConsensus, isFirstNight, wolvesLoaded])

  // Realtime subscription for consensus votes — ONLY after wolves loaded
  useEffect(() => {
    if (isFirstNight || !wolvesLoaded) return

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
  }, [roomId, isFirstNight, wolvesLoaded, fetchConsensus])

  // Compute alive wolves and expected voter count
  const aliveWolves = wolves.filter((w) => w.isAlive)
  const expectedVoters = wolvesLoaded ? aliveWolves.length : -1

  // Compute consensus for a given target_index, optionally excluding a target
  function computeConsensus(targetIndex: number = 1, excludeTargetId?: string | null) {
    if (expectedVoters <= 0) {
      return { hasConsensus: false, consensusTarget: null, consensusTargetName: null }
    }

    const validVotes = consensusVotes
      .filter((v) => v.target_id != null && v.target_index === targetIndex)
      .filter((v) => !excludeTargetId || v.target_id !== excludeTargetId)

    const hasConsensus = validVotes.length >= expectedVoters && validVotes.length > 0 && validVotes.every((v) => v.target_id === validVotes[0].target_id)

    if (hasConsensus) {
      console.log('[CONSENSUS DEBUG]', {
        targetIndex,
        wolvesLoaded,
        expectedVoters,
        aliveWolvesCount: aliveWolves.length,
        aliveWolvesNames: aliveWolves.map(w => w.name),
        validVotesCount: validVotes.length,
        allVotes: consensusVotes.map(v => ({ voter: v.voter_name, target: v.target_name, ti: v.target_index })),
      })
    }

    if (validVotes.length < expectedVoters) {
      return { hasConsensus: false, consensusTarget: null, consensusTargetName: null }
    }

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

  // Normal mode: single-target consensus
  const { hasConsensus, consensusTarget, consensusTargetName } = computeConsensus(1)

  // Frenzy mode: phase 1 always uses target_index=1
  const frenzyHasConsensus1 = wolvesFrenzy ? computeConsensus(1).hasConsensus : false
  const frenzyConsensusTarget1 = wolvesFrenzy ? computeConsensus(1).consensusTarget : null
  const frenzyConsensusTargetName1 = wolvesFrenzy ? computeConsensus(1).consensusTargetName : null

  // Frenzy phase 2: only compute if we're actually in phase 2 AND have a locked target 1
  const frenzyLockedTarget1 = wolvesFrenzy && frenzyPhase === 2 ? frenzyConsensusTarget1 : null
  const { hasConsensus: frenzyHasConsensus2, consensusTarget: frenzyConsensusTarget2, consensusTargetName: frenzyConsensusTargetName2 } =
    frenzyPhase === 2 && frenzyLockedTarget1
      ? computeConsensus(2, frenzyLockedTarget1)
      : { hasConsensus: false, consensusTarget: null, consensusTargetName: null }

  const frenzyAllConsensus = wolvesFrenzy && frenzyLockedTarget1 && frenzyConsensusTarget2

  // My vote for current phase
  const currentTargetIndex = wolvesFrenzy
    ? (frenzyPhase === 2 ? 2 : 1)
    : 1
  const myVote = consensusVotes.find((v) => v.voter_id === playerId && v.target_index === currentTargetIndex)

  // Votes grouped by target for inline display (current phase only)
  const votesByTarget = new Map<string, { voter_id: string; voter_name: string }[]>()
  consensusVotes
    .filter((v) => v.target_index === currentTargetIndex)
    .forEach((v) => {
      if (v.target_id) {
        const entry = { voter_id: v.voter_id, voter_name: v.voter_name }
        const existing = votesByTarget.get(v.target_id)
        if (existing) existing.push(entry)
        else votesByTarget.set(v.target_id, [entry])
      }
    })

  // Current phase consensus status
  const currentHasConsensus = wolvesFrenzy
    ? (frenzyPhase === 1 ? frenzyHasConsensus1 : frenzyHasConsensus2)
    : hasConsensus
  const currentConsensusTarget = wolvesFrenzy
    ? (frenzyPhase === 1 ? frenzyConsensusTarget1 : frenzyConsensusTarget2)
    : consensusTarget
  const currentConsensusTargetName = wolvesFrenzy
    ? (frenzyPhase === 1 ? frenzyConsensusTargetName1 : frenzyConsensusTargetName2)
    : consensusTargetName

  // Targets for current phase (exclude target 1 in frenzy phase 2)
  const currentTargets = wolvesFrenzy && frenzyPhase === 2 && frenzyLockedTarget1
    ? targets.filter((t) => t.id !== frenzyLockedTarget1)
    : targets

  // Advance from frenzy phase 1 → 2
  function handleAdvanceFrenzyPhase2() {
    if (frenzyHasConsensus1 && frenzyConsensusTarget1) {
      setFrenzyPhase(2)
    }
  }

  // Submit a kill action
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

  // Vote for a target in the current consensus phase
  async function handleVote(targetId: string) {
    setError('')
    try {
      const targetIndex = wolvesFrenzy ? (frenzyPhase === 2 ? 2 : 1) : 1
      const { error: rpcErr } = await supabase.rpc('upsert_consensus_vote', {
        p_room_id: roomId,
        p_target_id: targetId,
        p_target_index: targetIndex,
      })
      if (rpcErr) throw new Error(rpcErr.message)
    } catch (err) {
      console.error('[WerewolfPanel] vote error:', err)
      setError(err instanceof Error ? err.message : 'Erro ao votar')
    }
  }

  // Confirm kill(s)
  async function handleConsensusConfirm() {
    if (wolvesFrenzy) {
      if (!frenzyLockedTarget1 || !frenzyConsensusTarget2) return
      setBusy(true)
      setError('')
      try {
        await submitKill(frenzyLockedTarget1, false)
        await submitKill(frenzyConsensusTarget2, infectTarget)
        setHasActed(true)
        onDone?.()
      } catch (err) {
        console.error('[WerewolfPanel] RPC error:', err)
        setError(err instanceof Error ? err.message : 'Erro inesperado')
      }
      setBusy(false)
    } else {
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

  // ── FRENZY PHASE 1 → 2 TRANSITION ────────────────────────────────
  // If frenzy is active and all wolves agreed on target 1, but we haven't
  // advanced to phase 2 yet, show a confirmation screen.
  if (wolvesFrenzy && frenzyPhase === 1 && frenzyHasConsensus1 && frenzyConsensusTargetName1) {
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

        <div className="py-4 px-6 rounded-xl bg-emerald-950/30 border border-emerald-800/40 space-y-2">
          <p className="text-emerald-400 text-xs uppercase tracking-wider font-bold">
            ✅ 1º alvo definido — consenso
          </p>
          <p className="text-emerald-300 text-lg font-bold">
            {frenzyConsensusTargetName1}
          </p>
          <p className="text-neutral-500 text-[10px] uppercase tracking-wider">
            Todos os lobos concordaram
          </p>
        </div>

        <button
          onClick={handleAdvanceFrenzyPhase2}
          disabled={busy}
          className="w-full py-3 px-4 rounded-xl text-sm font-bold bg-red-900/30 border border-red-700/50 text-red-400 hover:bg-red-800/40 disabled:opacity-40 transition-all duration-200 cursor-pointer"
        >
          🔥 Prosseguir ao 2º alvo
        </button>

        {error && (
          <p className="text-red-500 text-xs text-center">{error}</p>
        )}
      </div>
    )
  }

  // ── CONSOLIDATED MODE (normal + frenzy phase 2) ───────────────────
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

      {wolvesFrenzy && frenzyPhase === 2 && frenzyConsensusTargetName1 && (
        <p className="text-emerald-500 text-xs font-bold">
          ✅ 1º alvo definido: {frenzyConsensusTargetName1}
        </p>
      )}

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

      {/* Target list with inline votes */}
      <div>
        <p className="text-neutral-500 text-xs mb-3">
          {wolvesFrenzy
            ? frenzyPhase === 1
              ? 'Escolha o 1º alvo:'
              : 'Escolha o 2º alvo:'
            : aliveWolves.length > 1
              ? myVote?.target_id
                ? 'Seu voto — clique para mudar:'
                : 'Escolha seu voto:'
              : 'Escolha a vítima:'}
        </p>
        <div className="space-y-2">
          {currentTargets.map((t) => {
            const isMyVote = myVote?.target_id === t.id
            const votersForTarget = votesByTarget.get(t.id) || []
            return (
              <button
                key={t.id}
                onClick={() => handleVote(t.id)}
                disabled={busy}
                className={`
                  w-full py-3 px-4 rounded-xl text-sm font-medium
                  transition-all duration-200 cursor-pointer flex items-center justify-between gap-2
                  ${isMyVote
                    ? 'bg-red-900/30 border border-red-700/50 text-red-300'
                    : 'bg-neutral-900 border border-neutral-800 text-neutral-300 hover:border-red-800 hover:text-red-400'
                  }
                  disabled:opacity-40
                `}
              >
                <span>{isMyVote ? `✓ ${t.name}` : t.name}</span>
                {votersForTarget.length > 0 && (
                  <span className="text-neutral-500 text-[10px] shrink-0">
                    {votersForTarget.map((v) =>
                      v.voter_id === playerId ? '(Você)' : `(${v.voter_name})`
                    ).join(' ')}
                  </span>
                )}
              </button>
            )
          })}
        </div>
      </div>

      {/* Alpha wolf infection option (only during frenzy when picking target 2) */}
      {isAlpha && alphaHasPower && wolvesFrenzy && frenzyPhase === 2 && currentHasConsensus && currentConsensusTarget && (
        <label className="flex items-center justify-center gap-2 px-3 py-2 rounded-lg bg-neutral-900/40 border border-neutral-800 cursor-pointer hover:bg-neutral-800/40 transition-colors">
          <input
            type="checkbox"
            checked={infectTarget}
            onChange={(e) => setInfectTarget(e.target.checked)}
            className="accent-red-600 cursor-pointer"
          />
          <span className="text-neutral-400 text-xs">
            🐺 Infectar {currentConsensusTargetName} (Poder do Lobo Alfa — Uso Único)
          </span>
        </label>
      )}

      {/* Consensus status + confirm button */}
      {aliveWolves.length > 1 && (
        <div className="space-y-2">
          {wolvesFrenzy ? (
            // Frenzy phase 2: show consensus
            frenzyAllConsensus ? (
              <p className="text-emerald-500 text-xs font-bold uppercase tracking-wider">
                ✅ Consenso — 1º: {frenzyConsensusTargetName1}, 2º: {frenzyConsensusTargetName2}
              </p>
            ) : frenzyHasConsensus2 ? (
              <p className="text-emerald-500 text-xs font-bold uppercase tracking-wider">
                ✅ 2º alvo: {frenzyConsensusTargetName2} — aguardando confirmação
              </p>
            ) : (
              <p className="text-yellow-500 text-xs uppercase tracking-wider">
                ⚠️ Aguardando consenso no 2º alvo...
              </p>
            )
          ) : (
            // Normal: single consensus
            hasConsensus ? (
              <p className="text-emerald-500 text-xs font-bold uppercase tracking-wider">
                ✅ Consenso — todos votaram em {consensusTargetName}
              </p>
            ) : (
              <p className="text-yellow-500 text-xs uppercase tracking-wider">
                ⚠️ Aguardando consenso...
              </p>
            )
          )}

          <button
            onClick={handleConsensusConfirm}
            disabled={busy || !(wolvesFrenzy ? frenzyAllConsensus : hasConsensus)}
            className="w-full py-3 px-4 rounded-xl text-sm font-bold bg-red-900/30 border border-red-700/50 text-red-400 hover:bg-red-800/40 disabled:opacity-30 disabled:cursor-not-allowed transition-all duration-200 cursor-pointer"
          >
            {busy
              ? 'Atacando...'
              : wolvesFrenzy && frenzyAllConsensus
                ? `⚔️ Confirmar Ataque — ${frenzyConsensusTargetName1} & ${frenzyConsensusTargetName2}`
                : wolvesFrenzy
                  ? `⚔️ Confirmar (2 alvos necessários)`
                  : hasConsensus
                    ? `⚔️ Confirmar Ataque a ${consensusTargetName}`
                    : '⚔️ Confirmar (consenso necessário)'}
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
