'use client'

import { useEffect, useState, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import { CARD_CATALOG, ROLE_STYLE, ROLE_LABEL } from '@/lib/cards'

interface RoleRow {
  id: string
  name: string
  role: string
  is_alive: boolean
  has_viewed_card: boolean
}

interface HostRolePanelProps {
  roomId: string
  isHost: boolean
}

export function HostRolePanel({ roomId, isHost }: HostRolePanelProps) {
  const [rows, setRows] = useState<RoleRow[]>([])
  const [collapsed, setCollapsed] = useState(false)
  const [error, setError] = useState('')
  const [tooltipRole, setTooltipRole] = useState<string | null>(null)
  const supabase = createClient()

  const fetchPlayers = useCallback(async () => {
    if (!isHost) return

    setError('')

    const { data, error: rpcError } = await supabase.rpc('fetch_roles_for_host', { p_room_id: roomId })

    if (rpcError) {
      console.error('fetch_roles_for_host error:', rpcError)
      setError(rpcError.message)
      return
    }

    if (data) {
      setRows(data as RoleRow[])
    }
  }, [roomId, isHost])

  useEffect(() => {
    if (!isHost) return

    fetchPlayers()

    const handleChange = () => {
      fetchPlayers().catch((e) => {
        console.error('Realtime refresh error:', e)
        setError(e instanceof Error ? e.message : 'Erro ao atualizar lista')
      })
    }

    const channel = supabase
      .channel(`host-roles:${roomId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'players', filter: `room_id=eq.${roomId}` }, handleChange)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'game_state', filter: `room_id=eq.${roomId}` }, handleChange)
      .subscribe()

    return () => { supabase.removeChannel(channel) }
  }, [roomId, isHost, fetchPlayers])

  const [killTarget, setKillTarget] = useState<{ id: string; name: string } | null>(null)
  const [killBusy, setKillBusy] = useState(false)

  async function handleConfirmKill() {
    if (!killTarget) return
    setKillBusy(true)
    const { error: e } = await supabase.rpc('host_kill_player', {
      p_target_id: killTarget.id,
      p_room_id: roomId,
    })
    if (e) console.error('host_kill_player error:', e)
    setKillBusy(false)
    setKillTarget(null)
  }

  if (!isHost) return null

  return (
    <div className="w-full max-w-sm mx-auto">
      <button
        onClick={() => setCollapsed((c) => !c)}
        className="w-full flex items-center justify-between px-4 py-2 rounded-xl bg-neutral-900/80 border border-neutral-800 text-xs uppercase tracking-widest text-neutral-500 hover:text-neutral-400 transition-colors cursor-pointer mb-2"
      >
        <span>🎙️ Painel do Mestre</span>
        <span className="text-neutral-600">{collapsed ? '▼' : '▲'}</span>
      </button>

      {!collapsed && (
        <div className="rounded-xl border border-neutral-800 bg-neutral-900/60 overflow-hidden">
          {error && (
            <div className="px-4 py-2 bg-red-950/30 border-b border-red-900/30">
              <p className="text-red-500 text-xs">{error}</p>
            </div>
          )}
          <div className="divide-y divide-neutral-800">
            {rows.filter((r) => r.role !== 'moderator').map((r) => (
              <div key={r.id} className="flex items-center gap-3 px-4 py-2.5">
                <span
                  className={`w-2 h-2 rounded-full shrink-0 ${
                    r.is_alive ? 'bg-green-500 shadow-[0_0_6px_rgba(34,197,94,0.5)]' : 'bg-red-800'
                  }`}
                />
                <span className={`flex-1 text-sm font-medium truncate ${r.is_alive ? 'text-neutral-200' : 'text-neutral-600 line-through'}`}>
                  {r.has_viewed_card && <span className="mr-1 opacity-70">👁</span>}
                  {r.name}
                </span>
                <span className={`text-xs tracking-wider shrink-0 px-2 py-0.5 rounded-full border ${ROLE_STYLE[r.role] ?? 'text-neutral-500 border-neutral-700'}`}>
                  {ROLE_LABEL[r.role] ?? r.role}
                </span>
                <span className="relative shrink-0">
                  <button
                    type="button"
                    onClick={() => setTooltipRole(tooltipRole === r.role ? null : r.role)}
                    className="text-neutral-600 hover:text-neutral-400 text-xs transition-colors cursor-pointer"
                  >
                    ⓘ
                  </button>
                  {tooltipRole === r.role && (() => {
                    const card = CARD_CATALOG.find((c) => c.id === r.role)
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
                {r.is_alive && r.role !== 'moderator' && (
                  <button
                    onClick={() => setKillTarget({ id: r.id, name: r.name })}
                    className="text-sm opacity-60 hover:opacity-100 hover:text-red-400 transition-all duration-200 cursor-pointer shrink-0"
                    title="Punição do Mestre"
                  >
                    ☠️
                  </button>
                )}
              </div>
            ))}
            {rows.filter((r) => r.role !== 'moderator').length === 0 && !error && (
              <div className="px-4 py-6 text-center">
                <p className="text-neutral-700 text-xs">Nenhum jogador encontrado</p>
              </div>
            )}
          </div>
        </div>
      )}

      {killTarget && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 px-6">
          <div className="w-full max-w-xs rounded-2xl border border-neutral-800 bg-neutral-950 p-6 text-center space-y-4">
            <p className="text-neutral-300 text-sm font-medium">
              ☠️ Strike Final?
            </p>
            <p className="text-neutral-500 text-xs">
              Tem certeza que deseja punir <span className="text-red-400 font-bold">{killTarget.name}</span>?
            </p>
            <div className="flex gap-3">
              <button
                onClick={() => setKillTarget(null)}
                disabled={killBusy}
                className="flex-1 py-3 rounded-xl text-sm font-medium bg-neutral-900 border border-neutral-800 text-neutral-400 hover:bg-neutral-800 disabled:opacity-40 cursor-pointer transition-all duration-200"
              >
                Cancelar
              </button>
              <button
                onClick={handleConfirmKill}
                disabled={killBusy}
                className="flex-1 py-3 rounded-xl text-sm font-bold bg-red-900/30 border border-red-700/50 text-red-400 hover:bg-red-800/40 disabled:opacity-40 cursor-pointer transition-all duration-200"
              >
                {killBusy ? 'Executando...' : 'Executar'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
