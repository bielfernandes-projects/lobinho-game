'use client'

import { WerewolfPanel } from './werewolf-panel'
import { SeerPanel } from './seer-panel'
import { WitchPanel } from './witch-panel'

interface NightPhaseProps {
  roomId: string
  role: string
  playerId: string
  turnIndex: number
  isAlive: boolean
  wolvesResolved: boolean
  wolfVictimName: string | null
}

export function NightPhase({
  roomId,
  role,
  playerId,
  turnIndex,
  isAlive,
  wolvesResolved,
  wolfVictimName,
}: NightPhaseProps) {
  // Moderador: nao age, apenas observa
  if (role === 'moderator') {
    return null
  }

  const noRole = role !== 'werewolf' && role !== 'seer' && role !== 'witch'

  // Lobo: ativo independente de wolvesResolved
  if (role === 'werewolf') {
    return (
      <div className="flex flex-1 flex-col items-center justify-center px-6 gap-6">
        <p className="text-neutral-600 text-xs uppercase tracking-widest select-none animate-pulse">
          🌙 Fechem os olhos...
        </p>
        <WerewolfPanel roomId={roomId} playerId={playerId} turnIndex={turnIndex} />
      </div>
    )
  }

  // Seer: ativo independente de wolvesResolved
  if (role === 'seer') {
    return (
      <div className="flex flex-1 flex-col items-center justify-center px-6 gap-6">
        <p className="text-neutral-600 text-xs uppercase tracking-widest select-none animate-pulse">
          🌙 Fechem os olhos...
        </p>
        <SeerPanel roomId={roomId} playerId={playerId} turnIndex={turnIndex} />
      </div>
    )
  }

  // Bruxa: so age apos lobos resolverem
  if (role === 'witch') {
    if (!wolvesResolved) {
      return (
        <div className="flex flex-1 flex-col items-center justify-center px-6 gap-6">
          <p className="text-neutral-600 text-xs uppercase tracking-widest select-none animate-pulse">
            🌙 Fechem os olhos...
          </p>
          <p className="text-neutral-800 text-sm select-none">
            Aguardando o ataque dos lobos...
          </p>
        </div>
      )
    }

    return (
      <div className="flex flex-1 flex-col items-center justify-center px-6 gap-6">
        <p className="text-neutral-600 text-xs uppercase tracking-widest select-none animate-pulse">
          🌙 Fechem os olhos...
        </p>
        <WitchPanel
          roomId={roomId}
          playerId={playerId}
          turnIndex={turnIndex}
          victimName={wolfVictimName}
        />
      </div>
    )
  }

  if (noRole || !isAlive) {
    return (
      <div className="flex flex-1 flex-col items-center justify-center px-6 gap-6">
        <p className="text-neutral-600 text-xs uppercase tracking-widest select-none animate-pulse">
          🌙 Fechem os olhos...
        </p>
        <p className="text-neutral-800 text-sm select-none">
          Aguarde o dia nascer...
        </p>
      </div>
    )
  }

  return null
}
