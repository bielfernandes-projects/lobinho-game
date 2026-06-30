'use client'

import { useParams, useRouter } from 'next/navigation'
import { useEffect, useState, useRef } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useCurrentPlayer } from '@/hooks/use-player'
import { useRoomPlayers, useGameState } from '@/hooks/use-room'
import { FlipCard } from '@/components/flip-card'
import { HostControls } from '@/components/host-controls'
import { NightPhase } from '@/components/night-phase'
import { DayAnnouncement } from '@/components/day-announcement'
import { VotingPanel } from '@/components/voting-panel'
import { TimerDisplay } from '@/components/timer-display'
import { HostTimerControls } from '@/components/host-timer-controls'
import { HostRolePanel } from '@/components/host-role-panel'

export default function GameScreen() {
  const params = useParams()
  const router = useRouter()
  const roomId = params.id as string
  const supabase = createClient()

  const { player, loading: playerLoading } = useCurrentPlayer(roomId)
  const { players, loading: playersLoading } = useRoomPlayers(roomId)
  const { gameState, loading: stateLoading } = useGameState(roomId)

  const [roomStatus, setRoomStatus] = useState<string | null>(null)
  const hasFlippedRef = useRef(false)

  const phase = gameState?.current_phase ?? null
  const turnIndex = gameState?.turn_index ?? 0
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

  const isHost = player.isHost
  const isAlive = player.isAlive
  const isModerator = player.role === 'moderator'

  // ── Phase: card_reveal ────────────────────────────────────────────
  if (phase === 'card_reveal') {
    // Host/moderator: skip card reveal entirely
    if (isHost || isModerator) {
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
            <p className="text-neutral-500 text-xs text-center">
              Aguardando jogadores revelarem suas cartas...
            </p>
            <HostRolePanel roomId={roomId} isHost={true} />
            <HostControls
              roomId={roomId}
              mode="advance"
              allViewed={allViewed}
              advanceLabel="Avançar para Noite"
            />
          </div>
        </div>
      )
    }

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
  if (phase === 'night' || roomStatus?.startsWith('finished_')) {
    const wolfVictimName = lastEvent?.victim_name ?? null

    if (phase === 'ended') {
      return renderEnded()
    }

    return (
      <div className="flex flex-1 flex-col items-center min-h-dvh">
        {/* Banner: resultado da votacao anterior (empate ou linchamento) */}
        {lastVoteResult && lastVoteResult.type === 'vote_tie' && (
          <div className="w-full bg-orange-950/40 border-b border-orange-900/30 px-6 py-4 text-center">
            <p className="text-orange-400 text-sm font-bold tracking-wide">
              🤝 A vila não chegou a um consenso. Ninguém foi linchado.
            </p>
          </div>
        )}

        {lastVoteResult && lastVoteResult.type === 'lynch' && lastVoteResult.victim_name && (
          <div className="w-full bg-red-950/40 border-b border-red-900/30 px-6 py-4 text-center">
            <p className="text-red-400 text-sm font-bold tracking-wide">
              ☠️ {lastVoteResult.victim_name} foi linchado pela vila.
            </p>
          </div>
        )}

        <NightPhase
          roomId={roomId}
          role={player.role ?? ''}
          playerId={player.id}
          turnIndex={turnIndex}
          isAlive={isAlive}
          wolvesResolved={wolvesResolved}
          wolfVictimName={wolfVictimName}
        />

        {/* Painel do mestre (visivel apenas para o host/moderador) */}
        {(isHost || isModerator) && (
          <div className="w-full px-6 pb-4 pt-2">
            <HostRolePanel roomId={roomId} isHost={true} />
          </div>
        )}

        {isHost && !wolvesResolved && (
          <div className="pb-8">
            <HostControls
              roomId={roomId}
              mode="resolve_night_wolves"
              turnIndex={turnIndex}
            />
          </div>
        )}

        {isHost && wolvesResolved && (
          <div className="pb-8">
            <HostControls
              roomId={roomId}
              mode="resolve_night"
            />
          </div>
        )}

        {!isHost && player.role !== 'werewolf' && player.role !== 'seer' && player.role !== 'witch' && !isModerator && (
          <p className="text-neutral-700 text-xs mt-4 select-none text-center px-6 pb-8">
            Quando todos estiverem prontos, o host resolverá a noite
          </p>
        )}
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

        {/* Painel do mestre */}
        {(isHost || isModerator) && (
          <div className="w-full max-w-sm mx-auto px-6 pt-4">
            <HostRolePanel roomId={roomId} isHost={true} />
          </div>
        )}

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

  // ── Phase: ended ──────────────────────────────────────────────────
  const isGameOver =
    phase === 'ended' ||
    roomStatus === 'finished_villagers_win' ||
    roomStatus === 'finished_wolves_win'

  if (isGameOver) {
    return renderEnded()
  }

  return null

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
