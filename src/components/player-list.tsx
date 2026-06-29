interface PlayerListItem {
  id: string
  name: string
  isHost: boolean
  hasViewedCard: boolean
}

interface PlayerListProps {
  players: PlayerListItem[]
  currentPlayerId?: string
  showViewedIndicators?: boolean
}

export function PlayerList({
  players,
  currentPlayerId,
  showViewedIndicators,
}: PlayerListProps) {
  const total = players.length
  const viewed = players.filter((p) => p.hasViewedCard).length

  return (
    <div className="w-full max-w-sm mx-auto">
      <div className="flex items-center justify-between mb-3">
        <h2 className="text-neutral-400 text-sm uppercase tracking-widest">
          Jogadores
        </h2>
        <span className="text-neutral-600 text-xs">{total}/8</span>
      </div>

      <div className="space-y-2">
        {players.map((player) => {
          const isSelf = player.id === currentPlayerId
          return (
            <div
              key={player.id}
              className={`
                flex items-center gap-3 px-4 py-3 rounded-xl
                border transition-colors
                ${
                  isSelf
                    ? 'border-red-800/60 bg-red-950/20'
                    : 'border-neutral-800 bg-neutral-900/50'
                }
              `}
            >
              {/* Avatar com inicial */}
              <div
                className={`
                  w-10 h-10 rounded-full flex items-center justify-center
                  text-sm font-bold shrink-0
                  ${isSelf ? 'bg-red-800 text-white' : 'bg-neutral-800 text-neutral-400'}
                `}
              >
                {player.name.charAt(0).toUpperCase()}
              </div>

              {/* Nome */}
              <span
                className={`
                  flex-1 text-sm font-medium truncate
                  ${isSelf ? 'text-red-300' : 'text-neutral-300'}
                `}
              >
                {player.name}
                {isSelf && (
                  <span className="text-neutral-600 text-xs ml-2">(você)</span>
                )}
              </span>

              {/* Indicador de leitura (host view) */}
              {showViewedIndicators && (
                <span
                  className={`text-sm ${
                    player.hasViewedCard
                      ? 'text-green-500 drop-shadow-[0_0_6px_rgba(34,197,94,0.5)]'
                      : 'text-neutral-700'
                  }`}
                >
                  {player.hasViewedCard ? '👁️' : '◯'}
                </span>
              )}

              {/* Badge de Host */}
              {player.isHost && (
                <span className="text-[10px] uppercase tracking-wider bg-red-900/60 text-red-400 px-2 py-0.5 rounded-full font-semibold">
                  Host
                </span>
              )}
            </div>
          )
        })}
      </div>

      {showViewedIndicators && (
        <div className="mt-4 flex items-center justify-between text-xs">
          <span className="text-neutral-500">
            {viewed}/{total} leram a carta
          </span>
          <div className="flex-1 h-1.5 mx-3 rounded-full bg-neutral-800 overflow-hidden">
            <div
              className="h-full rounded-full bg-green-600 transition-all duration-300"
              style={{ width: `${total > 0 ? (viewed / total) * 100 : 0}%` }}
            />
          </div>
        </div>
      )}
    </div>
  )
}
