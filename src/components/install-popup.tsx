'use client'

import { useEffect, useState } from 'react'
import { useInstallPrompt } from '@/hooks/use-install-prompt'
import { installMode } from '@/lib/install'

// Offers to install the app every time the site is opened in a browser (iOS and Android).
// Closing it only hides it for this visit: the next time the site is opened it shows again.
// Never shown inside the installed app.
export function InstallPopup() {
  const { isInstallable, promptInstall } = useInstallPrompt()
  const [env, setEnv] = useState<{ standalone: boolean; ua: string; hasTouch: boolean } | null>(null)
  const [closed, setClosed] = useState(false)

  // Read the browser only after mount so the server and the first client render match.
  /* eslint-disable react-hooks/set-state-in-effect -- one-shot environment detection */
  useEffect(() => {
    const standalone =
      window.matchMedia('(display-mode: standalone)').matches ||
      (window.navigator as Navigator & { standalone?: boolean }).standalone === true
    setEnv({ standalone, ua: navigator.userAgent, hasTouch: 'ontouchend' in document })
    const onInstalled = () => setClosed(true)
    window.addEventListener('appinstalled', onInstalled)
    return () => window.removeEventListener('appinstalled', onInstalled)
  }, [])
  /* eslint-enable react-hooks/set-state-in-effect */

  if (!env || closed) return null
  const mode = installMode({ ...env, installable: isInstallable })
  if (!mode) return null

  return (
    <div
      role="dialog"
      aria-label="Instalar o Lobinho"
      className="fixed inset-x-0 bottom-0 z-50 px-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]"
    >
      <div className="mx-auto w-full max-w-sm rounded-2xl border border-neutral-700 bg-neutral-950 p-5 shadow-2xl shadow-black/60 space-y-3">
        <div className="flex items-center gap-3">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/android-chrome-192x192.png" alt="" width={44} height={44} className="rounded-xl" />
          <div>
            <p className="text-neutral-100 text-sm font-bold">Instale o Lobinho</p>
            <p className="text-neutral-400 text-xs leading-relaxed">
              Abre em tela cheia, direto na Caderneta do Mestre, como um app de verdade.
            </p>
          </div>
        </div>

        {mode === 'ios' ? (
          <>
            <ol className="text-neutral-300 text-xs space-y-1.5 list-decimal list-inside">
              <li>Toque em <b>compartilhar</b> (o quadrado com a seta para cima).</li>
              <li>Role e toque em <b>&quot;Adicionar à Tela de Início&quot;</b>.</li>
              <li>Toque em <b>&quot;Adicionar&quot;</b>.</li>
            </ol>
            <button
              type="button"
              onClick={() => setClosed(true)}
              className="w-full py-2.5 rounded-xl text-sm font-bold bg-primary text-white hover:bg-primary-hover active:bg-primary-active cursor-pointer"
            >
              Entendi
            </button>
          </>
        ) : (
          <div className="flex gap-2">
            <button
              type="button"
              onClick={promptInstall}
              className="flex-1 py-2.5 rounded-xl text-sm font-bold bg-primary text-white hover:bg-primary-hover active:bg-primary-active cursor-pointer"
            >
              Instalar
            </button>
            <button
              type="button"
              onClick={() => setClosed(true)}
              className="flex-1 py-2.5 rounded-xl text-sm font-medium border border-neutral-700 text-neutral-300 hover:bg-neutral-800 cursor-pointer"
            >
              Agora não
            </button>
          </div>
        )}
      </div>
    </div>
  )
}
