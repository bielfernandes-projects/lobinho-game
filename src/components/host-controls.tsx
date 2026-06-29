'use client'

import { useState, useEffect, useRef } from 'react'
import { createClient } from '@/lib/supabase/client'

interface HostControlsProps {
  roomId: string
  mode: 'start' | 'advance' | 'resolve_night_wolves' | 'resolve_night' | 'resolve_vote'
  allViewed?: boolean
  advanceLabel?: string
  turnIndex?: number
  wolvesResolved?: boolean
}

export function HostControls({ roomId, mode, allViewed = true, advanceLabel = 'Avançar', turnIndex = 0, wolvesResolved = false }: HostControlsProps) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [actionCount, setActionCount] = useState(0)
  const [voteCount, setVoteCount] = useState(0)
  const [aliveCount, setAliveCount] = useState(0)
  const supabase = createClient()
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)

  useEffect(() => {
    if (mode === 'resolve_night_wolves') {
      poll()
      pollRef.current = setInterval(poll, 2000)
    }

    if (mode === 'resolve_vote') {
      pollVotes()
      pollRef.current = setInterval(pollVotes, 2000)
    }

    return () => {
      if (pollRef.current) clearInterval(pollRef.current)
    }
  }, [mode, roomId, turnIndex])

  async function poll() {
    const { count } = await supabase
      .from('night_actions')
      .select('*', { count: 'exact', head: true })
      .eq('room_id', roomId)
      .eq('turn_index', turnIndex)
      .eq('action_type', 'werewolf_kill')
    if (count !== null) setActionCount(count)
  }

  async function pollVotes() {
    const { data: profiles } = await supabase
      .from('player_profiles')
      .select('id, is_alive')
      .eq('room_id', roomId)

    if (profiles) {
      setAliveCount((profiles as any[]).filter((p) => p.is_alive).length)
    }

    const { count } = await supabase
      .from('votes')
      .select('*', { count: 'exact', head: true })
      .eq('room_id', roomId)
      .eq('turn_index', turnIndex)
    if (count !== null) setVoteCount(count)
  }

  async function handleStart() {
    setBusy(true); setError('')
    const { error: e } = await supabase.rpc('start_game', { p_room_id: roomId })
    if (e) { setError(e.message); setBusy(false); return }
    setBusy(false)
  }

  async function handleAdvance() {
    setBusy(true); setError('')
    const { error: e } = await supabase.rpc('advance_phase', { p_room_id: roomId })
    if (e) { setError(e.message); setBusy(false); return }
    setBusy(false)
  }

  async function handleResolveNightWolves() {
    setBusy(true); setError('')
    const { error: e } = await supabase.rpc('resolve_night_wolves', { p_room_id: roomId })
    if (e) { setError(e.message); setBusy(false); return }
    setBusy(false)
  }

  async function handleResolveNight() {
    setBusy(true); setError('')
    const { error: e } = await supabase.rpc('resolve_night', { p_room_id: roomId })
    if (e) { setError(e.message); setBusy(false); return }
    setBusy(false)
  }

  async function handleResolveVote() {
    setBusy(true); setError('')
    const { error: e } = await supabase.rpc('resolve_day_vote', { p_room_id: roomId })
    if (e) { setError(e.message); setBusy(false); return }
    setBusy(false)
  }

  if (mode === 'start') {
    return (
      <div className="w-full max-w-sm mx-auto mt-6">
        <button onClick={handleStart} disabled={busy}
          className="
            w-full py-4 rounded-2xl font-bold text-lg tracking-wider
            bg-red-700 text-white hover:bg-red-600 active:bg-red-800
            disabled:opacity-40 disabled:cursor-not-allowed
            shadow-lg shadow-red-900/40 animate-pulse
            transition-all duration-200 cursor-pointer disabled:animate-none
          "
        >
          {busy ? 'Iniciando...' : 'Iniciar Jogo'}
        </button>
        <p className="text-neutral-600 text-xs text-center mt-2">
          Você é o Host — ao iniciar, as funções serão sorteadas
        </p>
        {error && <p className="text-red-500 text-xs text-center mt-2">{error}</p>}
      </div>
    )
  }

  if (mode === 'resolve_night_wolves') {
    return (
      <div className="w-full max-w-sm mx-auto mt-6 space-y-2">
        <div className="text-center">
          <p className="text-neutral-600 text-xs">
            🐺 Votos dos lobos: {actionCount}
          </p>
        </div>
        <button onClick={handleResolveNightWolves} disabled={busy}
          className="
            w-full py-4 rounded-2xl font-bold text-lg tracking-wider
            bg-neutral-800 text-red-400 border border-red-900/50
            hover:bg-red-900/30 active:bg-red-950/40
            disabled:opacity-30 disabled:cursor-not-allowed
            transition-all duration-200 cursor-pointer
          "
        >
          {busy ? 'Resolvendo...' : '🐺 Resolver Ataque dos Lobos'}
        </button>
        {error && <p className="text-red-500 text-xs text-center">{error}</p>}
      </div>
    )
  }

  if (mode === 'resolve_night') {
    return (
      <div className="w-full max-w-sm mx-auto mt-6 space-y-2">
        <button onClick={handleResolveNight} disabled={busy}
          className="
            w-full py-4 rounded-2xl font-bold text-lg tracking-wider
            bg-neutral-800 text-emerald-400 border border-emerald-900/50
            hover:bg-emerald-900/30 active:bg-emerald-950/40
            disabled:opacity-30 disabled:cursor-not-allowed
            transition-all duration-200 cursor-pointer
          "
        >
          {busy ? 'Resolvendo...' : '🌙 Resolver Noite'}
        </button>
        {error && <p className="text-red-500 text-xs text-center">{error}</p>}
      </div>
    )
  }

  if (mode === 'resolve_vote') {
    const threshold = Math.floor(aliveCount / 2) + 1
    return (
      <div className="w-full max-w-sm mx-auto mt-6 space-y-2">
        <div className="text-center">
          <p className="text-neutral-600 text-xs">
            🗳️ Votos: {voteCount}/{aliveCount} ({threshold} necessários)
          </p>
        </div>
        <button onClick={handleResolveVote} disabled={busy}
          className="
            w-full py-4 rounded-2xl font-bold text-lg tracking-wider
            bg-neutral-800 text-red-400 border border-red-900/50
            hover:bg-red-900/30 active:bg-red-950/40
            disabled:opacity-30 disabled:cursor-not-allowed
            transition-all duration-200 cursor-pointer
          "
        >
          {busy ? 'Resolvendo...' : '⚖️ Resolver Votação'}
        </button>
        {error && <p className="text-red-500 text-xs text-center">{error}</p>}
      </div>
    )
  }

  // advance mode (card_reveal→night, day→vote)
  return (
    <div className="w-full max-w-sm mx-auto mt-6">
      <button onClick={handleAdvance} disabled={busy || !allViewed}
        className="
          w-full py-4 rounded-2xl font-bold text-lg tracking-wider
          bg-red-700 text-white hover:bg-red-600 active:bg-red-800
          disabled:opacity-40 disabled:cursor-not-allowed
          shadow-lg shadow-red-900/40
          transition-all duration-200 cursor-pointer
        "
      >
        {busy ? 'Avançando...'
          : !allViewed ? 'Aguardando leitura...'
          : advanceLabel}
      </button>
      {error && <p className="text-red-500 text-xs text-center mt-2">{error}</p>}
    </div>
  )
}
