'use client'

export function DeadPlayerScreen() {
  return (
    <div className="flex flex-1 flex-col items-center justify-center min-h-dvh bg-black px-6 gap-6">
      <div className="text-center space-y-6 max-w-xs">
        <div className="text-7xl select-none opacity-60">💀</div>

        <p className="text-red-800 text-xs uppercase tracking-[0.3em] font-bold">
          Você está morto
        </p>

        <p className="text-neutral-700 text-sm leading-relaxed select-none">
          Acompanhe a partida em silêncio.
        </p>

        <div className="w-12 h-[1px] bg-neutral-900 mx-auto" />

        <p className="text-neutral-800 text-[10px] uppercase tracking-wider select-none">
          Não interaja até o fim do jogo
        </p>
      </div>
    </div>
  )
}
