'use client'

import { useState, type FormEvent } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

type Mode = 'criar' | 'entrar'

function gerarPin(): string {
  return String(Math.floor(1000 + Math.random() * 9000))
}

export default function EntryScreen() {
  const router = useRouter()
  const [mode, setMode] = useState<Mode>('criar')
  const [name, setName] = useState('')
  const [pin, setPin] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  async function ensureAuth() {
    const supabase = createClient()
    const { data: { user } } = await supabase.auth.getUser()
    if (user) return user

    const { data } = await supabase.auth.signInAnonymously()
    if (!data.user) throw new Error('Falha na autenticação anônima')
    return data.user
  }

  async function handleCriarSala(e: FormEvent) {
    e.preventDefault()
    const trimmed = name.trim()
    if (!trimmed) { setError('Digite seu nome'); return }

    setBusy(true)
    setError('')
    const supabase = createClient()

    for (let tentativa = 0; tentativa < 5; tentativa++) {
      try {
        const user = await ensureAuth()
        const pinCode = gerarPin()

        const { data: room, error: roomErr } = await supabase
          .from('rooms')
          .insert({
            pin_code: pinCode,
            host_id: user.id,
            max_players: 8,
          })
          .select('id, pin_code')
          .single()

        if (roomErr) {
          if (roomErr.message.includes('duplicate key')) continue
          setError(roomErr.message)
          setBusy(false)
          return
        }

        const { error: playerErr } = await supabase.from('players').insert({
          room_id: room.id,
          name: trimmed,
          user_id: user.id,
          is_host: true,
        })

        if (playerErr) {
          setError(playerErr.message)
          setBusy(false)
          return
        }

        router.push(`/lobby/${room.id}`)
        return
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Erro inesperado')
        setBusy(false)
        return
      }
    }

    setError('Erro ao gerar PIN único. Tente novamente.')
    setBusy(false)
  }

  async function handleEntrar(e: FormEvent) {
    e.preventDefault()
    const trimmed = name.trim()
    if (!trimmed) { setError('Digite seu nome'); return }
    if (!/^\d{4}$/.test(pin)) { setError('PIN deve ter 4 dígitos'); return }

    setBusy(true)
    setError('')
    const supabase = createClient()

    try {
      const user = await ensureAuth()

      const { data: room, error: roomErr } = await supabase
        .from('rooms')
        .select('id, max_players')
        .eq('pin_code', pin)
        .single()

      if (roomErr || !room) {
        setError('Sala não encontrada')
        setBusy(false)
        return
      }

      const { data: existing } = await supabase
        .from('players')
        .select('id')
        .eq('room_id', room.id)
        .eq('user_id', user.id)
        .maybeSingle()

      if (existing) {
        router.push(`/lobby/${room.id}`)
        return
      }

      const { count } = await supabase
        .from('players')
        .select('*', { count: 'exact', head: true })
        .eq('room_id', room.id)

      if ((count ?? 0) >= room.max_players) {
        setError('Sala cheia')
        setBusy(false)
        return
      }

      const { error: playerErr } = await supabase.from('players').insert({
        room_id: room.id,
        name: trimmed,
        user_id: user.id,
        is_host: false,
      })

      if (playerErr) {
        setError(playerErr.message)
        setBusy(false)
        return
      }

      router.push(`/lobby/${room.id}`)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erro inesperado')
      setBusy(false)
    }
  }

  return (
    <div className="flex flex-1 flex-col items-center justify-center px-6 min-h-dvh">
      <div className="w-full max-w-xs flex flex-col items-center gap-10">
        {/* Título */}
        <div className="text-center">
          <h1 className="text-5xl font-black tracking-widest text-red-600 drop-shadow-[0_0_20px_rgba(220,38,38,0.3)]">
            LOBINHO
          </h1>
          <p className="text-neutral-600 text-xs tracking-widest uppercase mt-2">
            A Werewolf Game Based
          </p>
        </div>

        {/* Formulário */}
        <form className="w-full flex flex-col gap-4">
          <input
            type="text"
            placeholder="Seu nome"
            maxLength={30}
            value={name}
            onChange={(e) => { setName(e.target.value); setError('') }}
            className="
              w-full px-4 py-3 rounded-xl text-sm
              bg-neutral-900 border border-neutral-800
              text-neutral-200 placeholder-neutral-600
              focus:outline-none focus:ring-2 focus:ring-red-700 focus:border-red-800
              transition-all
            "
          />

          {/* PIN — só aparece no modo "entrar" */}
          {mode === 'entrar' && (
            <input
              type="text"
              inputMode="numeric"
              pattern="[0-9]{4}"
              placeholder="PIN da sala (4 dígitos)"
              maxLength={4}
              value={pin}
              onChange={(e) => { setPin(e.target.value.replace(/\D/g, '')); setError('') }}
              className="
                w-full px-4 py-3 rounded-xl text-sm tracking-widest text-center
                bg-neutral-900 border border-neutral-800
                text-neutral-200 placeholder-neutral-600
                focus:outline-none focus:ring-2 focus:ring-red-700 focus:border-red-800
                transition-all
              "
            />
          )}

          {error && (
            <p className="text-red-500 text-xs text-center">{error}</p>
          )}

          {/* Alternador criar / entrar */}
          <div className="flex rounded-xl border border-neutral-800 overflow-hidden">
            <button
              type="button"
              onClick={() => { setMode('criar'); setError('') }}
              className={`flex-1 py-2.5 text-xs font-medium tracking-wider transition-colors cursor-pointer ${
                mode === 'criar'
                  ? 'bg-red-900/40 text-red-400 border-r border-neutral-800'
                  : 'bg-neutral-900 text-neutral-500 hover:text-neutral-400'
              }`}
            >
              Criar Sala
            </button>
            <button
              type="button"
              onClick={() => { setMode('entrar'); setError('') }}
              className={`flex-1 py-2.5 text-xs font-medium tracking-wider transition-colors cursor-pointer ${
                mode === 'entrar'
                  ? 'bg-red-900/40 text-red-400'
                  : 'bg-neutral-900 text-neutral-500 hover:text-neutral-400'
              }`}
            >
              Entrar
            </button>
          </div>

          {/* Botão de ação */}
          {mode === 'criar' ? (
            <button
              type="button"
              onClick={handleCriarSala}
              disabled={busy}
              className="
                w-full py-3.5 rounded-2xl font-bold text-sm tracking-wider
                bg-red-700 text-white
                hover:bg-red-600 active:bg-red-800
                disabled:opacity-40 disabled:cursor-not-allowed
                shadow-lg shadow-red-900/30
                transition-all duration-200
                cursor-pointer
              "
            >
              {busy ? 'Criando...' : 'Criar Sala'}
            </button>
          ) : (
            <button
              type="button"
              onClick={handleEntrar}
              disabled={busy}
              className="
                w-full py-3.5 rounded-2xl font-bold text-sm tracking-wider
                border border-red-700 text-red-400
                hover:bg-red-950/30 active:bg-red-950/50
                disabled:opacity-40 disabled:cursor-not-allowed
                transition-all duration-200
                cursor-pointer
              "
            >
              {busy ? 'Entrando...' : 'Entrar'}
            </button>
          )}
        </form>
      </div>
    </div>
  )
}
