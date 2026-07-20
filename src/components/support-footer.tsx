'use client'

export function SupportFooter() {
  return (
    <div className="w-full max-w-xs mx-auto rounded-xl border border-neutral-800 bg-neutral-900/60 px-4 py-4 text-center space-y-3">
      <p className="text-neutral-400 text-xs font-medium tracking-wider">
        ❤️ Ajude o Dev
      </p>
      <p className="text-neutral-600 text-[10px] leading-relaxed">
        O Lobinho é gratuito e sem anúncios.
        <br />
        Se quiser contribuir, aceito um Pix
        <br />
        ou mande sugestões por e-mail. 💛
      </p>

      <div className="flex gap-2">
        <a
          href="https://nubank.com.br/cobrar/33flp/6a344314-311f-4227-828e-eb97b67db887"
          target="_blank"
          rel="noopener noreferrer"
          className="flex-1 py-2.5 rounded-xl text-xs font-medium tracking-wider
            bg-yellow-900/20 border border-yellow-800/40 text-yellow-400
            hover:bg-yellow-900/30 hover:border-yellow-700/50
            transition-all duration-200 cursor-pointer text-center"
        >
          💛 Fazer um Pix
        </a>
        <a
          href="mailto:gabriel.fernandeshw@gmail.com?subject=Sugest%C3%A3o%20Lobinho"
          className="flex-1 py-2.5 rounded-xl text-xs font-medium tracking-wider
            bg-neutral-900 border border-neutral-800 text-neutral-400
            hover:border-neutral-700 hover:text-neutral-300
            transition-all duration-200 cursor-pointer text-center"
        >
          📧 Enviar E-mail
        </a>
      </div>
    </div>
  )
}
