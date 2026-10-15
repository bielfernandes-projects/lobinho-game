'use client'

import { useEffect, useReducer, useState } from 'react'
import { initialState, reducer, sanitizeState } from '@/lib/caderneta/state'
import { SCENARIO_SESSION_KEY } from '@/hooks/use-scenario-counts'

const STORAGE_KEY = 'lobinho:caderneta:v1'

/** Forget the Caderneta (players, scenario, game). Used by "← Início" and by the idle reset. */
export function clearCadernetaStorage() {
  try {
    sessionStorage.removeItem(STORAGE_KEY)
    sessionStorage.removeItem(SCENARIO_SESSION_KEY)
  } catch {}
}

// The game lives in sessionStorage: it survives a reload but is gone once the tab/app is closed.
export function useCaderneta() {
  const [state, dispatch] = useReducer(reducer, undefined, initialState)
  const [hydrated, setHydrated] = useState(false)

  // Read after mount so server and client render the same first frame.
  /* eslint-disable react-hooks/set-state-in-effect -- one-shot storage hydration, see comment above */
  useEffect(() => {
    try {
      // Earlier versions kept the game in localStorage forever; drop that leftover.
      localStorage.removeItem(STORAGE_KEY)
      const raw = sessionStorage.getItem(STORAGE_KEY)
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
      if (blank) sessionStorage.removeItem(STORAGE_KEY)
      else sessionStorage.setItem(STORAGE_KEY, JSON.stringify(state))
    } catch {}
  }, [state, hydrated])

  return { state, dispatch, hydrated }
}
