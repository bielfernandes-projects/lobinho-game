// Caderneta do Mestre: pure state + reducer. No React, no Supabase.
// Relative `.ts` imports on purpose: this file is run directly by `node --test`.
import { CARD_CATALOG, DRUNK_ALLOWED } from '../cards.ts'
import { NIGHT_STEPS, stepIsAvailable, type NightStep } from '../night-steps.ts'
import { MAX_PLAYERS, rolesFromCounts, type ScenarioCounts } from '../scenario.ts'
import { computeWinner, wolfCounts, type Winner } from './winner.ts'

export type Phase = 'setup' | 'deal' | 'play' | 'ended'
export type View = 'night' | 'day'
export type Tag = 'soulmate' | 'protected' | 'cult' | 'pox' | 'blessed' | 'companion'
export type Rng = () => number

export const TAGS: { id: Tag; label: string }[] = [
  { id: 'soulmate', label: '💞 Alma gêmea' },
  { id: 'protected', label: '🛡️ Protegido' },
  { id: 'cult', label: '🔮 Culto' },
  { id: 'pox', label: '🤒 Varíola' },
  { id: 'blessed', label: '🙏 Abençoado' },
  { id: 'companion', label: '🔗 Companheiro' },
]

export const MAX_STRIKES = 3
export const NAME_MAX = 30
export const NOTE_MAX = 140
const STATE_VERSION = 1

export interface CadernetaPlayer {
  id: string
  name: string
  role: string
  alive: boolean
  tags: Tag[]
  note: string
  strikes: number
}

export interface CadernetaState {
  v: 1
  phase: Phase
  names: string[]
  players: CadernetaPlayer[]
  drunkHiddenRole: string | null
  dealIndex: number
  view: View
  turn: number
  doneSteps: string[]
  /** Player the host lynched last (the Tanner only wins if he was lynched). */
  lastLynchId: string | null
}

export type Action =
  | { type: 'load'; state: CadernetaState }
  | { type: 'reset' }
  | { type: 'setNames'; names: string[] }
  | { type: 'deal'; roles: string[]; drunkHiddenRole: string | null }
  | { type: 'nextDeal' }
  | { type: 'cancel' }
  | { type: 'setAlive'; id: string; alive: boolean }
  | { type: 'lynch'; id: string }
  | { type: 'toggleTag'; id: string; tag: Tag }
  | { type: 'setNote'; id: string; note: string }
  | { type: 'setRole'; id: string; role: string }
  | { type: 'toggleStep'; step: string }
  | { type: 'toNight' }
  | { type: 'toDay' }
  | { type: 'addStrike'; id: string }
  | { type: 'removeStrike'; id: string }
  | { type: 'end' }

const ROLE_IDS = new Set<string>(CARD_CATALOG.map((c) => c.id))
const TAG_IDS = new Set<string>(TAGS.map((t) => t.id))
const PHASES: Phase[] = ['setup', 'deal', 'play', 'ended']

export function initialState(): CadernetaState {
  return {
    v: STATE_VERSION,
    phase: 'setup',
    names: [],
    players: [],
    drunkHiddenRole: null,
    dealIndex: 0,
    view: 'night',
    turn: 1,
    doneSteps: [],
    lastLynchId: null,
  }
}

/** Fisher-Yates over one entry per card. `rng` is injectable for tests. */
export function drawRoles(counts: ScenarioCounts, rng: Rng = Math.random): string[] {
  const roles = rolesFromCounts(counts)
  for (let i = roles.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1))
    const tmp = roles[i]
    roles[i] = roles[j]
    roles[j] = tmp
  }
  return roles
}

export function pickDrunkRole(hasDrunk: boolean, choice: string, rng: Rng = Math.random): string | null {
  if (!hasDrunk) return null
  if (choice !== 'random') return choice
  return DRUNK_ALLOWED[Math.floor(rng() * DRUNK_ALLOWED.length)]
}

