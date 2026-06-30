export interface Player {
  id: string
  name: string
  role?: string | null
  isAlive: boolean
  isHost: boolean
  userId: string
  hasViewedCard: boolean
  viewedCardAt?: string | null
  createdAt: string
}

export interface Room {
  id: string
  pinCode: string
  status: 'waiting' | 'playing' | 'finished'
  maxPlayers: number
  hostId: string
  createdAt: string
}

export interface GameState {
  roomId: string
  currentPhase: 'card_reveal' | 'night' | 'day' | 'vote' | 'ended'
  turnIndex: number
  phaseStartedAt: string
}

export interface NightAction {
  id: string
  roomId: string
  turnIndex: number
  actorId: string
  actionType: 'werewolf_kill' | 'seer_investigate'
  targetId: string
  result?: boolean | null
}

export interface Vote {
  id: string
  roomId: string
  turnIndex: number
  voterId: string
  targetId: string
}

export type ViewMode = 'card' | 'indicators'
export type Phase = 'card_reveal' | 'night' | 'day' | 'vote' | 'ended'
export type Role = 'werewolf' | 'seer' | 'witch' | 'villager' | 'moderator'
