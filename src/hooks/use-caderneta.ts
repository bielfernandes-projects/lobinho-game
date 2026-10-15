'use client'

import { useEffect, useReducer, useState } from 'react'
import { initialState, reducer, sanitizeState } from '@/lib/caderneta/state'

const STORAGE_KEY = 'lobinho:caderneta:v1'

export function useCaderneta() {
  const [state, dispatch] = useReducer(reducer, undefined, initialState)
  const [hydrated, setHydrated] = useState(false)

  // Read after mount so server and client render the same first frame.
  /* eslint-disable react-hooks/set-state-in-effect -- one-shot localStorage hydration, see comment above */
  useEffect(() => {
    try {
      const raw = localStorage.getItem(STORAGE_KEY)
      if (raw) {
        const saved = sanitizeState(JSON.parse(raw))
        if (saved) dispatch({ type: 'load', state: saved })
      }
    } catch {}
    setHydrated(true)
  }, [])
  /* eslint-enable react-hooks/set-state-in-effect */

  useEffect(() => {
    if (!hydrated) return
    try {
      const blank = state.phase === 'setup' && state.names.length === 0
      if (blank) localStorage.removeItem(STORAGE_KEY)
      else localStorage.setItem(STORAGE_KEY, JSON.stringify(state))
    } catch {}
  }, [state, hydrated])

  return { state, dispatch, hydrated }
}
