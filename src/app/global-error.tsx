'use client'

import { useEffect } from 'react'

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string }
  reset: () => void
}) {
  useEffect(() => {
    console.error('[GlobalError]', error)
  }, [error])

  return (
    <html lang="pt-BR">
      <body className="min-h-dvh flex flex-col bg-neutral-950 text-neutral-200 font-sans items-center justify-center px-6 gap-6">
        <p className="text-6xl">💥</p>
        <p className="text-neutral-300 text-lg font-bold text-center">
          Algo deu errado
        </p>
        <p className="text-neutral-600 text-xs text-center max-w-xs">
          Ocorreu um erro inesperado. Tente recarregar a página.
        </p>
        <button
          onClick={reset}
          className="px-6 py-3 rounded-xl text-sm font-bold tracking-wider bg-red-700 text-white hover:bg-red-600 active:bg-red-800 shadow-lg shadow-red-900/40 transition-all duration-200 cursor-pointer"
        >
          Tentar Novamente
        </button>
      </body>
    </html>
  )
}
