'use client'

import { useInstallPrompt } from '@/hooks/use-install-prompt'

export function InstallButton() {
  const { isInstallable, promptInstall } = useInstallPrompt()

  if (!isInstallable) return null

  return (
    <button
      onClick={promptInstall}
      className="
        px-5 py-2.5 rounded-xl text-xs font-medium tracking-wider
        border border-neutral-800 text-neutral-500
        hover:border-red-800/50 hover:text-red-400
        active:bg-red-950/10
        transition-all duration-200 cursor-pointer
      "
    >
      📲 Instalar App
    </button>
  )
}
