'use client'

import { useParams, useRouter } from 'next/navigation'
import { useEffect, useState, useRef } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useCurrentPlayer } from '@/hooks/use-player'
import { useRoomPlayers, useGameState } from '@/hooks/use-room'
import { FlipCard } from '@/components/flip-card'
import { CARD_CATALOG, ROLE_STYLE } from '@/lib/cards'
import { getRevealedRoleText } from '@/lib/reveal'
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
import { CupidPanel } from '@/components/cupid-panel'
import { CultLeaderPanel } from '@/components/cult-leader-panel'
import { GraveyardList } from '@/components/graveyard-list'
import type { RevealMode } from '@/lib/reveal'

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
  const [resolvedActions, setResolvedActions] = useState<Set<string>>(new Set())
  const [voteCount, setVoteCount] = useState(0)
  const [eligibleVoters, setEligibleVoters] = useState(0)
  const [soulmateName, setSoulmateName] = useState<string | null>(null)
  const [revealMode, setRevealMode] = useState<RevealMode>('total')
  const [wolvesFrenzy, setWolvesFrenzy] = useState(false)
  const [infectedId, setInfectedId] = useState<string | null>(null)
  const [showInfectionBanner, setShowInfectionBanner] = useState(false)

  const WAKE_ORDER = ['cupid', 'priest', 'bodyguard', 'wolves', 'witch', 'seer', 'aura_seer', 'cult_leader'] as const
  const STEP_TO_ACTION_TYPES: Record<string, string[]> = {
    cupid: [],
    priest: ['priest_bless'],
    bodyguard: ['bodyguard_protect'],
    wolves: ['werewolf_kill'],
    witch: ['witch_save', 'witch_poison'],
    seer: ['seer_investigate'],
    aura_seer: ['aura_investigate'],
    cult_leader: ['cult_convert'],
  }
  const NIGHT_ROLE_LABELS: Record<string, string> = {
    cupid: '💘 Cupido',
    priest: '🙏 Padre',
    bodyguard: '🛡️ Guarda-costas',
    wolves: '🐺 Lobisomens',
    witch: '🧪 Bruxa',
    seer: '🔮 Vidente',
    aura_seer: '👁️ Vidente de Aura',
    cult_leader: '🔮 Líder de Culto',
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
      .select('role, has_used_power')
      .eq('room_id', roomId)
      .neq('role', 'moderator')
      .in('role', ['werewolf', 'wolf_cub', 'alpha_wolf', 'lone_wolf', 'seer', 'witch', 'priest', 'bodyguard', 'aura_seer', 'cupid', 'cult_leader'])
      .then(({ data }) => {
        if (data) {
          const roles = (data as any[])
            .filter((r) => !(r.role === 'priest' && r.has_used_power))
            .map((r) => r.role)
          setAvailableNightRoles(new Set(roles))
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
          if (payload.new && 'wolves_frenzy' in payload.new) {
            setWolvesFrenzy(payload.new.wolves_frenzy as boolean)
          }
        }
      )
      .subscribe()

    return () => { supabase.removeChannel(channel) }
  }, [roomId])

  // Derived state: gameEnded is true ONLY when rooms.status says so
  const gameEnded =
    roomStatus === 'finished_villagers_win' || roomStatus === 'finished_wolves_win' || roomStatus === 'finished_tanner_win' ||
    roomStatus === 'finished_soulmates_win' || roomStatus === 'finished_cult_win' || roomStatus === 'finished_lone_wolf_win'

  // Fetch ALL player names and roles when game ends (bypasses RLS via SECURITY DEFINER RPC)
  useEffect(() => {
    if (!gameEnded && !gameWinner) return
    async function poll() {
      const status = roomStatus
      const w = gameWinner
        ?? lastEvent?.winner
        ?? (status === 'finished_wolves_win' ? 'wolves_win'
          : status === 'finished_tanner_win' ? 'tanner_win'
          : status === 'finished_lone_wolf_win' ? 'lone_wolf_win'
          : status === 'finished_soulmates_win' ? 'soulmates_win'
          : status === 'finished_cult_win' ? 'cult_win'
          : 'villagers_win')

      const winnerType = w as string

      const { data } = await supabase.rpc('get_revealed_players', { p_room_id: roomId })

      const allPlayers: { id: string; name: string; role: string; in_cult: boolean; soulmate_id: string | null }[] = (data as any[]) ?? []

      const getTeam = (roleId: string) => CARD_CATALOG.find((c) => c.id === roleId)?.team

      let result: { name: string; role: string }[]
      if (winnerType === 'soulmates_win') {
        result = allPlayers
          .filter((p) => p.soulmate_id != null)
          .map((p) => ({ name: p.name, role: p.role }))
      } else if (winnerType === 'cult_win') {
        result = allPlayers
          .filter((p) => p.role === 'cult_leader' || p.in_cult)
          .map((p) => ({ name: p.name, role: p.role }))
      } else if (winnerType === 'lone_wolf_win') {
        result = allPlayers
          .filter((p) => p.role === 'lone_wolf')
          .map((p) => ({ name: p.name, role: p.role }))
      } else if (winnerType === 'wolves_win') {
        result = allPlayers
          .filter((p) => getTeam(p.role) === 'wolf')
          .map((p) => ({ name: p.name, role: p.role }))
      } else if (winnerType === 'tanner_win') {
        result = allPlayers
          .filter((p) => p.role === 'tanner')
          .map((p) => ({ name: p.name, role: p.role }))
      } else {
        result = allPlayers
          .filter((p) => getTeam(p.role) === 'village')
          .map((p) => ({ name: p.name, role: p.role }))
      }

      setWinnerPlayers(result)
    }
    poll()
    const iv = setInterval(poll, 2000)
    return () => clearInterval(iv)
  }, [gameEnded, gameWinner])

  // Fetch reveal_mode + wolves_frenzy from rooms
  useEffect(() => {
    if (!roomId) return
    supabase
      .from('rooms')
      .select('reveal_mode, wolves_frenzy')
      .eq('id', roomId)
      .single()
      .then(({ data }) => {
        if (data?.reveal_mode) setRevealMode(data.reveal_mode as RevealMode)
        if (data?.wolves_frenzy != null) setWolvesFrenzy(data.wolves_frenzy as boolean)
      })
  }, [roomId])

  // Fetch soulmate name if player has one
  useEffect(() => {
    if (!player?.soulmateId) return
    supabase
      .from('players')
      .select('name')
      .eq('id', player.soulmateId)
      .single()
      .then(({ data }) => {
        if (data) setSoulmateName((data as any).name)
      })
  }, [player?.soulmateId])

  // Check if current player was infected by Alpha Wolf
  useEffect(() => {
    if (!player || !lastEvent || showInfectionBanner) return
    const infected = (lastEvent as any)?.infected_id
    if (infected === player.id) {
      setShowInfectionBanner(true)
    }
  }, [lastEvent, player, showInfectionBanner])

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

  // Poll night_actions to mark which night roles have already acted
  useEffect(() => {
    if (phase !== 'night' || !roomId) return
    async function poll() {
      const { data } = await supabase
        .from('night_actions')
        .select('action_type')
        .eq('room_id', roomId)
        .eq('turn_index', turnIndex)
      if (data) {
        const types = new Set(data.map((r: any) => r.action_type))
        const resolved = new Set<string>()
        for (const [step, actionTypes] of Object.entries(STEP_TO_ACTION_TYPES)) {
          if (actionTypes.some((at) => types.has(at))) {
            resolved.add(step)
          }
        }
        setResolvedActions(resolved)
      }
    }
    poll()
    const iv = setInterval(poll, 2000)
    return () => clearInterval(iv)
  }, [phase, roomId, turnIndex])

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

  const soulmateBanner = !isHost && soulmateName && (
    <div className="fixed bottom-4 right-4 text-[10px] text-neutral-600 opacity-60 select-none z-50">
      💕 Alma Gêmea: {soulmateName}
    </div>
  )

  const infectionBanner = showInfectionBanner && (
    <div className="fixed bottom-4 left-4 text-[10px] text-red-500/80 select-none z-50 bg-red-950/40 px-3 py-1.5 rounded-lg border border-red-800/30 backdrop-blur-sm">
      🐺 Você foi mordido pelo Lobo Alfa e agora pertence à Alcatéia!
    </div>
  )

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

  async function handleAdvanceAfterPrince() {
    await supabase.rpc('advance_to_night', { p_room_id: roomId })
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
            victims={(lastEvent?.victims ?? []) as { name: string; cause: string; role?: string }[]}
            turnIndex={turnIndex}
            isHost={true}
            revealMode="total"
            onStartDiscussion={handleStartDiscussion}
          />
        )}

        {phase === 'day' && dayStep === 'prince_reveal' && lastEvent?.type === 'prince_reveal' && (
          <div className="w-full max-w-sm mx-auto space-y-4 px-6 py-4">
            <div className="fixed inset-0 z-40 flex items-center justify-center pointer-events-none">
              <div className="bg-cyan-950/80 border border-cyan-700/50 rounded-2xl px-5 py-4 text-center shadow-2xl backdrop-blur-sm max-w-[85vw]">
                <p className="text-3xl mb-2">🤴</p>
                <p className="text-cyan-400 text-sm font-black tracking-wider">
                  O Príncipe revelou sua identidade e impediu a execução!
                </p>
              </div>
            </div>
            <div className="pt-24">
              <button
                onClick={handleAdvanceAfterPrince}
                className="w-full py-4 rounded-2xl font-bold text-lg tracking-wider bg-red-700 text-white hover:bg-red-600 active:bg-red-800 shadow-lg shadow-red-900/40 transition-all duration-200 cursor-pointer"
              >
                🌙 Avançar para Noite
              </button>
            </div>
          </div>
        )}

        {phase === 'day' && dayStep === 'lynch_reveal' && lastVoteResult?.type === 'lynch' && (
          <div className="w-full max-w-sm mx-auto space-y-4 px-6 py-4">
            <div className="fixed inset-0 z-40 flex items-center justify-center pointer-events-none">
              <div className="bg-red-950/80 border border-red-700/50 rounded-2xl px-5 py-4 text-center shadow-2xl backdrop-blur-sm max-w-[85vw]">
                <p className="text-3xl mb-2">⚖️</p>
                <p className="text-red-400 text-sm font-black tracking-wider">
                  {lastVoteResult.soulmate_name
                    ? `${lastVoteResult.victim_name} foi linchado(a) pela vila! ${lastVoteResult.soulmate_name} morreu de coração partido.`
                    : `O acusado foi linchado pela vila!`}
                </p>
                {lastVoteResult.victim_role && (
                  <p className="text-neutral-500 text-[10px] mt-1 uppercase tracking-wider">
                    {getRevealedRoleText(lastVoteResult.victim_role as string, 'total')}
                  </p>
                )}
              </div>
            </div>
            <div className="pt-24">
              <button
                onClick={handleAdvanceAfterPrince}
                className="w-full py-4 rounded-2xl font-bold text-lg tracking-wider bg-red-700 text-white hover:bg-red-600 active:bg-red-800 shadow-lg shadow-red-900/40 transition-all duration-200 cursor-pointer"
              >
                🌙 Avançar para Noite
              </button>
            </div>
          </div>
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
              const WOLF_ROLES = ['werewolf', 'wolf_cub', 'alpha_wolf', 'lone_wolf']
              const nextRoleToWake = WAKE_ORDER.find((s) => {
                if (s === 'wolves') {
                  if (!WOLF_ROLES.some((r) => availableNightRoles.has(r))) return false
                  return nightStep !== 'wolves' && !wolvesResolved
                }
                if (!availableNightRoles.has(s)) return false
                if (s === 'cupid' && turnIndex !== 1) return false
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
                className="px-3 py-2 rounded-lg text-xs font-bold tracking-wider bg-neutral-900 border border-neutral-800 text-neutral-500 hover:text-neutral-400 cursor-pointer transition-all duration-200"
              >
                😴 Todos Dormindo
              </button>
              {[
                { step: 'cupid', role: 'cupid', label: '💘 Acordar Cupido' },
                { step: 'priest', role: 'priest', label: '🙏 Acordar Padre' },
                { step: 'bodyguard', role: 'bodyguard', label: '🛡️ Acordar Guarda-costas' },
                { step: 'wolves', role: 'werewolf', label: '🐺 Acordar Lobos' },
                { step: 'witch', role: 'witch', label: '🧪 Acordar Bruxa' },
                { step: 'seer', role: 'seer', label: '🔮 Acordar Vidente' },
                { step: 'aura_seer', role: 'aura_seer', label: '👁️ Acordar Vidente de Aura' },
                { step: 'cult_leader', role: 'cult_leader', label: '🔮 Acordar Líder de Culto' },
              ].filter((b) => {
                if (b.step === 'cupid' && turnIndex !== 1) return false
                if (b.step === 'wolves') {
                  return ['werewolf', 'wolf_cub', 'alpha_wolf', 'lone_wolf'].some((r) => availableNightRoles.has(r))
                }
                return availableNightRoles.has(b.role)
              }).map((b) => {
                const isWolves = b.step === 'wolves'
                const actionDone = !isWolves && resolvedActions.has(b.step)
                const disabled = isWolves
                  ? nightStep === 'wolves' || wolvesResolved
                  : nightStep === b.step || actionDone
                return (
                  <button
                    key={b.step}
                    onClick={() => handleSetNightStep(b.step)}
                    disabled={disabled}
                    className={`px-3 py-2 rounded-lg text-xs font-bold tracking-wider border ${ROLE_STYLE[b.role] ?? 'text-neutral-500 border-neutral-700'} disabled:opacity-30 transition-all duration-200 ${actionDone ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}`}
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
        {soulmateBanner}
        {infectionBanner}
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
            revealMode={revealMode}
          />
        )}

        {dayStep === 'prince_reveal' && lastEvent?.type === 'prince_reveal' && (
          <div className="flex flex-1 flex-col items-center justify-center px-6 gap-4">
            <div className="fixed inset-0 z-40 flex items-center justify-center pointer-events-none">
              <div className="bg-cyan-950/80 border border-cyan-700/50 rounded-2xl px-5 py-4 text-center shadow-2xl backdrop-blur-sm max-w-[85vw]">
                <p className="text-3xl mb-2">🤴</p>
                <p className="text-cyan-400 text-sm font-black tracking-wider">
                  O Príncipe revelou sua identidade e impediu a execução!
                </p>
              </div>
            </div>
            <p className="text-neutral-500 text-sm text-center mt-32">
              O dia foi cancelado pela autoridade do Príncipe. Todos vão dormir.
            </p>
          </div>
        )}

        {dayStep === 'lynch_reveal' && lastVoteResult?.type === 'lynch' && (
          <div className="flex flex-1 flex-col items-center justify-center px-6 gap-4">
            <div className="fixed inset-0 z-40 flex items-center justify-center pointer-events-none">
              <div className="bg-red-950/80 border border-red-700/50 rounded-2xl px-5 py-4 text-center shadow-2xl backdrop-blur-sm max-w-[85vw]">
                <p className="text-3xl mb-2">⚖️</p>
                <p className="text-red-400 text-sm font-black tracking-wider">
                  {lastVoteResult.soulmate_name
                    ? `${lastVoteResult.victim_name} foi linchado(a) pela vila! ${lastVoteResult.soulmate_name} morreu de coração partido.`
                    : `O acusado foi linchado pela vila!`}
                </p>
                {lastVoteResult.victim_role && (
                  <p className="text-neutral-500 text-[10px] mt-1 uppercase tracking-wider">
                    {getRevealedRoleText(lastVoteResult.victim_role as string, revealMode)}
                  </p>
                )}
              </div>
            </div>
            <p className="text-neutral-500 text-sm text-center mt-32">
              A noite está chegando...
            </p>
          </div>
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
            <TribunalReveal roomId={roomId} turnIndex={turnIndex} />
          </>
        )}
        {soulmateBanner}
        {infectionBanner}

        <div className="mt-auto pt-4 pb-6">
          <GraveyardList roomId={roomId} revealMode={revealMode} />
        </div>
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
  const wolfVictimName2 = (lastEvent as any)?.victims?.[1]?.victim_name ?? null

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

    if (player.role === 'cupid') {
      if (nightStep !== 'cupid') return sleepScreen()
      if (turnIndex !== 1) return sleepScreen()
      if (actedRoles.has('cupid')) return sleepScreen()
      return (
        <div className="flex flex-1 flex-col items-center justify-center px-6 gap-6">
          <p className="text-neutral-600 text-xs uppercase tracking-widest select-none animate-pulse">
            🌙 Fechem os olhos...
          </p>
          <CupidPanel roomId={roomId} playerId={player.id} onDone={() => handleRoleDone('cupid')} />
        </div>
      )
    }

    if (['werewolf', 'wolf_cub', 'alpha_wolf', 'lone_wolf'].includes(player.role ?? '')) {
      if (nightStep !== 'wolves') return sleepScreen()
      if (actedRoles.has('werewolf')) return sleepScreen()
      return (
        <div className="flex flex-1 flex-col items-center justify-center px-6 gap-6">
          <p className="text-neutral-600 text-xs uppercase tracking-widest select-none animate-pulse">
            🌙 Fechem os olhos...
          </p>
          <WerewolfPanel
            roomId={roomId}
            playerId={player.id}
            turnIndex={turnIndex}
            isFirstNight={turnIndex === 1}
            isAlpha={player.role === 'alpha_wolf'}
            alphaHasPower={player.role === 'alpha_wolf' && !player.hasUsedPower}
            wolvesFrenzy={wolvesFrenzy}
            onDone={() => handleRoleDone('werewolf')}
          />
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
      return (
        <div className="flex flex-1 flex-col items-center justify-center px-6 gap-6">
          <p className="text-neutral-600 text-xs uppercase tracking-widest select-none animate-pulse">
            🌙 Fechem os olhos...
          </p>
          <AuraSeerPanel roomId={roomId} playerId={player.id} turnIndex={turnIndex} onDone={() => handleRoleDone('aura_seer')} />
        </div>
      )
    }

    if (player.role === 'cult_leader') {
      if (nightStep !== 'cult_leader') return sleepScreen()
      if (actedRoles.has('cult_leader')) return sleepScreen()
      return (
        <div className="flex flex-1 flex-col items-center justify-center px-6 gap-6">
          <p className="text-neutral-600 text-xs uppercase tracking-widest select-none animate-pulse">
            🌙 Fechem os olhos...
          </p>
          <CultLeaderPanel roomId={roomId} playerId={player.id} onDone={() => handleRoleDone('cult_leader')} />
        </div>
      )
    }

    return sleepScreen()
  }

  function renderEnded() {
    const winner = gameWinner ?? lastEvent?.winner ?? (roomStatus === 'finished_wolves_win' ? 'wolves_win' : roomStatus === 'finished_tanner_win' ? 'tanner_win' : roomStatus === 'finished_lone_wolf_win' ? 'lone_wolf_win' : 'villagers_win')
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

    const soulmateStyle = 'text-pink-400 drop-shadow-[0_0_20px_rgba(236,72,153,0.5)]'
    const cultStyle = 'text-violet-400 drop-shadow-[0_0_20px_rgba(139,92,246,0.5)]'
    const tannerStyle = 'text-stone-600 drop-shadow-[0_0_20px_rgba(120,100,80,0.5)]'
    const wolfStyle = 'text-red-700 drop-shadow-[0_0_20px_rgba(185,28,28,0.5)]'
    const loneWolfStyle = 'text-orange-500 drop-shadow-[0_0_20px_rgba(249,115,22,0.5)]'
    const villagerStyle = 'text-yellow-500 drop-shadow-[0_0_20px_rgba(234,179,8,0.4)]'

    const colors =
      winner === 'soulmates_win' ? soulmateStyle
        : winner === 'cult_win' ? cultStyle
        : winner === 'tanner_win' ? tannerStyle
        : winner === 'wolves_win' ? wolfStyle
        : winner === 'lone_wolf_win' ? loneWolfStyle
        : villagerStyle

    const displayText =
      winner === 'soulmates_win' ? 'O AMOR VENCEU!'
        : winner === 'cult_win' ? 'O CULTO DOMINOU A VILA!'
        : winner === 'tanner_win' ? 'O CURTIDOR VENCEU'
        : winner === 'wolves_win' ? 'VITÓRIA DO TIME DOS LOBOS'
        : winner === 'lone_wolf_win' ? 'O LOBO SOLITÁRIO VENCEU!'
        : 'VITÓRIA DO TIME DA VILA'

    return (
      <div className="flex flex-1 flex-col items-center justify-center min-h-dvh px-6 gap-6">
        <p className="text-6xl">{
          winner === 'soulmates_win' ? '💕'
            : winner === 'cult_win' ? '🔮'
            : winner === 'tanner_win' ? '👔'
            : winner === 'wolves_win' ? '🐺'
            : winner === 'lone_wolf_win' ? '🐺'
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
