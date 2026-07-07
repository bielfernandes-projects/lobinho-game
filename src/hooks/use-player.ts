'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'

interface Player {
  id: string
  name: string
  role?: string | null
  isAlive: boolean
  isHost: boolean
  userId: string
  hasViewedCard: boolean
  viewedCardAt?: string | null
  createdAt: string
  soulmateId?: string | null
  hasUsedPower?: boolean
}

interface RawPlayer {
  id: string
  name: string
  role: string | null
  is_alive: boolean
  is_host: boolean
  user_id: string
  has_viewed_card: boolean
  viewed_card_at: string | null
  created_at: string
  has_used_power: boolean
  soulmate_id: string | null
}

function normalize(p: RawPlayer): Player {
  return {
    id: p.id,
    name: p.name,
    role: p.role,
    isAlive: p.is_alive,
    isHost: p.is_host,
    userId: p.user_id,
    hasViewedCard: p.has_viewed_card,
    viewedCardAt: p.viewed_card_at,
    createdAt: p.created_at,
    soulmateId: p.soulmate_id,
    hasUsedPower: p.has_used_power,
  }
}

export function useCurrentPlayer(roomId: string) {
  const [player, setPlayer] = useState<Player | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const supabase = createClient()
    let myUserId: string | undefined

    async function load() {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        setLoading(false)
        return
      }
      myUserId = user.id

      const { data } = await supabase
        .from('players')
        .select('*')
        .eq('room_id', roomId)
        .eq('user_id', user.id)
        .single()

      if (data) setPlayer(normalize(data as RawPlayer))
      setLoading(false)
    }

    load()

    // Polling de fallback a cada 5s (caso Realtime caia)
    const pollInterval = setInterval(load, 5000)

    const channel = supabase
      .channel(`self:${roomId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'players',
          filter: `room_id=eq.${roomId}`,
        },
        (payload) => {
          if (!payload.new || !myUserId) return
          const raw = payload.new as RawPlayer
          if (raw.user_id === myUserId) {
            setPlayer(normalize(raw))
          }
        }
      )
      .subscribe()

    return () => {
      clearInterval(pollInterval)
      supabase.removeChannel(channel)
    }
  }, [roomId])

  return { player, loading }
}
