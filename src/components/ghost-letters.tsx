'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { ROLE_LABEL } from '@/lib/cards'

interface GhostState {
  active: boolean
  am_ghost?: boolean
  can_write?: boolean
  letters?: { turn: number; letter: string }[]
  view?: { name: string; role: string; is_alive: boolean }[] | null
}

// Everyone sees the Ghost's letters; the Ghost also gets the writing box
// (and the full list of roles).
export function GhostLetters({ roomId }: { roomId: string }) {
  const [state, setState] = useState<GhostState>({ active: false })
  const [letter, setLetter] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const supabase = createClient()

  async function load() {
    try {
      const { data } = await supabase.rpc('get_ghost_state', { p_room_id: roomId })
      if (data) setState(data as GhostState)
    } catch {}
  }

  useEffect(() => {
    load()
    const iv = setInterval(load, 5000)
    return () => clearInterval(iv)
  }, [roomId])

  async function send() {
    setBusy(true)
    setError('')
    try {
      const { error: err } = await supabase.rpc('ghost_write_letter', { p_room_id: roomId, p_letter: letter })
      if (err) setError(err.message)
      else {
        setLetter('')
        await load()
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Erro inesperado')
    }
    setBusy(false)
  }

  if (!state.active) return null
  const letters = state.letters ?? []

  return (
    <>
      {letters.length > 0 && (
        <div className="fixed top-2 left-1/2 -translate-x-1/2 z-40 px-4 py-1.5 rounded-full bg-neutral-900/90 border border-neutral-700 text-neutral-300 text-sm tracking-[0.3em] select-none">
          👻 {letters.map((l) => l.letter).join(' ')}
        </div>
      )}

      {state.am_ghost && (
        <div className="fixed bottom-0 inset-x-0 z-40 max-h-[55dvh] overflow-y-auto bg-neutral-950/95 border-t border-neutral-800 px-5 py-4 space-y-3">
          <p className="text-neutral-400 text-xs uppercase tracking-widest text-center">👻 Você é o Fantasma</p>

          {state.view && (
            <div className="space-y-1">
              {state.view.map((p, i) => (
                <p key={i} className={`text-xs flex justify-between ${p.is_alive ? 'text-neutral-300' : 'text-neutral-600 line-through'}`}>
                  <span>{p.name}</span>
                  <span>{ROLE_LABEL[p.role] ?? p.role}</span>
                </p>
              ))}
            </div>
          )}

          {state.can_write ? (
            <div className="space-y-2">
              <p className="text-neutral-500 text-[10px] text-center">
                Uma letra por dia. Sem nomes ou iniciais de jogadores.
              </p>
              <div className="flex gap-2 justify-center">
                <input
                  value={letter}
                  onChange={(e) => setLetter(e.target.value.slice(-1))}
                  maxLength={1}
                  className="w-14 text-center text-2xl uppercase bg-neutral-900 border border-neutral-700 rounded-lg py-2 text-neutral-200"
                />
                <button
                  onClick={send}
                  disabled={busy || !/^[A-Za-z]$/.test(letter)}
                  className="px-5 rounded-lg text-sm font-bold bg-neutral-800 border border-neutral-600 text-neutral-200 disabled:opacity-40 cursor-pointer"
                >
                  Enviar
                </button>
              </div>
              {error && <p className="text-red-500 text-xs text-center">{error}</p>}
            </div>
          ) : (
            <p className="text-neutral-600 text-[10px] text-center">
              Você escreve uma letra por dia, durante o dia.
            </p>
          )}
        </div>
      )}
    </>
  )
}
