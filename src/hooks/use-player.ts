'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import type { RealtimeChannel } from '@supabase/supabase-js'

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
    let channelRef: RealtimeChannel | null = null

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

    function setupChannel() {
      if (!myUserId) return
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
        .subscribe((status: string) => {
          if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
            console.warn('[useCurrentPlayer] channel error, re-subscribing in 3s')
            setTimeout(() => {
              if (channelRef) supabase.removeChannel(channelRef)
              setupChannel()
            }, 3000)
          }
        })
      channelRef = channel
    }

    // Aguarda o primeiro load para obter myUserId antes de subscrever
    load().then(() => setupChannel())

    // Polling de fallback a cada 5s (caso Realtime caia)
    const pollInterval = setInterval(load, 5000)

    return () => {
      clearInterval(pollInterval)
      if (channelRef) supabase.removeChannel(channelRef)
    }
  }, [roomId])

  return { player, loading }
}
