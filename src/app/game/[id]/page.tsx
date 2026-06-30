'use client'

import { useParams, useRouter } from 'next/navigation'
import { useEffect, useState, useRef } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useCurrentPlayer } from '@/hooks/use-player'
import { useRoomPlayers, useGameState } from '@/hooks/use-room'
import { FlipCard } from '@/components/flip-card'
import { HostControls } from '@/components/host-controls'
import { WerewolfPanel } from '@/components/werewolf-panel'
import { SeerPanel } from '@/components/seer-panel'
import { WitchPanel } from '@/components/witch-panel'
import { DayAnnouncement } from '@/components/day-announcement'
import { VotingPanel } from '@/components/voting-panel'
import { TimerDisplay } from '@/components/timer-display'
import { HostTimerControls } from '@/components/host-timer-controls'
import { HostRolePanel } from '@/components/host-role-panel'
import { VoteTimerPanel } from '@/components/vote-timer-panel'

export default function GameScreen() {
  const params = useParams()
  const router = useRouter()
  const roomId = params.id as string
  const supabase = createClient()

  const { player, loading: playerLoading } = useCurrentPlayer(roomId)
  const { players, loading: playersLoading } = useRoomPlayers(roomId)
  const { gameState, loading: stateLoading } = useGameState(roomId)

  const [roomStatus, setRoomStatus] = useState<string | null>(null)
  const [showExitModal, setShowExitModal] = useState(false)
  const [actedRoles, setActedRoles] = useState<Set<string>>(new Set())
  const prevNightStepRef = useRef<string>('sleeping')
  const hasFlippedRef = useRef(false)

  const phase = gameState?.current_phase ?? null
  const turnIndex = gameState?.turn_index ?? 0
  const nightStep = gameState?.night_step ?? 'sleeping'
  const wolvesResolved = gameState?.wolves_resolved ?? false
  const lastEvent = gameState?.last_event ?? null
  const lastVoteResult = gameState?.last_vote_result ?? null
  const timerRemaining = gameState?.timer_remaining ?? null
  const isTimerRunning = gameState?.is_timer_running ?? false
  const timerStartedAt = gameState?.timer_started_at ?? null
  const timerDuration = gameState?.timer_duration ?? null
  const hasTimer = timerDuration != null

  // Redirect if no player
  useEffect(() => {
    if (!playerLoading && !player) {
      router.push('/')
    }
  }, [player, playerLoading, router])

  // Watch rooms.status for game over (fallback para Realtime)
  useEffect(() => {
    const channel = supabase
      .channel(`game-room:${roomId}`)
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'rooms',
          filter: `id=eq.${roomId}`,
        },
        (payload) => {
          if (payload.new && 'status' in payload.new) {
            const s = payload.new.status as string
            setRoomStatus(s)
          }
        }
      )
      .subscribe()

    return () => { supabase.removeChannel(channel) }
  }, [roomId])

  // Derived state: gameEnded is true ONLY when rooms.status says so
  const gameEnded =
    roomStatus === 'finished_villagers_win' || roomStatus === 'finished_wolves_win'

  // Mark has_viewed_card on first flip
  async function handleFirstFlip() {
    if (hasFlippedRef.current || !player) return
    hasFlippedRef.current = true

    await supabase
      .from('players')
      .update({
        has_viewed_card: true,
        viewed_card_at: new Date().toISOString(),
      })
      .eq('id', player.id)
  }

  const allViewed = players.length > 0 && players.every((p) => p.isHost || p.hasViewedCard)

  if (playerLoading || playersLoading || stateLoading) {
    return (
      <div className="flex flex-1 items-center justify-center min-h-dvh">
        <div className="w-8 h-8 border-2 border-red-700 border-t-transparent rounded-full animate-spin" />
      </div>
    )
  }

  if (!player || !phase) return null

  // Game ended — ONLY triggered by rooms.status via Supabase Realtime
  if (gameEnded) {
    return renderEnded()
  }

  // Reset actedRoles when nightStep changes
  if (nightStep !== prevNightStepRef.current) {
    prevNightStepRef.current = nightStep
    setActedRoles(new Set())
  }

  const isHost = player.isHost
  const isAlive = player.isAlive
  const isModerator = player.role === 'moderator'

  function handleRoleDone(role: string) {
    setActedRoles((prev) => new Set([...prev, role]))
  }

  async function handleSetNightStep(step: string) {
    await supabase.from('game_state').update({ night_step: step }).eq('room_id', roomId)
  }

  async function handleExitToLobby() {
    const supabase = createClient()
    await supabase.from('rooms').update({ status: 'waiting' }).eq('id', roomId)
    router.push(`/lobby/${roomId}`)
  }

  // ── Moderator / Host Dashboard ──────────────────────────
  // Omniscient view — NEVER shows the "close your eyes" screen
  if (isHost || isModerator) {
    return (
      <div className="flex flex-1 flex-col items-center min-h-dvh">
        <div className="w-full px-6 pt-8 pb-4 text-center">
          <p className="text-neutral-600 text-[10px] uppercase tracking-widest mb-1">Fase</p>
          <p className="text-sm font-bold tracking-wider uppercase">
            {phase === 'card_reveal' && '🎴 Revelação'}
            {phase === 'night' && '🌙 Noite'}
            {phase === 'day' && '☀️ Dia'}
            {phase === 'vote' && '🗳️ Votação'}
            {!'card_reveal night day vote'.includes(phase) && (
              <span className="text-red-500">⚠️ {phase}</span>
            )}
          </p>
        </div>

        {lastVoteResult?.type === 'vote_tie' && (
          <div className="w-full bg-orange-950/40 border-b border-orange-900/30 px-6 py-4 text-center">
            <p className="text-orange-400 text-sm font-bold tracking-wide">
              🤝 A vila não chegou a um consenso. Ninguém foi linchado.
            </p>
          </div>
        )}

        {lastVoteResult?.type === 'lynch' && lastVoteResult.victim_name && (
          <div className="w-full bg-red-950/40 border-b border-red-900/30 px-6 py-4 text-center">
            <p className="text-red-400 text-sm font-bold tracking-wide">
              ☠️ {lastVoteResult.victim_name} foi linchado pela vila.
            </p>
          </div>
        )}

        {phase === 'day' && lastEvent?.victims && (
          <DayAnnouncement
            victims={lastEvent.victims as { name: string; cause: string }[]}
            turnIndex={turnIndex}
          />
        )}

        <div className="w-full px-6 pb-4">
          <HostRolePanel roomId={roomId} isHost={true} />
        </div>

        {phase === 'card_reveal' && (
          <HostControls
            roomId={roomId}
            mode="advance"
            allViewed={allViewed}
            advanceLabel="Avançar para Noite"
          />
        )}

        {phase === 'night' && (
          <div className="w-full max-w-sm mx-auto space-y-3 py-2">
            <p className="text-neutral-600 text-[10px] uppercase tracking-widest text-center">
              Controle da Noite
            </p>
            <div className="flex flex-wrap gap-2 justify-center">
              <button
                onClick={() => handleSetNightStep('sleeping')}
                disabled={nightStep === 'sleeping'}
                className="px-3 py-2 rounded-lg text-xs font-bold tracking-wider bg-neutral-900 border border-neutral-800 text-neutral-500 hover:text-neutral-400 disabled:opacity-30 cursor-pointer transition-all duration-200"
              >
                😴 Todos Dormindo
              </button>
              <button
                onClick={() => handleSetNightStep('wolves')}
                disabled={nightStep === 'wolves' || wolvesResolved}
                className="px-3 py-2 rounded-lg text-xs font-bold tracking-wider bg-neutral-900 border border-red-900/30 text-red-400 hover:bg-red-900/20 disabled:opacity-30 cursor-pointer transition-all duration-200"
              >
                🐺 Acordar Lobos
              </button>
              <button
                onClick={() => handleSetNightStep('seer')}
                disabled={nightStep === 'seer'}
                className="px-3 py-2 rounded-lg text-xs font-bold tracking-wider bg-neutral-900 border border-purple-900/30 text-purple-400 hover:bg-purple-900/20 disabled:opacity-30 cursor-pointer transition-all duration-200"
              >
                🔮 Acordar Vidente
              </button>
              <button
                onClick={() => handleSetNightStep('witch')}
                disabled={nightStep === 'witch'}
                className="px-3 py-2 rounded-lg text-xs font-bold tracking-wider bg-neutral-900 border border-emerald-900/30 text-emerald-400 hover:bg-emerald-900/20 disabled:opacity-30 cursor-pointer transition-all duration-200"
              >
                🧪 Acordar Bruxa
              </button>
            </div>

            {!wolvesResolved && (
              <HostControls
                roomId={roomId}
                mode="resolve_night_wolves"
                turnIndex={turnIndex}
              />
            )}

            {wolvesResolved && (
              <HostControls
                roomId={roomId}
                mode="resolve_night"
              />
            )}
          </div>
        )}

        {phase === 'day' && (
          <div className="w-full max-w-sm mx-auto py-4 flex flex-col items-center gap-3">
            <TimerDisplay
              remaining={timerRemaining}
              isRunning={isTimerRunning}
              startedAt={timerStartedAt}
            />
            <HostTimerControls
              roomId={roomId}
              isRunning={isTimerRunning}
              hasTimer={hasTimer}
            />
            <HostControls
              roomId={roomId}
              mode="advance"
              advanceLabel="Iniciar Votação"
            />
          </div>
        )}

        {phase === 'vote' && (
          <>
            <HostControls
              roomId={roomId}
              mode="resolve_vote"
              turnIndex={turnIndex}
            />
            <VoteTimerPanel />
          </>
        )}

        <div className="mt-auto pt-6 pb-8 px-6 w-full max-w-sm mx-auto">
          <button
            onClick={() => setShowExitModal(true)}
            className="w-full py-2.5 rounded-xl text-xs font-medium tracking-wider text-neutral-600 border border-neutral-800 hover:border-red-900/50 hover:text-red-500 transition-all duration-200 cursor-pointer bg-transparent"
          >
            ⚠️ Voltar para o Lobby
          </button>
        </div>

        {showExitModal && (
          <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 px-6">
            <div className="w-full max-w-xs rounded-2xl border border-neutral-800 bg-neutral-950 p-6 text-center space-y-4">
              <p className="text-neutral-300 text-sm font-medium">
                Tem certeza? O jogo será interrompido.
              </p>
              <div className="flex gap-3">
                <button
                  onClick={() => setShowExitModal(false)}
                  className="flex-1 py-3 rounded-xl text-sm font-medium bg-neutral-900 border border-neutral-800 text-neutral-400 hover:bg-neutral-800 cursor-pointer transition-all duration-200"
                >
                  Cancelar
                </button>
                <button
                  onClick={handleExitToLobby}
                  className="flex-1 py-3 rounded-xl text-sm font-bold bg-red-900/30 border border-red-700/50 text-red-400 hover:bg-red-800/40 cursor-pointer transition-all duration-200"
                >
                  Sim, voltar
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    )
  }

  // ── Phase: card_reveal ────────────────────────────────────────────
  if (phase === 'card_reveal') {
    return (
      <div className="flex flex-1 flex-col items-center px-6 py-8 min-h-dvh">
        <div className="w-full max-w-sm flex flex-col items-center gap-6">
          <div className="text-center">
            <p className="text-neutral-600 text-[10px] uppercase tracking-widest mb-1">
              Fase
            </p>
            <p className="text-sm font-bold tracking-wider text-red-500 uppercase">
              🎴 Revelação
            </p>
          </div>

          <p className="text-neutral-500 text-xs uppercase tracking-widest text-center select-none">
            Pressione e segure a carta para ver sua função
          </p>
          <FlipCard
            playerName={player.name}
            role={player.role ?? '???'}
            onFirstFlip={handleFirstFlip}
          />
        </div>
      </div>
    )
  }

  // ── Phase: night ──────────────────────────────────────────────────
  if (phase === 'night') {
    return (
      <div className="flex flex-1 flex-col items-center min-h-dvh">
        {lastVoteResult?.type === 'vote_tie' && (
          <div className="w-full bg-orange-950/40 border-b border-orange-900/30 px-6 py-4 text-center">
            <p className="text-orange-400 text-sm font-bold tracking-wide">
              🤝 A vila não chegou a um consenso. Ninguém foi linchado.
            </p>
          </div>
        )}

        {lastVoteResult?.type === 'lynch' && lastVoteResult.victim_name && (
          <div className="w-full bg-red-950/40 border-b border-red-900/30 px-6 py-4 text-center">
            <p className="text-red-400 text-sm font-bold tracking-wide">
              ☠️ {lastVoteResult.victim_name} foi linchado pela vila.
            </p>
          </div>
        )}

        {renderNightPanel()}
      </div>
    )
  }

  // ── Phase: day ────────────────────────────────────────────────────
  if (phase === 'day') {
    const victims = (lastEvent?.victims ?? []) as { name: string; cause: string }[]

    return (
      <div className="flex flex-1 flex-col items-center min-h-dvh">
        <DayAnnouncement
          victims={victims}
          turnIndex={turnIndex}
        />

        <div className="w-full max-w-sm mx-auto py-4 flex flex-col items-center gap-3">
          <TimerDisplay
            remaining={timerRemaining}
            isRunning={isTimerRunning}
            startedAt={timerStartedAt}
          />

          {isHost && (
            <HostTimerControls
              roomId={roomId}
              isRunning={isTimerRunning}
              hasTimer={hasTimer}
            />
          )}

          {!isHost && hasTimer && !isTimerRunning && timerRemaining != null && timerRemaining > 0 && (
            <p className="text-neutral-600 text-[10px] uppercase tracking-widest">
              ⏸️ Pausado pelo anfitrião
            </p>
          )}
        </div>

        {isHost && (
          <div className="pb-8">
            <HostControls
              roomId={roomId}
              mode="advance"
              advanceLabel="Iniciar Votação"
            />
          </div>
        )}

        {!isHost && (
          <div className="pb-8 text-center">
            <p className="text-neutral-700 text-xs">
              O anfitrião iniciará a votação em breve
            </p>
          </div>
        )}
      </div>
    )
  }

  // ── Phase: vote ──────────────────────────────────────────────────
  if (phase === 'vote') {
    return (
      <div className="flex flex-1 flex-col items-center min-h-dvh">
        <VotingPanel
          roomId={roomId}
          playerId={player.id}
          isAlive={isAlive}
          turnIndex={turnIndex}
        />

        {isHost && (
          <HostControls
            roomId={roomId}
            mode="resolve_vote"
            turnIndex={turnIndex}
          />
        )}
      </div>
    )
  }

  return null

  function renderNightPanel() {
    if (!player) return null

    function sleepScreen() {
      return (
        <div className="flex flex-1 flex-col items-center justify-center px-6 gap-6">
          <p className="text-neutral-600 text-xs uppercase tracking-widest select-none animate-pulse">
            🌙 Fechem os olhos...
          </p>
          <p className="text-neutral-800 text-sm select-none">
            Aguarde o dia nascer...
          </p>
        </div>
      )
    }

    if (!isAlive) return sleepScreen()

    const wolfVictimName = lastEvent?.victim_name ?? null

    if (player.role === 'werewolf') {
      if (nightStep !== 'wolves') return sleepScreen()
      if (actedRoles.has('werewolf')) return sleepScreen()
      return (
        <div className="flex flex-1 flex-col items-center justify-center px-6 gap-6">
          <p className="text-neutral-600 text-xs uppercase tracking-widest select-none animate-pulse">
            🌙 Fechem os olhos...
          </p>
          <WerewolfPanel roomId={roomId} playerId={player.id} turnIndex={turnIndex} onDone={() => handleRoleDone('werewolf')} />
        </div>
      )
    }

    if (player.role === 'seer') {
      if (nightStep !== 'seer') return sleepScreen()
      if (actedRoles.has('seer')) return sleepScreen()
      return (
        <div className="flex flex-1 flex-col items-center justify-center px-6 gap-6">
          <p className="text-neutral-600 text-xs uppercase tracking-widest select-none animate-pulse">
            🌙 Fechem os olhos...
          </p>
          <SeerPanel roomId={roomId} playerId={player.id} turnIndex={turnIndex} onDone={() => handleRoleDone('seer')} />
        </div>
      )
    }

    if (player.role === 'witch') {
      if (!wolvesResolved) return sleepScreen()
      if (nightStep !== 'witch') return sleepScreen()
      if (actedRoles.has('witch')) return sleepScreen()
      return (
        <div className="flex flex-1 flex-col items-center justify-center px-6 gap-6">
          <p className="text-neutral-600 text-xs uppercase tracking-widest select-none animate-pulse">
            🌙 Fechem os olhos...
          </p>
          <WitchPanel
            roomId={roomId}
            playerId={player.id}
            turnIndex={turnIndex}
            victimName={wolfVictimName}
            onDone={() => handleRoleDone('witch')}
          />
        </div>
      )
    }

    return sleepScreen()
  }

  function renderEnded() {
    const winner = lastEvent?.winner ?? (roomStatus === 'finished_wolves_win' ? 'wolves_win' : 'unknown')
    return (
      <div className="flex flex-1 flex-col items-center justify-center min-h-dvh px-6 gap-6">
        <p className="text-6xl">🏆</p>
        <p className="text-neutral-400 text-xs uppercase tracking-widest">
          Fim de Jogo
        </p>
        <p className="text-3xl font-black tracking-widest uppercase text-yellow-500 drop-shadow-[0_0_20px_rgba(234,179,8,0.4)] text-center">
          {winner === 'wolves_win' ? '🐺 Lobisomens Venceram' : '🌿 Aldeões Venceram'}
        </p>
        <button onClick={() => router.push('/')}
          className="mt-4 px-8 py-3 rounded-2xl font-bold text-sm tracking-wider bg-neutral-900 text-neutral-400 border border-neutral-800 hover:bg-neutral-800 cursor-pointer transition-all duration-200"
        >
          Voltar ao Início
        </button>
      </div>
    )
  }
}
