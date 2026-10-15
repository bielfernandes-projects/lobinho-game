'use client'

import { useEffect, useState } from 'react'
import { emptyCounts, type ScenarioCounts } from '@/lib/scenario'

// Same key the online builder has always used, so the last scenario is shared by both modes.
const STORAGE_KEY = 'lobinho_last_scenario'

export function useScenarioCounts() {
  const [counts, setCounts] = useState<ScenarioCounts>(emptyCounts)
  const [hydrated, setHydrated] = useState(false)

  // Read after mount (not in the initializer) so server and client render the same first frame.
  /* eslint-disable react-hooks/set-state-in-effect -- one-shot localStorage hydration, see comment above */
  useEffect(() => {
    try {
      const saved = localStorage.getItem(STORAGE_KEY)
      if (saved) setCounts({ ...emptyCounts(), ...JSON.parse(saved) })
    } catch {}
    setHydrated(true)
  }, [])
  /* eslint-enable react-hooks/set-state-in-effect */

  useEffect(() => {
    if (!hydrated) return
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(counts))
    } catch {}
  }, [counts, hydrated])

  return [counts, setCounts] as const
}
