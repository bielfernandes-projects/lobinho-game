'use client'

import { useParams, useRouter } from 'next/navigation'
import { useEffect, useState, useRef } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useCurrentPlayer } from '@/hooks/use-player'
import { useRoomPlayers } from '@/hooks/use-room'
import { PlayerList } from '@/components/player-list'
import { HostControls } from '@/components/host-controls'

export default function LobbyScreen() {
  const params = useParams()
  const router = useRouter()
  const roomId = params.id as string
  const supabase = createClient()

  const { player, loading: playerLoading } = useCurrentPlayer(roomId)
  const { players, loading: playersLoading } = useRoomPlayers(roomId)

  const [roomStatus, setRoomStatus] = useState<string | null>(null)
  const [roomPin, setRoomPin] = useState('')
  const [transferError, setTransferError] = useState('')
  const [transferBusy, setTransferBusy] = useState(false)
  const redirectedRef = useRef(false)

  async function handleTransferHost(newHostPlayerId: string) {
    setTransferBusy(true); setTransferError('')
    const { error: e } = await supabase.rpc('transfer_host', {
      p_room_id: roomId,
      p_new_host_player_id: newHostPlayerId,
    })
    if (e) { setTransferError(e.message); setTransferBusy(false); return }
    setTransferBusy(false)
  }

  /*
   * Wake Lock API:
   *   const wakeLock = await navigator.wakeLock.request('screen');
   * Liberar ao sair: await wakeLock.release();
   * Sugestao: usar useEffect + ref, chamar release em cleanup.
   */

  // Load room metadata + watch for status change
  useEffect(() => {
    async function loadRoom() {
      const { data } = await supabase
        .from('rooms')
        .select('status, pin_code')
        .eq('id', roomId)
        .single()

      if (data) {
        setRoomStatus(data.status)
        setRoomPin(data.pin_code)
      } else {
        if (!redirectedRef.current) {
          redirectedRef.current = true
          router.push('/')
        }
      }
    }

    loadRoom()
  }, [roomId, router])

  // Watch for room status → playing → redirect to game
  useEffect(() => {
    if (roomStatus === 'playing') {
      router.push(`/game/${roomId}`)
      return
    }

    const channel = supabase
      .channel(`room-status:${roomId}`)
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
            const newStatus = payload.new.status as string
            setRoomStatus(newStatus)
            if (newStatus === 'playing') {
              router.push(`/game/${roomId}`)
            }
          }
        }
      )
      .subscribe()

    return () => { supabase.removeChannel(channel) }
  }, [roomId, roomStatus, router])

  // Presence — track current player
  useEffect(() => {
    if (!player) return

    const channel = supabase.channel(`presence:${roomId}`)

    channel
      .on('presence', { event: 'sync' }, () => {})
      .subscribe(async (status) => {
        if (status === 'SUBSCRIBED') {
          await channel.track({
            user_id: player.userId,
            player_id: player.id,
            player_name: player.name,
            is_host: player.isHost,
          })
        }
      })

    return () => { supabase.removeChannel(channel) }
  }, [player, roomId])

  if (playerLoading || playersLoading) {
    return (
      <div className="flex flex-1 items-center justify-center min-h-dvh">
        <div className="w-8 h-8 border-2 border-red-700 border-t-transparent rounded-full animate-spin" />
      </div>
    )
  }

  if (!player) {
    return (
      <div className="flex flex-1 flex-col items-center justify-center px-6 min-h-dvh gap-4">
        <p className="text-neutral-500 text-sm">Sessão não encontrada</p>
        <button
          onClick={() => router.push('/')}
          className="text-red-500 text-sm underline cursor-pointer"
        >
          Voltar ao início
        </button>
      </div>
    )
  }

  return (
    <div className="flex flex-1 flex-col items-center px-6 py-10 min-h-dvh">
      <div className="w-full max-w-sm flex flex-col items-center gap-8">
        {/* PIN da sala */}
        <div className="text-center">
          <p className="text-neutral-600 text-xs uppercase tracking-widest mb-1">
            Sala
          </p>
          <p className="text-3xl font-bold tracking-[0.3em] text-red-500">
            {roomPin}
          </p>
        </div>

        {/* Lista de jogadores */}
        <PlayerList
          players={players}
          currentPlayerId={player.id}
          onTransferHost={player.isHost ? handleTransferHost : undefined}
        />

        {transferError && (
          <p className="text-red-500 text-xs text-center">{transferError}</p>
        )}

        {/* Botão de iniciar (só host vê) */}
        {player.isHost && <HostControls roomId={roomId} mode="start" />}

        {/* Aguardando */}
        {!player.isHost && (
          <p className="text-neutral-600 text-xs text-center mt-4">
            Aguardando o Host iniciar a partida...
          </p>
        )}
      </div>
    </div>
  )
}
