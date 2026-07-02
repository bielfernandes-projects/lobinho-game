'use client'

import { useState, useEffect, useRef } from 'react'
import { createClient } from '@/lib/supabase/client'
import { CARD_CATALOG } from '@/lib/cards'

interface TribunalPanelProps {
  roomId: string
  dayStep: string
  accusedId: string | null
  turnIndex: number
}

export function TribunalPanel({ roomId, dayStep, accusedId, turnIndex }: TribunalPanelProps) {
  const [accuseModal, setAccuseModal] = useState(false)
  const [players, setPlayers] = useState<{ id: string; name: string; role: string }[]>([])
  const [accusedName, setAccusedName] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [voteCount, setVoteCount] = useState(0)
  const [tooltipRole, setTooltipRole] = useState<string | null>(null)
  const supabase = createClient()
  const accusedFetchCountRef = useRef(0)

  useEffect(() => {
    if (!accusedId) { setAccusedName(null); return }
    const id = ++accusedFetchCountRef.current
    supabase
      .from('players')
      .select('name')
      .eq('id', accusedId)
      .single()
      .then(({ data }) => {
        if (id === accusedFetchCountRef.current && data) {
          setAccusedName((data as any).name)
        }
      })
  }, [accusedId])

  async function openAccuseModal() {
    const { data } = await supabase
      .from('players')
      .select('id, name, role')
      .eq('room_id', roomId)
      .neq('role', 'moderator')
      .eq('is_alive', true)
    if (data) {
      setPlayers(data as { id: string; name: string; role: string }[])
    }
    setAccuseModal(true)
  }

  async function handleAccuse(targetId: string) {
    setBusy(true)
    await supabase
      .from('game_state')
      .update({ day_step: 'trial', current_accused_id: targetId })
      .eq('room_id', roomId)
    setBusy(false)
    setAccuseModal(false)
  }

  async function handleOpenVoting() {
    await supabase.from('game_state').update({ day_step: 'voting' }).eq('room_id', roomId)
  }

  async function handleReveal() {
    const { count } = await supabase
      .from('votes')
      .select('*', { count: 'exact', head: true })
      .eq('room_id', roomId)
      .eq('turn_index', turnIndex)
    if (count !== null) setVoteCount(count)

    await supabase.from('game_state').update({ day_step: 'reveal' }).eq('room_id', roomId)
  }

  async function handleExecute() {
    setBusy(true)
    await supabase.rpc('host_execute_accused', { p_room_id: roomId })
    setBusy(false)
  }

  async function handleAbsolve() {
    setBusy(true)
    await supabase.rpc('host_absolve_accused', { p_room_id: roomId })
    setBusy(false)
  }

  async function handleSkipToNight() {
    setBusy(true)
    await supabase.rpc('host_day_to_night', { p_room_id: roomId })
    setBusy(false)
  }

  // Poll vote count during voting phase
  if (dayStep === 'voting') {
    // Simple poll on mount (host can refresh manually via reveal)
  }

  return (
    <div className="w-full max-w-sm mx-auto space-y-3">
      {/* DISCUSSION */}
      {dayStep === 'discussion' && (
        <>
          <button
            onClick={openAccuseModal}
            disabled={busy}
            className="w-full py-4 rounded-2xl font-bold text-lg tracking-wider bg-neutral-800 text-red-400 border border-red-900/50 hover:bg-red-900/30 active:bg-red-950/40 disabled:opacity-30 transition-all duration-200 cursor-pointer"
          >
            🎤 Nova Acusação Formal
          </button>
          <button
            onClick={handleSkipToNight}
            disabled={busy}
            className="w-full py-3 rounded-2xl font-bold text-sm tracking-wider bg-neutral-900 text-neutral-400 border border-neutral-800 hover:text-neutral-300 hover:border-neutral-700 disabled:opacity-30 transition-all duration-200 cursor-pointer"
          >
            🌙 Avançar para Noite
          </button>
        </>
      )}

      {/* Modal de acusação */}
      {accuseModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 px-6">
          <div className="w-full max-w-xs rounded-2xl border border-neutral-800 bg-neutral-950 p-6 text-center space-y-3">
            <p className="text-neutral-300 text-sm font-medium">Selecione o Acusado</p>
            <div className="space-y-2 max-h-60 overflow-y-auto">
              {players.map((p) => (
                <div key={p.id} className="flex items-center gap-2">
                  <button
                    onClick={() => handleAccuse(p.id)}
                    disabled={busy}
                    className="flex-1 py-2.5 px-4 rounded-xl text-sm font-medium bg-neutral-900 border border-neutral-800 text-neutral-300 hover:border-red-700 hover:text-red-400 disabled:opacity-40 transition-all duration-200 cursor-pointer text-left"
                  >
                    {p.name}
                  </button>
                  <span className="relative shrink-0">
                    <button
                      type="button"
                      onClick={() => setTooltipRole(tooltipRole === p.role ? null : p.role)}
                      className="text-neutral-600 hover:text-neutral-400 text-xs transition-colors cursor-pointer"
                    >
                      ⓘ
                    </button>
                    {tooltipRole === p.role && (() => {
                      const card = CARD_CATALOG.find((c) => c.id === p.role)
                      if (!card) return null
                      return (
                        <div className="absolute bottom-full right-0 mb-2 w-56 rounded-xl border border-neutral-700 bg-neutral-900 p-3 shadow-xl z-10">
                          <p className="text-neutral-300 text-xs leading-relaxed">
                            {card.description}
                          </p>
                        </div>
                      )
                    })()}
                  </span>
                </div>
              ))}
            </div>
            <button
              onClick={() => setAccuseModal(false)}
              className="text-neutral-600 text-xs underline cursor-pointer"
            >
              Cancelar
            </button>
          </div>
        </div>
      )}

      {/* TRIAL */}
      {dayStep === 'trial' && (
        <div className="space-y-3">
          <div className="rounded-xl border border-red-800/60 bg-red-950/20 px-4 py-3 text-center">
            <p className="text-neutral-500 text-[10px] uppercase tracking-widest">Acusado</p>
            <p className="text-red-400 text-lg font-bold mt-1">
              {accusedName ?? '...'}
            </p>
          </div>
          <button
            onClick={handleOpenVoting}
            className="w-full py-4 rounded-2xl font-bold text-lg tracking-wider bg-emerald-900/30 border border-emerald-700/50 text-emerald-400 hover:bg-emerald-800/40 transition-all duration-200 cursor-pointer"
          >
            📬 Abrir Urnas
          </button>
        </div>
      )}

      {/* VOTING */}
      {dayStep === 'voting' && (
        <div className="space-y-3">
          <p className="text-neutral-500 text-xs text-center">
            🗳️ Votação em andamento...
          </p>
          <PollVoteCount roomId={roomId} turnIndex={turnIndex} />
          <button
            onClick={handleReveal}
            disabled={busy}
            className="w-full py-4 rounded-2xl font-bold text-lg tracking-wider bg-neutral-800 text-purple-400 border border-purple-900/50 hover:bg-purple-900/30 disabled:opacity-30 transition-all duration-200 cursor-pointer"
          >
            📊 Revelar Votos
          </button>
        </div>
      )}

      {/* REVEAL */}
      {dayStep === 'reveal' && (
        <div className="space-y-3">
          <button
            onClick={handleExecute}
            disabled={busy}
            className="w-full py-4 rounded-2xl font-bold text-lg tracking-wider bg-red-900/30 border border-red-700/50 text-red-400 hover:bg-red-800/40 disabled:opacity-30 transition-all duration-200 cursor-pointer"
          >
            {busy ? 'Executando...' : '☠️ Executar Linchamento'}
          </button>
          <button
            onClick={handleAbsolve}
            disabled={busy}
            className="w-full py-3 rounded-2xl font-bold text-sm tracking-wider bg-neutral-900 text-neutral-400 border border-neutral-800 hover:text-yellow-400 hover:border-yellow-900/50 disabled:opacity-30 transition-all duration-200 cursor-pointer"
          >
            ⚖️ Absolver e Voltar ao Debate
          </button>
        </div>
      )}
    </div>
  )
}

function PollVoteCount({ roomId, turnIndex }: { roomId: string; turnIndex: number }) {
  const supabase = createClient()
  const [count, setCount] = useState(0)

  useState(() => {
    async function poll() {
      const { count: c } = await supabase
        .from('votes')
        .select('*', { count: 'exact', head: true })
        .eq('room_id', roomId)
        .eq('turn_index', turnIndex)
      if (c !== null) setCount(c)
    }
    poll()
    const interval = setInterval(poll, 2000)
    return () => clearInterval(interval)
  })

  return <p className="text-neutral-600 text-xs text-center">Votos registrados: {count}</p>
}
