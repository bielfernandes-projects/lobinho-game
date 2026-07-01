'use client'

interface VictimInfo {
  name: string
  cause: string
}

interface DayAnnouncementProps {
  victims: VictimInfo[]
  turnIndex: number
  isHost?: boolean
  onStartDiscussion?: () => void
}

export function DayAnnouncement({ victims, turnIndex, isHost = false, onStartDiscussion }: DayAnnouncementProps) {
  const ninguemMorreu = victims.length === 0

  return (
    <div className="flex flex-1 flex-col items-center justify-center px-6 gap-8">
      <p className="text-neutral-600 text-xs uppercase tracking-widest">
        Dia {turnIndex + 1}
      </p>

      {ninguemMorreu ? (
        <div className="text-center">
          <p className="text-5xl mb-4">🌅</p>
          <p className="text-green-500 text-xl font-bold tracking-wider">
            Ninguém morreu
          </p>
          <p className="text-neutral-600 text-sm mt-2">
            A noite passou em branco
          </p>
        </div>
      ) : (
        <div className="text-center space-y-6">
          {victims.map((v, i) => (
            <div key={i} className="animate-pulse">
              <p className="text-6xl mb-4">☠️</p>
              <p className="text-red-500 text-2xl font-black tracking-widest uppercase drop-shadow-[0_0_15px_rgba(220,38,38,0.5)]">
                {v.name}
              </p>
              {isHost && (
                <p className="text-neutral-500 text-sm mt-2">
                  {v.cause === 'lobisomem' && 'morto pelos lobisomens'}
                  {v.cause === 'veneno' && 'envenenado'}
                </p>
              )}
            </div>
          ))}
        </div>
      )}

      {isHost && onStartDiscussion && (
        <button
          onClick={onStartDiscussion}
          className="px-6 py-3 rounded-xl text-sm font-bold tracking-wider bg-red-700 text-white hover:bg-red-600 active:bg-red-800 shadow-lg shadow-red-900/40 transition-all duration-200 cursor-pointer"
        >
          Iniciar Debate
        </button>
      )}
    </div>
  )
}
