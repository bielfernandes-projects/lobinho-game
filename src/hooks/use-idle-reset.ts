'use client'

import { useEffect, useRef } from 'react'

/** "Muito tempo sem mexer": 30 minutes without touching the screen. */
export const IDLE_RESET_MS = 30 * 60 * 1000

const ACTIVITY_EVENTS = ['pointerdown', 'keydown', 'touchstart', 'scroll', 'input'] as const

/**
 * Calls `onIdle` once after `limitMs` without user activity while `enabled`.
 * Timers are throttled when a phone sleeps, so it also checks the clock when the tab comes back.
 */
export function useIdleReset(enabled: boolean, onIdle: () => void, limitMs: number = IDLE_RESET_MS) {
  const onIdleRef = useRef(onIdle)
  useEffect(() => {
    onIdleRef.current = onIdle
  })

  useEffect(() => {
    if (!enabled) return
    let last = Date.now()
    let fired = false

    const touch = () => {
      last = Date.now()
    }
    const check = () => {
      if (!fired && Date.now() - last >= limitMs) {
        fired = true
        onIdleRef.current()
      }
    }

    for (const ev of ACTIVITY_EVENTS) window.addEventListener(ev, touch, { passive: true, capture: true })
    const interval = setInterval(check, 30_000)
    document.addEventListener('visibilitychange', check)
    return () => {
      for (const ev of ACTIVITY_EVENTS) window.removeEventListener(ev, touch, { capture: true })
      clearInterval(interval)
      document.removeEventListener('visibilitychange', check)
    }
  }, [enabled, limitMs])
}
