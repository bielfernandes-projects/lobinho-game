// Ready-made scenarios and the ones the master saves (browser only).
// Pure: run directly by `node --test`. Relative `.ts` imports on purpose.
import { CARD_CATALOG, roleName } from '../cards.ts'
import { balanceOf, countCards, totalPoints, type Balance, type ScenarioCounts } from '../scenario.ts'

export interface ScenarioPreset {
  id: string
  name: string
  /** Only the roles that are in it (the rest is zero). */
  counts: ScenarioCounts
}

// Lobinho's own suggestions (there is no official list), each balanced by the points system.
export const PRESETS: ScenarioPreset[] = [
  { id: 'minimo-2-lobos', name: 'Mínimo (6 jogadores)', counts: { werewolf: 2, seer: 1, witch: 1, villager: 2 } },
  { id: 'minimo-1-lobo', name: 'Mínimo com 1 lobo (6 jogadores)', counts: { werewolf: 1, seer: 1, cupid: 1, villager: 3 } },
  { id: 'classico', name: 'Clássico', counts: { werewolf: 2, seer: 1, witch: 1, villager: 4 } },
  { id: 'com-amor', name: 'Com amor', counts: { werewolf: 2, seer: 1, cupid: 1, hunter: 1, villager: 3 } },
  { id: 'rapido', name: 'Jogo Rápido', counts: { werewolf: 2, seer: 1, hunter: 1, huntress: 1, marksman: 1, mad_bomber: 1, cupid: 1 } },
  { id: 'guarda-costas', name: 'Guarda-costas', counts: { werewolf: 2, wolf_cub: 1, seer: 1, bodyguard: 1, hunter: 1, villager: 4 } },
  { id: 'cacada', name: 'Caçada', counts: { werewolf: 1, alpha_wolf: 1, seer: 1, witch: 1, hunter: 1, villager: 4 } },
  { id: 'vila-animada', name: 'Vila animada', counts: { werewolf: 3, seer: 1, witch: 1, bodyguard: 1, mayor: 1, cupid: 1, villager: 4 } },
  { id: 'caotico', name: 'Caótico', counts: { werewolf: 2, seer: 1, witch: 1, tanner: 1, cupid: 1, priest: 1, hunter: 1, lycan: 1, villager: 3 } },
]

/** The roles of a scenario in catalog order, with how many of each. */
export function countEntries(counts: ScenarioCounts): { id: string; n: number }[] {
  return CARD_CATALOG.filter((c) => (counts[c.id] ?? 0) > 0).map((c) => ({ id: c.id, n: counts[c.id] }))
}

/** "2× Werewolf (Lobisomem), Seer (Vidente)" in catalog order. */
export function describeCounts(counts: ScenarioCounts): string {
  return countEntries(counts)
    .map(({ id, n }) => (n > 1 ? `${n}× ${roleName(id)}` : roleName(id)))
    .join(', ')
}

export function summarize(counts: ScenarioCounts): { cards: number; points: number; balance: Balance } {
  const points = totalPoints(counts)
  return { cards: countCards(counts), points, balance: balanceOf(points) }
}

// ---- saved by the master ----

export interface SavedScenario {
  name: string
  counts: ScenarioCounts
}

export const SAVED_MAX = 20
export const SAVED_NAME_MAX = 30
export const SAVED_KEY = 'lobinho:caderneta:saved-scenarios'

const ROLE_IDS = new Set<string>(CARD_CATALOG.map((c) => c.id))

function cleanCounts(raw: unknown): ScenarioCounts | null {
  if (!raw || typeof raw !== 'object') return null
  const out: ScenarioCounts = {}
  for (const [id, n] of Object.entries(raw as Record<string, unknown>)) {
    if (!ROLE_IDS.has(id) || typeof n !== 'number' || !Number.isInteger(n) || n < 0) return null
    if (n > 0) out[id] = n
  }
  return Object.keys(out).length > 0 ? out : null
}

/** Reads the saved list from untrusted JSON; anything malformed is dropped. */
export function parseSaved(raw: string | null): SavedScenario[] {
  if (!raw) return []
  let data: unknown
  try {
    data = JSON.parse(raw)
  } catch {
    return []
  }
  if (!Array.isArray(data)) return []
  const out: SavedScenario[] = []
  for (const item of data) {
    if (!item || typeof item !== 'object') continue
    const { name, counts } = item as Record<string, unknown>
    const clean = cleanCounts(counts)
    if (typeof name !== 'string' || !name.trim() || name.length > SAVED_NAME_MAX || !clean) continue
    out.push({ name, counts: clean })
  }
  return out.slice(0, SAVED_MAX)
}

/** Adds (or overwrites by name, case-insensitive) a scenario; the newest comes first. */
export function saveScenario(
  list: SavedScenario[],
  rawName: string,
  counts: ScenarioCounts,
): { list: SavedScenario[]; error: string | null } {
  const name = rawName.trim().replace(/\s+/g, ' ')
  if (!name) return { list, error: 'Dê um nome ao cenário' }
  if (name.length > SAVED_NAME_MAX) return { list, error: `Máximo de ${SAVED_NAME_MAX} caracteres` }
  const clean = cleanCounts(counts)
  if (!clean) return { list, error: 'Escolha ao menos uma carta' }
  const without = list.filter((s) => s.name.toLowerCase() !== name.toLowerCase())
  if (without.length >= SAVED_MAX) return { list, error: `Máximo de ${SAVED_MAX} cenários salvos` }
  return { list: [{ name, counts: clean }, ...without], error: null }
}

export function removeScenario(list: SavedScenario[], name: string): SavedScenario[] {
  return list.filter((s) => s.name !== name)
}
