'use client'

import { useParams, useRouter } from 'next/navigation'
import { useEffect, useState, useRef } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useCurrentPlayer } from '@/hooks/use-player'
import { useRoomPlayers, useGameState } from '@/hooks/use-room'
import { FlipCard } from '@/components/flip-card'
import { CARD_CATALOG, ROLE_STYLE } from '@/lib/cards'
import { HostControls } from '@/components/host-controls'
import { WerewolfPanel } from '@/components/werewolf-panel'
import { SeerPanel } from '@/components/seer-panel'
import { WitchPanel } from '@/components/witch-panel'
import { DayAnnouncement } from '@/components/day-announcement'
import { TimerDisplay } from '@/components/timer-display'
import { HostTimerControls } from '@/components/host-timer-controls'
import { HostRolePanel } from '@/components/host-role-panel'
import { VoteTimerPanel } from '@/components/vote-timer-panel'
import { DeadPlayerScreen } from '@/components/dead-player-screen'
import { TribunalPanel } from '@/components/tribunal-panel'
import { TribunalVoting } from '@/components/tribunal-voting'
import { TribunalReveal } from '@/components/tribunal-reveal'
import { HostActionLog } from '@/components/host-action-log'
import { PriestPanel } from '@/components/priest-panel'
import { BodyguardPanel } from '@/components/bodyguard-panel'
import { AuraSeerPanel } from '@/components/aura-seer-panel'

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
  const [winnerPlayers, setWinnerPlayers] = useState<{ name: string; role: string }[]>([])
  const [availableNightRoles, setAvailableNightRoles] = useState<Set<string>>(new Set(['werewolf']))
  const [voteCount, setVoteCount] = useState(0)
  const [eligibleVoters, setEligibleVoters] = useState(0)

  const WAKE_ORDER = ['priest', 'bodyguard', 'wolves', 'seer', 'witch', 'aura_seer'] as const
  const NIGHT_ROLE_LABELS: Record<string, string> = {
    priest: '🙏 Padre',
    bodyguard: '🛡️ Guarda-costas',
    wolves: '🐺 Lobisomens',
    seer: '🔮 Vidente',
    witch: '🧪 Bruxa',
    aura_seer: '👁️ Vidente de Aura',
  }
  const prevNightStepRef = useRef<string>('sleeping')
  const nightRolesActedRef = useRef<Set<string>>(new Set())
  const prevTurnRef = useRef<number>(0)
  const hasFlippedRef = useRef(false)

  const phase = gameState?.current_phase ?? null
  const turnIndex = gameState?.turn_index ?? 0
  const nightStep = gameState?.night_step ?? 'sleeping'
  const wolvesResolved = gameState?.wolves_resolved ?? false
  const votingOpen = gameState?.voting_open ?? false
  const dayStep = gameState?.day_step ?? 'discussion'
  const accusedId = gameState?.current_accused_id ?? null
  const gameWinner = gameState?.winner ?? null
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

  // Fetch available night roles (roles with night actions present in this game)
  useEffect(() => {
    if (!roomId) return
    supabase
      .from('players')
      .select('role')
      .eq('room_id', roomId)
      .neq('role', 'moderator')
      .in('role', ['werewolf', 'seer', 'witch', 'priest', 'bodyguard', 'aura_seer'])
      .then(({ data }) => {
        if (data) {
          setAvailableNightRoles(new Set((data as any[]).map((r) => r.role)))
        }
      })
  }, [roomId, gameState?.turn_index])

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
            if (s === 'waiting') {
              router.push(`/lobby/${roomId}`)
              return
            }
          }
        }
      )
      .subscribe()

    return () => { supabase.removeChannel(channel) }
  }, [roomId])

  // Derived state: gameEnded is true ONLY when rooms.status says so
  const gameEnded =
    roomStatus === 'finished_villagers_win' || roomStatus === 'finished_wolves_win' || roomStatus === 'finished_tanner_win'

  // Fetch winner player names when game ends
  useEffect(() => {
    if (!gameEnded) return
    async function poll() {
      const status = roomStatus
      const w = lastEvent?.winner ?? (status === 'finished_wolves_win' ? 'wolves_win' : status === 'finished_tanner_win' ? 'tanner_win' : 'villagers_win')

      let roleFilter: string | null = null
      if (w === 'wolves_win') roleFilter = 'werewolf'
      else if (w === 'tanner_win') roleFilter = 'tanner'

      if (!roleFilter) return

      const { data: playersData } = await supabase
        .from('players')
        .select('id, role')
        .eq('room_id', roomId)
        .eq('role', roleFilter)

      if (!playersData || playersData.length === 0) return

      const playerIds = (playersData as { id: string; role: string }[]).map((p) => p.id)

      const { data: profiles } = await supabase
        .from('player_profiles')
        .select('id, name')
        .in('id', playerIds)

      const nameMap = new Map<string, string>()
      if (profiles) {
        for (const p of profiles as { id: string; name: string }[]) {
          nameMap.set(p.id, p.name)
        }
      }

      const result = (playersData as { id: string; role: string }[]).map((p) => ({
        name: nameMap.get(p.id) ?? 'Desconhecido',
        role: p.role,
      }))

      setWinnerPlayers(result)
    }
    poll()
    const iv = setInterval(poll, 2000)
    return () => clearInterval(iv)
  }, [gameEnded])

  // Poll vote count during voting phase (Task 3)
  useEffect(() => {
    if (dayStep !== 'voting' || !roomId) return
    async function poll() {
      const [{ count: countVotes }, { data: alivePlayers }] = await Promise.all([
        supabase.from('votes').select('*', { count: 'exact', head: true }).eq('room_id', roomId).eq('turn_index', turnIndex),
        supabase.from('players').select('id, role').eq('room_id', roomId).eq('is_alive', true),
      ])
      const eligible = (alivePlayers ?? []).filter(
        (p: any) => p.role !== 'moderator' && p.id !== accusedId
      ).length
      setVoteCount(countVotes ?? 0)
      setEligibleVoters(eligible)
    }
    poll()
    const iv = setInterval(poll, 2000)
    return () => clearInterval(iv)
  }, [dayStep, roomId, turnIndex, accusedId])

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

  const allViewed = players.length > 0 && players.every((p) => p.isHost || !p.isAlive || p.hasViewedCard)

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

  // Dead players (non-moderator) only see the death screen
  if (!player.isAlive && player.role !== 'moderator') {
    return <DeadPlayerScreen />
  }

  // Reset night role tracking on new turn
  if (turnIndex !== prevTurnRef.current) {
    prevTurnRef.current = turnIndex
    nightRolesActedRef.current = new Set()
  }

  // Reset actedRoles when nightStep changes; track visited roles
  if (nightStep !== prevNightStepRef.current) {
    const prevStep = prevNightStepRef.current
    if (prevStep !== 'sleeping') {
      nightRolesActedRef.current = new Set([...nightRolesActedRef.current, prevStep])
    }
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

  async function handleStartDiscussion() {
    await supabase.from('game_state').update({ day_step: 'discussion' }).eq('room_id', roomId)
  }

  async function handleExitToLobby() {
    const supabase = createClient()
    await supabase.from('rooms').update({ status: 'waiting' }).eq('id', roomId)
    router.push(`/lobby/${roomId}`)
  }

  async function handleEndGame() {
    await supabase.rpc('host_end_game', { p_room_id: roomId })
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
            {phase === 'day' && (
              <>
                ☀️ Dia
                {dayStep === 'announcement' && ' - Anúncio'}
                {dayStep === 'discussion' && ' - Discussão'}
                {dayStep === 'trial' && ' - Acusação'}
                {dayStep === 'voting' && ' - Votação'}
                {dayStep === 'reveal' && ' - Julgamento'}
              </>
            )}
            {!'card_reveal night day vote'.includes(phase) && (
              <span className="text-red-500">⚠️ {phase}</span>
            )}
          </p>
        </div>

        {phase === 'day' && dayStep === 'announcement' && (
          <DayAnnouncement
            victims={(lastEvent?.victims ?? []) as { name: string; cause: string }[]}
            turnIndex={turnIndex}
            isHost={true}
            onStartDiscussion={handleStartDiscussion}
          />
        )}

        <div className="w-full px-6 pb-4">
          <HostRolePanel roomId={roomId} isHost={true} />
        </div>

        {gameWinner && (
          <div className="w-full max-w-sm mx-auto px-6 pb-4">
            <div className="rounded-xl border border-yellow-900/30 bg-yellow-950/10 px-4 py-3 text-center space-y-2">
              <p className="text-yellow-500 text-xs font-bold tracking-wide uppercase">
                🏁 Fim de Jogo
              </p>
              <button
                onClick={handleEndGame}
                className="px-5 py-2 rounded-lg text-sm font-bold bg-yellow-900/30 border border-yellow-700/50 text-yellow-400 hover:bg-yellow-800/40 transition-all duration-200 cursor-pointer"
              >
                Finalizar Partida — Revelar Vencedor
              </button>
            </div>
          </div>
        )}

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
            {(() => {
              const nextRoleToWake = WAKE_ORDER.find((s) => {
                const role = s === 'wolves' ? 'werewolf' : s
                if (!availableNightRoles.has(role)) return false
                if (s === 'wolves') return nightStep !== 'wolves' && !wolvesResolved
                if (nightRolesActedRef.current.has(s)) return false
                return nightStep !== s
              })
              if (nightStep === 'sleeping') {
                if (nextRoleToWake) {
                  return (
                    <p className="text-yellow-400 text-xs text-center">
                      📍 Vez de acordar: {NIGHT_ROLE_LABELS[nextRoleToWake]}
                    </p>
                  )
                }
                return (
                  <p className="text-emerald-500 text-xs text-center">
                    ✅ Todas as ações concluídas — resolva a noite
                  </p>
                )
              }
              return (
                <p className="text-yellow-400 text-xs text-center">
                  📍 Vez: {NIGHT_ROLE_LABELS[nightStep] ?? nightStep}
                </p>
              )
            })()}
            <div className="flex flex-wrap gap-2 justify-center">
              <button
                onClick={() => handleSetNightStep('sleeping')}
                disabled={nightStep === 'sleeping'}
                className="px-3 py-2 rounded-lg text-xs font-bold tracking-wider bg-neutral-900 border border-neutral-800 text-neutral-500 hover:text-neutral-400 disabled:opacity-30 cursor-pointer transition-all duration-200"
              >
                😴 Todos Dormindo
              </button>
              {[
                { step: 'priest', role: 'priest', label: '🙏 Acordar Padre' },
                { step: 'bodyguard', role: 'bodyguard', label: '🛡️ Acordar Guarda-costas' },
                { step: 'wolves', role: 'werewolf', label: '🐺 Acordar Lobos' },
                { step: 'seer', role: 'seer', label: '🔮 Acordar Vidente' },
                { step: 'witch', role: 'witch', label: '🧪 Acordar Bruxa' },
                { step: 'aura_seer', role: 'aura_seer', label: '👁️ Acordar Vidente de Aura' },
              ].filter((b) => availableNightRoles.has(b.role)).map((b) => {
                const disabled =
                  b.step === 'wolves'
                    ? nightStep === 'wolves' || wolvesResolved
                    : nightStep === b.step
                return (
                  <button
                    key={b.step}
                    onClick={() => handleSetNightStep(b.step)}
                    disabled={disabled}
                    className={`px-3 py-2 rounded-lg text-xs font-bold tracking-wider border ${ROLE_STYLE[b.role] ?? 'text-neutral-500 border-neutral-700'} disabled:opacity-30 cursor-pointer transition-all duration-200`}
                  >
                    {b.label}
                  </button>
                )
              })}
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

            <HostActionLog roomId={roomId} turnIndex={turnIndex} />
          </div>
        )}

        {phase === 'day' && dayStep !== 'announcement' && (
          <>
            {dayStep === 'discussion' && (
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
                <TribunalPanel
                  roomId={roomId}
                  dayStep={dayStep}
                  accusedId={accusedId}
                  turnIndex={turnIndex}
                />
              </div>
            )}

            {dayStep === 'trial' && (
              <>
                <VoteTimerPanel />
                <TribunalPanel
                  roomId={roomId}
                  dayStep={dayStep}
                  accusedId={accusedId}
                  turnIndex={turnIndex}
                />
              </>
            )}

            {dayStep === 'voting' && (
              <>
                <div className="w-full max-w-sm mx-auto px-6">
                  <p className="text-neutral-500 text-xs text-center font-mono">
                    Votos registrados: {voteCount} / {eligibleVoters}
                  </p>
                </div>
                <TribunalPanel
                  roomId={roomId}
                  dayStep={dayStep}
                  accusedId={accusedId}
                  turnIndex={turnIndex}
                />
              </>
            )}

            {dayStep === 'reveal' && (
              <>
                {lastVoteResult?.type === 'lynch' && lastVoteResult.victim_name && (
                  <div className="fixed inset-0 z-40 flex items-center justify-center pointer-events-none">
                    <div className="bg-red-950/80 border border-red-700/50 rounded-2xl px-8 py-6 text-center shadow-2xl backdrop-blur-sm">
                      <p className="text-5xl mb-3">⚖️</p>
                      <p className="text-red-400 text-xl font-black tracking-wider">
                        O acusado foi linchado pela vila!
                      </p>
                    </div>
                  </div>
                )}
                <TribunalPanel
                  roomId={roomId}
                  dayStep={dayStep}
                  accusedId={accusedId}
                  turnIndex={turnIndex}
                />
                <TribunalReveal roomId={roomId} turnIndex={turnIndex} />
              </>
            )}
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
    const myCard = CARD_CATALOG.find((c) => c.id === player?.role)

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
            role={myCard?.name ?? player.role ?? '???'}
            description={myCard?.description}
            points={myCard?.points}
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
        {renderNightPanel()}
      </div>
    )
  }

  // ── Phase: day (Tribunal) ────────────────────────────────────────
  if (phase === 'day') {
    const victims = (lastEvent?.victims ?? []) as { name: string; cause: string }[]

    return (
      <div className="flex flex-1 flex-col items-center min-h-dvh">
        {dayStep === 'announcement' && (
          <DayAnnouncement
            victims={victims}
            turnIndex={turnIndex}
            isHost={false}
          />
        )}

        {dayStep === 'discussion' && (
          <>
            <div className="flex flex-1 flex-col items-center justify-center px-6 gap-4">
              <p className="text-neutral-600 text-xs uppercase tracking-widest">
                Dia {turnIndex + 1}
              </p>
              <p className="text-4xl">📣</p>
              <p className="text-neutral-200 text-xl font-black tracking-wider text-center">
                Hora da Discussão
              </p>
              <p className="text-neutral-500 text-sm text-center max-w-xs">
                Comunique-se com a vila para entender o que está acontecendo durante a noite.
              </p>
            </div>

            <div className="w-full max-w-sm mx-auto px-6 pb-8 flex flex-col items-center gap-3">
              <TimerDisplay
                remaining={timerRemaining}
                isRunning={isTimerRunning}
                startedAt={timerStartedAt}
              />

              {hasTimer && !isTimerRunning && timerRemaining != null && timerRemaining > 0 && (
                <p className="text-neutral-600 text-[10px] uppercase tracking-widest">
                  ⏸️ Pausado pelo anfitrião
                </p>
              )}
            </div>
          </>
        )}

        {dayStep !== 'announcement' && dayStep === 'trial' && (
          <div className="flex flex-1 flex-col items-center justify-center px-6 gap-4">
            <p className="text-neutral-500 text-xs uppercase tracking-widest text-center">
              🎤 Alguém foi acusado!
            </p>
            <div className="rounded-xl border border-red-800/60 bg-red-950/20 px-4 py-3 text-center">
              <p className="text-neutral-500 text-[10px] uppercase tracking-widest">Acusado</p>
              <p className="text-red-400 text-lg font-bold mt-1">
                {players.find((p) => p.id === accusedId)?.name ?? '...'}
              </p>
            </div>
            <p className="text-neutral-700 text-xs text-center">
              O anfitrião conduzirá o julgamento...
            </p>
          </div>
        )}

        {dayStep !== 'announcement' && dayStep === 'voting' && (
          <TribunalVoting
            roomId={roomId}
            playerId={player.id}
            isAlive={isAlive}
            isAccused={player.id === accusedId}
          />
        )}

        {dayStep !== 'announcement' && dayStep === 'reveal' && (
          <>
            {lastVoteResult?.type === 'lynch' && lastVoteResult.victim_name && (
              <div className="fixed inset-0 z-40 flex items-center justify-center pointer-events-none">
                <div className="bg-red-950/80 border border-red-700/50 rounded-2xl px-8 py-6 text-center shadow-2xl backdrop-blur-sm">
                  <p className="text-5xl mb-3">⚖️</p>
                  <p className="text-red-400 text-xl font-black tracking-wider">
                    O acusado foi linchado pela vila!
                  </p>
                </div>
              </div>
            )}
            <TribunalReveal roomId={roomId} turnIndex={turnIndex} />
          </>
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

    if (player.role === 'priest') {
      if (nightStep !== 'priest') return sleepScreen()
      if (actedRoles.has('priest')) return sleepScreen()
      return (
        <div className="flex flex-1 flex-col items-center justify-center px-6 gap-6">
          <p className="text-neutral-600 text-xs uppercase tracking-widest select-none animate-pulse">
            🌙 Fechem os olhos...
          </p>
          <PriestPanel roomId={roomId} playerId={player.id} turnIndex={turnIndex} onDone={() => handleRoleDone('priest')} />
        </div>
      )
    }

    if (player.role === 'bodyguard') {
      if (nightStep !== 'bodyguard') return sleepScreen()
      if (actedRoles.has('bodyguard')) return sleepScreen()
      return (
        <div className="flex flex-1 flex-col items-center justify-center px-6 gap-6">
          <p className="text-neutral-600 text-xs uppercase tracking-widest select-none animate-pulse">
            🌙 Fechem os olhos...
          </p>
          <BodyguardPanel roomId={roomId} playerId={player.id} turnIndex={turnIndex} onDone={() => handleRoleDone('bodyguard')} />
        </div>
      )
    }

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

    if (player.role === 'aura_seer') {
      if (nightStep !== 'aura_seer') return sleepScreen()
      if (actedRoles.has('aura_seer')) return sleepScreen()
      return (
        <div className="flex flex-1 flex-col items-center justify-center px-6 gap-6">
          <p className="text-neutral-600 text-xs uppercase tracking-widest select-none animate-pulse">
            🌙 Fechem os olhos...
          </p>
          <AuraSeerPanel roomId={roomId} playerId={player.id} turnIndex={turnIndex} onDone={() => handleRoleDone('aura_seer')} />
        </div>
      )
    }

    return sleepScreen()
  }

  function renderEnded() {
    const winner = lastEvent?.winner ?? (roomStatus === 'finished_wolves_win' ? 'wolves_win' : roomStatus === 'finished_tanner_win' ? 'tanner_win' : 'villagers_win')
    const isHost = player?.isHost ?? false

    async function handleReturnToLobby() {
      await supabase.from('rooms').update({ status: 'waiting' }).eq('id', roomId)
      router.push(`/lobby/${roomId}`)
    }

    async function handleLeaveGame() {
      if (player) {
        await supabase.from('players').delete().eq('id', player.id)
      }
      router.push('/')
    }

    const tannerStyle = 'text-stone-600 drop-shadow-[0_0_20px_rgba(120,100,80,0.5)]'
    const wolfStyle = 'text-red-700 drop-shadow-[0_0_20px_rgba(185,28,28,0.5)]'
    const villagerStyle = 'text-yellow-500 drop-shadow-[0_0_20px_rgba(234,179,8,0.4)]'

    const colors =
      winner === 'tanner_win' ? tannerStyle
        : winner === 'wolves_win' ? wolfStyle
        : villagerStyle

    const displayText =
      winner === 'tanner_win' ? '👔 Curtidor Venceu'
        : winner === 'wolves_win' ? '🐺 Lobisomens Venceram'
        : '🌿 Aldeões Venceram'

    return (
      <div className="flex flex-1 flex-col items-center justify-center min-h-dvh px-6 gap-6">
        <p className="text-6xl">{
          winner === 'tanner_win' ? '👔'
            : winner === 'wolves_win' ? '🐺'
            : '🏆'
        }</p>
        <p className="text-neutral-400 text-xs uppercase tracking-widest">
          Fim de Jogo
        </p>
        <p
          className={`text-3xl font-black tracking-widest uppercase text-center ${colors}`}
        >
          {displayText}
        </p>

        {winnerPlayers.length > 0 && (
          <div className="text-center space-y-1">
            {winnerPlayers.map((p, i) => (
              <p key={i} className="text-neutral-300 text-sm font-medium">
                {p.name}
                <span className="text-neutral-600 ml-1.5 text-xs">
                  ({p.role === 'werewolf' ? 'Lobisomem' : p.role})
                </span>
              </p>
            ))}
          </div>
        )}

        <div className="flex flex-col gap-3 w-full max-w-xs mt-4">
          {isHost && (
            <button onClick={handleReturnToLobby}
              className="w-full py-3.5 rounded-2xl font-bold text-sm tracking-wider bg-neutral-900 text-neutral-400 border border-neutral-800 hover:bg-neutral-800 cursor-pointer transition-all duration-200"
            >
              Voltar para o Lobby
            </button>
          )}
          <button onClick={handleLeaveGame}
            className="w-full py-3.5 rounded-2xl font-bold text-sm tracking-wider border border-neutral-800 text-neutral-600 hover:text-red-500 hover:border-red-900/50 cursor-pointer transition-all duration-200 bg-transparent"
          >
            Sair da Sala
          </button>
        </div>
      </div>
    )
  }
}
