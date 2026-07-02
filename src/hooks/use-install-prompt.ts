'use client'

import { useState, useEffect } from 'react'

interface UseInstallPromptReturn {
  isInstallable: boolean
  promptInstall: () => void
}

export function useInstallPrompt(): UseInstallPromptReturn {
  const [deferredPrompt, setDeferredPrompt] = useState<any>(null)

  useEffect(() => {
    const handler = (e: Event) => {
      e.preventDefault()
      setDeferredPrompt(e)
    }
    window.addEventListener('beforeinstallprompt', handler)
    return () => window.removeEventListener('beforeinstallprompt', handler)
  }, [])

  const promptInstall = () => {
    if (deferredPrompt) {
      deferredPrompt.prompt()
      deferredPrompt.userChoice.then(() => setDeferredPrompt(null))
    }
  }

  return {
    isInstallable: deferredPrompt !== null,
    promptInstall,
  }
}
