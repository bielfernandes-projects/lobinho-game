'use client'

import { useCallback, useEffect, useState } from 'react'
import {
  SAVED_KEY,
  parseSaved,
  removeScenario,
  saveScenario,
  type SavedScenario,
} from '@/lib/caderneta/presets'
import type { ScenarioCounts } from '@/lib/scenario'

// Scenarios the master saved: kept only in this browser (localStorage).
export function useSavedScenarios() {
  const [list, setList] = useState<SavedScenario[]>([])

  // Read after mount so server and client render the same first frame.
  /* eslint-disable react-hooks/set-state-in-effect -- one-shot storage hydration */
  useEffect(() => {
    try {
      setList(parseSaved(localStorage.getItem(SAVED_KEY)))
    } catch {}
  }, [])
  /* eslint-enable react-hooks/set-state-in-effect */

  const persist = useCallback((next: SavedScenario[]) => {
    setList(next)
    try {
      localStorage.setItem(SAVED_KEY, JSON.stringify(next))
    } catch {}
  }, [])

  const save = useCallback(
    (name: string, counts: ScenarioCounts): string | null => {
      const result = saveScenario(list, name, counts)
      if (!result.error) persist(result.list)
      return result.error
    },
    [list, persist],
  )

  const remove = useCallback((name: string) => persist(removeScenario(list, name)), [list, persist])

  return { list, save, remove }
}
