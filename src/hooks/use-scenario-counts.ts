'use client'

import { useEffect, useState } from 'react'
import { emptyCounts, type ScenarioCounts } from '@/lib/scenario'

// The online builder remembers the last scenario forever (localStorage, key it has always used).
// The Caderneta's scenario only lives while the tab is open (sessionStorage): closing the app,
// "← Início" or idling clears it.
export const SCENARIO_LOCAL_KEY = 'lobinho_last_scenario'
export const SCENARIO_SESSION_KEY = 'lobinho:caderneta:scenario'

export function useScenarioCounts(storage: 'local' | 'session' = 'local') {
  const [counts, setCounts] = useState<ScenarioCounts>(emptyCounts)
  const [hydrated, setHydrated] = useState(false)
  const key = storage === 'session' ? SCENARIO_SESSION_KEY : SCENARIO_LOCAL_KEY

  // Read after mount (not in the initializer) so server and client render the same first frame.
  /* eslint-disable react-hooks/set-state-in-effect -- one-shot storage hydration, see comment above */
  useEffect(() => {
    try {
      const store = storage === 'session' ? sessionStorage : localStorage
      const saved = store.getItem(key)
      if (saved) setCounts({ ...emptyCounts(), ...JSON.parse(saved) })
    } catch {}
    setHydrated(true)
  }, [storage, key])
  /* eslint-enable react-hooks/set-state-in-effect */

  useEffect(() => {
    if (!hydrated) return
    try {
      const store = storage === 'session' ? sessionStorage : localStorage
      store.setItem(key, JSON.stringify(counts))
    } catch {}
  }, [counts, hydrated, storage, key])

  return [counts, setCounts] as const
}
