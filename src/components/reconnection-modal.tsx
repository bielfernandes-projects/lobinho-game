'use client'

import { createContext, useContext, useEffect, useState, useRef, type ReactNode } from 'react'
import { createClient } from '@/lib/supabase/client'

type ConnectionStatus = 'connected' | 'disconnected' | 'connecting'

const ConnectionContext = createContext<ConnectionStatus>('connected')

export function useConnectionStatus() {
  return useContext(ConnectionContext)
}

export function ConnectionProvider({ children }: { children: ReactNode }) {
  const [visible, setVisible] = useState(false)
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const supabase = createClient()

  useEffect(() => {
    const channel = supabase.channel('connection-health')

    channel.subscribe((newStatus) => {
      if (newStatus === 'SUBSCRIBED') {
        if (timerRef.current) {
          clearTimeout(timerRef.current)
          timerRef.current = null
        }
        setVisible(false)
      } else if (newStatus === 'CHANNEL_ERROR' || newStatus === 'CLOSED') {
        if (!timerRef.current) {
          timerRef.current = setTimeout(() => {
            setVisible(true)
          }, 3000)
        }
      }
    })

    return () => {
      supabase.removeChannel(channel)
      if (timerRef.current) clearTimeout(timerRef.current)
    }
  }, [])

  return (
    <ConnectionContext.Provider value={visible ? 'disconnected' : 'connected'}>
      {children}
      {visible && <ReconnectionOverlay />}
    </ConnectionContext.Provider>
  )
}

function ReconnectionOverlay() {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center pointer-events-none">
      <div className="bg-neutral-950/80 backdrop-blur-sm absolute inset-0" />
      <div className="relative bg-neutral-900 border border-red-900/50 rounded-2xl p-8 flex flex-col items-center gap-4 max-w-xs">
        <div className="w-10 h-10 border-[3px] border-red-700 border-t-transparent rounded-full animate-spin" />
        <p className="text-red-400 text-sm uppercase tracking-widest text-center">
          Reconectando...
        </p>
        <p className="text-neutral-600 text-xs text-center leading-relaxed">
          Perda de sinal detectada.
          <br />
          O jogo será retomado automaticamente.
        </p>
      </div>
    </div>
  )
}
