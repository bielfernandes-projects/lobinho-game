'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'

interface MasonPanelProps {
  roomId: string
  playerId: string
  onDone?: () => void
}

export function MasonPanel({ roomId, playerId, onDone }: MasonPanelProps) {
  const [partners, setPartners] = useState<{ id: string; name: string }[]>([])
  const [hasActed, setHasActed] = useState(false)
  const [error, setError] = useState('')
  const supabase = createClient()

  useEffect(() => {
    async function load() {
      const { data, error: rpcErr } = await supabase.rpc('get_masons', {
        p_room_id: roomId,
      })
      if (rpcErr) {
        console.error('[MasonPanel] RPC error:', rpcErr)
        setError('Erro ao carregar companheiros.')
        return
      }
      setPartners(((data as { id: string; name: string }[]) ?? []).filter((p) => p.id !== playerId))
    }
    load()
  }, [roomId, playerId, supabase])

  async function handleConfirm() {
    setHasActed(true)
    onDone?.()
  }

  if (hasActed) {
    return (
      <div className="w-full max-w-sm text-center space-y-2">
        <p className="text-neutral-500 text-sm font-semibold">✅ Reconhecimento concluído</p>
        <p className="text-neutral-700 text-xs">Aguarde a noite passar...</p>
      </div>
    )
  }

  return (
    <div className="w-full max-w-sm text-center space-y-4">
      <p className="text-emerald-500 text-sm uppercase tracking-widest font-bold">
        🧱 Maçons
      </p>

      {partners.length > 0 ? (
        <div>
          <p className="text-neutral-600 text-[10px] uppercase tracking-wider mb-2">
            Seus aliados secretos
          </p>
          <div className="flex flex-wrap justify-center gap-2">
            {partners.map((p) => (
              <span
                key={p.id}
                className="px-3 py-1 rounded-full bg-emerald-950/40 border border-emerald-900/30 text-emerald-400 text-xs"
              >
                {p.name}
              </span>
            ))}
          </div>
        </div>
      ) : (
        <p className="text-neutral-500 text-xs">
          Você é o único Maçom nesta sala.
        </p>
      )}

      <p className="text-neutral-500 text-xs">
        Vocês são aliados secretos. Confiem um no outro — mas cuidado para não revelar sua identidade.
      </p>

      <button
        onClick={handleConfirm}
        className="w-full py-3 px-4 rounded-xl text-sm font-medium bg-neutral-900 border border-neutral-800 text-neutral-300 hover:border-emerald-800 hover:text-emerald-400 transition-all duration-200 cursor-pointer"
      >
        Fechar Olhos
      </button>

      {error && (
        <p className="text-red-500 text-xs text-center">{error}</p>
      )}
    </div>
  )
}