export function addName(names: string[], raw: string): { names: string[]; error: string | null } {
  const name = raw.trim().replace(/\s+/g, ' ')
  if (!name) return { names, error: 'Digite um nome' }
  if (name.length > NAME_MAX) return { names, error: `Máximo de ${NAME_MAX} caracteres` }
  if (names.some((n) => n.toLowerCase() === name.toLowerCase())) {
    return { names, error: 'Esse nome já está na lista' }
  }
  if (names.length >= MAX_PLAYERS) return { names, error: `Máximo de ${MAX_PLAYERS} jogadores` }
  return { names: [...names, name], error: null }
}

function mapPlayer(
  state: CadernetaState,
  id: string,
  fn: (p: CadernetaPlayer) => CadernetaPlayer,
): CadernetaState {
  if (!state.players.some((p) => p.id === id)) return state
  return { ...state, players: state.players.map((p) => (p.id === id ? fn(p) : p)) }
}

const clampStrikes = (n: number) => Math.min(MAX_STRIKES, Math.max(0, n))

export function reducer(state: CadernetaState, action: Action): CadernetaState {
  switch (action.type) {
    case 'load':
      return action.state
    case 'reset':
      return initialState()
    case 'setNames':
      return state.phase === 'setup' ? { ...state, names: action.names } : state
    case 'deal': {
      if (state.phase !== 'setup' || action.roles.length !== state.names.length) return state
      const players: CadernetaPlayer[] = state.names.map((name, i) => ({
        id: `p${i}`,
        name,
        role: action.roles[i],
        alive: true,
        tags: [],
        note: '',
        strikes: 0,
      }))
      return {
        ...state,
        phase: 'deal',
        players,
        drunkHiddenRole: action.drunkHiddenRole,
        dealIndex: 0,
        view: 'night',
        turn: 1,
        doneSteps: [],
        lastLynchId: null,
      }
    }
    case 'nextDeal': {
      if (state.phase !== 'deal') return state
      const next = state.dealIndex + 1
      return next >= state.players.length
        ? { ...state, phase: 'play', dealIndex: next }
        : { ...state, dealIndex: next }
    }
    case 'cancel':
      return { ...initialState(), names: state.names }
    case 'setAlive': {
      const next = mapPlayer(state, action.id, (p) => ({ ...p, alive: action.alive }))
      // Bringing the lynched player back undoes the lynch.
      return action.alive && action.id === state.lastLynchId ? { ...next, lastLynchId: null } : next
    }
    case 'lynch': {
      const next = mapPlayer(state, action.id, (p) => ({ ...p, alive: false }))
      return next === state ? state : { ...next, lastLynchId: action.id }
    }
    case 'toggleTag':
      return mapPlayer(state, action.id, (p) => ({
        ...p,
        tags: p.tags.includes(action.tag) ? p.tags.filter((t) => t !== action.tag) : [...p.tags, action.tag],
      }))
    case 'setNote':
      return mapPlayer(state, action.id, (p) => ({ ...p, note: action.note.slice(0, NOTE_MAX) }))
    case 'setRole':
      if (!ROLE_IDS.has(action.role)) return state
      return mapPlayer(state, action.id, (p) => ({ ...p, role: action.role }))
    case 'toggleStep':
      return {
        ...state,
        doneSteps: state.doneSteps.includes(action.step)
          ? state.doneSteps.filter((s) => s !== action.step)
          : [...state.doneSteps, action.step],
      }
    case 'toNight':
      return state.phase === 'play'
        ? { ...state, view: 'night', turn: state.turn + 1, doneSteps: [], lastLynchId: null }
        : state
    case 'toDay':
      return state.phase === 'play' ? { ...state, view: 'day' } : state
    case 'addStrike':
      return mapPlayer(state, action.id, (p) => ({ ...p, strikes: clampStrikes(p.strikes + 1) }))
    case 'removeStrike':
      return mapPlayer(state, action.id, (p) => ({ ...p, strikes: clampStrikes(p.strikes - 1) }))
    case 'end':
      return state.phase === 'play' ? { ...state, phase: 'ended' } : state
  }
}

