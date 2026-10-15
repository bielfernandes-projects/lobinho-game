// Pure scenario maths shared by the online ScenarioBuilder and the Caderneta.
// Relative `.ts` imports on purpose: this file is run directly by `node --test`.
import { CARD_CATALOG } from './cards.ts'

export const MIN_PLAYERS = 6
export const MAX_PLAYERS = 77

export type ScenarioCounts = Record<string, number>
export type Balance = 'wolves' | 'balanced' | 'village'

export function emptyCounts(): ScenarioCounts {
  return Object.fromEntries(CARD_CATALOG.map((c) => [c.id, 0]))
}

export function countCards(counts: ScenarioCounts): number {
  return CARD_CATALOG.reduce((sum, c) => sum + (counts[c.id] ?? 0), 0)
}

export function totalPoints(counts: ScenarioCounts): number {
  return CARD_CATALOG.reduce((sum, c) => sum + c.points * (counts[c.id] ?? 0), 0)
}

export function balanceOf(points: number): Balance {
  if (points < -3) return 'wolves'
  if (points > 3) return 'village'
  return 'balanced'
}

export function isValidScenario(counts: ScenarioCounts, playerCount: number): boolean {
  return (
    countCards(counts) === playerCount &&
    playerCount >= MIN_PLAYERS &&
    playerCount <= MAX_PLAYERS
  )
}

/** One entry per card, in catalog order (the caller shuffles when it needs to). */
export function rolesFromCounts(counts: ScenarioCounts): string[] {
  const roles: string[] = []
  for (const card of CARD_CATALOG) {
    for (let i = 0; i < (counts[card.id] ?? 0); i++) roles.push(card.id)
  }
  return roles
}
