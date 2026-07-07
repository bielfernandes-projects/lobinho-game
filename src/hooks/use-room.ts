'use client'

import { useEffect, useRef, useState } from 'react'
import { createClient } from '@/lib/supabase/client'

interface ProfileRow {
  id: string
  name: string
  is_host: boolean
  is_alive: boolean
  has_viewed_card: boolean
  user_id: string
}

export interface RoomProfile {
  id: string
  name: string
  isHost: boolean
  isAlive: boolean
  hasViewedCard: boolean
  userId: string
}

export interface GameStateRow {
  current_phase: string
  turn_index: number
  night_step: string
  wolves_resolved: boolean
  voting_open: boolean
  day_step: string
  current_accused_id: string | null
  winner: string | null
  last_event: {
    type: string
    victim_id?: string | null
    victim_name?: string | null
    winner?: string | null
    victims?: { name: string; cause: string; role?: string }[]
    wolf_votes?: number
    victim_role?: string | null
    soulmate_role?: string | null
  } | null
  last_vote_result: {
    type: string
    victim_name?: string | null
    victim_role?: string | null
    soulmate_name?: string | null
    soulmate_role?: string | null
  } | null
  timer_duration: number | null
  timer_remaining: number | null
  is_timer_running: boolean
  timer_started_at: string | null
}

function normalize(row: ProfileRow): RoomProfile {
  return {
    id: row.id,
    name: row.name,
    isHost: row.is_host,
    isAlive: row.is_alive,
    hasViewedCard: row.has_viewed_card,
    userId: row.user_id,
  }
}

export function useRoomPlayers(roomId: string) {
  const [players, setPlayers] = useState<RoomProfile[]>([])
  const [loading, setLoading] = useState(true)
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null)

  useEffect(() => {
    const supabase = createClient()

    async function poll() {
      const { data } = await supabase
        .from('player_profiles')
        .select('id, name, is_host, is_alive, has_viewed_card, user_id')
        .eq('room_id', roomId)

      if (data) {
        setPlayers((data as ProfileRow[]).map(normalize))
      }
      setLoading(false)
    }

    poll()
    intervalRef.current = setInterval(poll, 4000)

    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current)
    }
  }, [roomId])

  return { players, loading }
}

export function useGameState(roomId: string) {
  const [state, setState] = useState<GameStateRow | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const supabase = createClient()

    async function load() {
      const { data, error } = await supabase
        .from('game_state')
        .select('current_phase, turn_index, night_step, wolves_resolved, voting_open, day_step, current_accused_id, winner, last_event, last_vote_result, timer_duration, timer_remaining, is_timer_running, timer_started_at')
        .eq('room_id', roomId)
        .single()

      if (error) {
        // PGRST116 = row não existe (game_state deletado ao voltar pro lobby)
        if (error.code !== 'PGRST116') {
          console.error('[useGameState] query error:', error)
        }
        setLoading(false)
        return
      }
      if (data) setState(data as GameStateRow)
      setLoading(false)
    }

    load()

    // Polling de fallback a cada 5s (caso Realtime caia)
    const pollInterval = setInterval(load, 5000)

    const channel = supabase
      .channel(`game-state:${roomId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'game_state',
          filter: `room_id=eq.${roomId}`,
        },
        (payload) => {
          if (payload.new) {
            setState(payload.new as GameStateRow)
          }
        }
      )
      .subscribe()

    return () => {
      clearInterval(pollInterval)
      supabase.removeChannel(channel)
    }
  }, [roomId])

  return { gameState: state, loading }
}