// ---- selectors ----

/** Current roles of everyone, alive or dead (the host may still "wake" dead roles to bluff). */
export function rolesInGame(state: CadernetaState): Set<string> {
  return new Set(state.players.map((p) => p.role))
}

export function nightSteps(state: CadernetaState): NightStep[] {
  const roles = rolesInGame(state)
  return NIGHT_STEPS.filter((s) => stepIsAvailable(s, state.turn, roles))
}

export function nextStepId(state: CadernetaState): string | undefined {
  return nightSteps(state).find((s) => !state.doneSteps.includes(s.id))?.id
}

/** Alive players split like the win check does (wolf team vs everyone else). */
export function aliveCounts(state: CadernetaState): { alive: number; wolves: number; others: number } {
  return wolfCounts(state.players)
}

/** Who has won by the count of the living, or null. Only meaningful once the game started. */
export function winnerOf(state: CadernetaState): Winner | null {
  if (state.phase !== 'play' && state.phase !== 'ended') return null
  return computeWinner(state.players, state.lastLynchId)
}

// ---- persistence guard ----

const isStringArray = (v: unknown): v is string[] =>
  Array.isArray(v) && v.every((x) => typeof x === 'string')

function sanitizePlayer(raw: unknown): CadernetaPlayer | null {
  if (!raw || typeof raw !== 'object') return null
  const p = raw as Record<string, unknown>
  if (typeof p.id !== 'string' || typeof p.name !== 'string' || typeof p.note !== 'string') return null
  if (typeof p.role !== 'string' || !ROLE_IDS.has(p.role)) return null
  if (typeof p.alive !== 'boolean') return null
  if (!Array.isArray(p.tags) || !p.tags.every((t) => typeof t === 'string' && TAG_IDS.has(t))) return null
  if (typeof p.strikes !== 'number' || !Number.isInteger(p.strikes) || p.strikes < 0 || p.strikes > MAX_STRIKES) {
    return null
  }
  return { id: p.id, name: p.name, role: p.role, alive: p.alive, tags: p.tags as Tag[], note: p.note, strikes: p.strikes }
}

/** Returns a valid state from untrusted JSON, or null (corrupt / other version). */
export function sanitizeState(raw: unknown): CadernetaState | null {
  if (!raw || typeof raw !== 'object') return null
  const s = raw as Record<string, unknown>
  if (s.v !== STATE_VERSION) return null
  if (typeof s.phase !== 'string' || !PHASES.includes(s.phase as Phase)) return null
  if (!isStringArray(s.names) || !isStringArray(s.doneSteps) || !Array.isArray(s.players)) return null
  const players: CadernetaPlayer[] = []
  for (const r of s.players) {
    const p = sanitizePlayer(r)
    if (!p) return null
    players.push(p)
  }
  const phase = s.phase as Phase
  if (phase !== 'setup' && players.length === 0) return null
  if (typeof s.dealIndex !== 'number' || !Number.isInteger(s.dealIndex)) return null
  if (s.dealIndex < 0 || s.dealIndex > players.length) return null
  if (phase === 'deal' && s.dealIndex >= players.length) return null
  if (s.view !== 'night' && s.view !== 'day') return null
  if (typeof s.turn !== 'number' || !Number.isInteger(s.turn) || s.turn < 1) return null
  if (s.drunkHiddenRole !== null && (typeof s.drunkHiddenRole !== 'string' || !ROLE_IDS.has(s.drunkHiddenRole))) {
    return null
  }
  // Absent in games saved before the lynch existed: treat as "nobody lynched".
  const lastLynchId = s.lastLynchId ?? null
  if (lastLynchId !== null && typeof lastLynchId !== 'string') return null
  return {
    v: STATE_VERSION,
    phase,
    names: s.names,
    players,
    drunkHiddenRole: s.drunkHiddenRole as string | null,
    dealIndex: s.dealIndex,
    view: s.view,
    turn: s.turn,
    doneSteps: s.doneSteps,
    lastLynchId,
  }
}
