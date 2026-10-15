'use client'

import { useState, type FormEvent } from 'react'
import { useRouter } from 'next/navigation'
import Image from 'next/image'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'
import { InstallButton } from '@/components/install-button'
import { SupportFooter } from '@/components/support-footer'

function gerarPin(): string {
  return String(Math.floor(1000 + Math.random() * 9000))
}

export default function EntryScreen() {
  const router = useRouter()
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

  async function handleCriarSala() {
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
            max_players: 78,
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

  async function handleEntrar() {
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

  function handleKeyDown(e: React.KeyboardEvent) {
    if (e.key === 'Enter') {
      if (pin.trim() && /^\d{4}$/.test(pin)) {
        handleEntrar()
      } else {
        handleCriarSala()
      }
    }
  }

  return (
    <div className="flex flex-1 flex-col items-center justify-center px-6 min-h-dvh">
      <div className="w-full max-w-xs flex flex-col items-center gap-10">
        <div className="text-center">
          <div className="relative w-24 h-24 mx-auto mb-5">
            <Image
              src="/logo.png"
              alt="Lobinho"
              fill
              sizes="96px"
              priority
              className="rounded-3xl shadow-lg shadow-red-900/30"
            />
          </div>
          <h1 className="font-display text-6xl tracking-[0.18em] text-red-600 drop-shadow-[0_0_20px_rgba(220,38,38,0.3)]">
            LOBINHO
          </h1>
          <p className="text-neutral-600 text-xs tracking-widest uppercase mt-2">
            A Werewolf Game Based
          </p>
        </div>

        <div className="w-full flex flex-col gap-4">
          <Link
            href="/caderneta"
            className="
              w-full py-4 rounded-2xl font-bold text-base tracking-wider text-center
              bg-primary hover:bg-primary-hover active:bg-primary-active text-white
              shadow-lg shadow-red-900/30
              transition-all duration-200
            "
          >
            Caderneta do Mestre
          </Link>
          <p className="text-neutral-500 text-xs text-center leading-relaxed">
            Um celular só, o mestre conduz. Cada jogador vê a própria carta sem precisar de conta.
          </p>

          <div className="flex items-center gap-2 mt-4">
            <span className="flex-1 h-px bg-neutral-800" />
            <h2 className="text-neutral-500 text-[10px] uppercase tracking-widest">Jogar online</h2>
            <span className="flex-1 h-px bg-neutral-800" />
          </div>
          <p className="text-neutral-600 text-[11px] text-center">
            Cada um no seu celular, com sala e código.
          </p>

          <input
            type="text"
            placeholder="Nome do Jogador"
            maxLength={30}
            value={name}
            onChange={(e) => { setName(e.target.value); setError('') }}
            onKeyDown={handleKeyDown}
            className="
              w-full px-4 py-3 rounded-xl text-sm
              bg-neutral-900 border border-neutral-800
              text-neutral-200 placeholder-neutral-600
              focus:outline-none focus:ring-2 focus:ring-red-700 focus:border-red-800
              transition-all
            "
          />

          <input
            type="text"
            inputMode="numeric"
            pattern="[0-9]{4}"
            placeholder="Código da Sala (4 dígitos)"
            maxLength={4}
            value={pin}
            onChange={(e) => { setPin(e.target.value.replace(/\D/g, '')); setError('') }}
            onKeyDown={handleKeyDown}
            className="
              w-full px-4 py-3 rounded-xl text-sm tracking-widest text-center
              bg-neutral-900 border border-neutral-800
              text-neutral-200 placeholder-neutral-600
              focus:outline-none focus:ring-2 focus:ring-red-700 focus:border-red-800
              transition-all
            "
          />

          {error && (
            <p className="text-red-500 text-xs text-center">{error}</p>
          )}

          <div className="flex flex-row gap-4">
            <button
              type="button"
              onClick={handleCriarSala}
              disabled={busy}
              className="
                flex-1 py-3.5 rounded-2xl font-bold text-sm tracking-wider
                bg-primary hover:bg-primary-hover active:bg-primary-active text-white
                disabled:opacity-40 disabled:cursor-not-allowed
                shadow-lg shadow-red-900/30
                transition-all duration-200 cursor-pointer
              "
            >
              {busy ? 'Criando...' : 'Criar Sala'}
            </button>
            <button
              type="button"
              onClick={handleEntrar}
              disabled={busy}
              className="
                flex-1 py-3.5 rounded-2xl font-bold text-sm tracking-wider
                border border-primary text-primary-light
                hover:bg-red-950/30 active:bg-red-950/50
                disabled:opacity-40 disabled:cursor-not-allowed
                transition-all duration-200 cursor-pointer
              "
            >
              {busy ? 'Entrando...' : 'Entrar'}
            </button>
          </div>

          <div className="flex justify-center mt-2">
            <InstallButton />
          </div>

          <SupportFooter />
        </div>
      </div>
    </div>
  )
}
