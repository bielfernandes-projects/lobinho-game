'use client'

import { useInstallPrompt } from '@/hooks/use-install-prompt'
import { useState, useEffect } from 'react'

function isIos() {
  if (typeof window === 'undefined') return false
  const ua = window.navigator.userAgent
  return /iPad|iPhone|iPod/.test(ua) || (ua.includes('Mac') && 'ontouchend' in document)
}

function isStandalone() {
  if (typeof window === 'undefined') return false
  return (
    window.matchMedia('(display-mode: standalone)').matches ||
    (window.navigator as any).standalone === true
  )
}

export function InstallButton() {
  const { isInstallable, promptInstall } = useInstallPrompt()
  const [iosHelpOpen, setIosHelpOpen] = useState(false)
  const [isIosDevice, setIsIosDevice] = useState(false)
  const [isInstalled, setIsInstalled] = useState(false)

  useEffect(() => {
    setIsIosDevice(isIos())
    setIsInstalled(isStandalone())
  }, [])

  // Se já está instalado, não mostra nada
  if (isInstalled) return null

  // Se for iOS, mostra botão de ajuda (Safari não dispara beforeinstallprompt)
  if (isIosDevice) {
    return (
      <>
        <button
          onClick={() => setIosHelpOpen(true)}
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
        {iosHelpOpen && (
          <div
            className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 px-6"
            onClick={() => setIosHelpOpen(false)}
          >
            <div
              onClick={(e) => e.stopPropagation()}
              className="w-full max-w-xs rounded-2xl border border-neutral-800 bg-neutral-950 p-6 text-center space-y-4"
            >
              <p className="text-3xl">📲</p>
              <p className="text-neutral-200 text-sm font-bold tracking-wider">
                Instalar no iPhone/iPad
              </p>
              <ol className="text-neutral-400 text-xs text-left space-y-2 list-decimal list-inside">
                <li>Toque no botão de <b>compartilhar</b> (⬆️ quadrado com seta).</li>
                <li>Role para baixo e toque em <b>"Adicionar à Tela de Início"</b>.</li>
                <li>Confirme tocando em <b>"Adicionar"</b>.</li>
              </ol>
              <button
                onClick={() => setIosHelpOpen(false)}
                className="
                  w-full py-2.5 rounded-xl text-sm font-medium
                  bg-neutral-900 border border-neutral-800 text-neutral-300
                  hover:bg-neutral-800 cursor-pointer transition-all duration-200
                "
              >
                Fechar
              </button>
            </div>
          </div>
        )}
      </>
    )
  }

  // Em outros navegadores, mostra o botão nativo (só aparece se beforeinstallprompt disparou)
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
