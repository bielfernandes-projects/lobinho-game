// Win conditions for the Caderneta: a TypeScript mirror of `compute_winner` in
// supabase/functions/compute_winner.sql (priority table: docs/game_rules.md section 6).
// Pure and dependency-free: run directly by `node --test`.

export type Winner =
  | 'lone_wolf_win'
  | 'chupacabra_win'
  | 'soulmates_win'
  | 'cult_win'
  | 'vampires_win'
  | 'tanner_win'
  | 'villagers_win'
  | 'wolves_win'

export interface WinnerPlayer {
  id: string
  role: string
  alive: boolean
  tags: readonly string[]
}

// Mirrors `wolf_team_roles()` in supabase/functions/role_groups.sql.
// The Lone Wolf is NOT in it: for the parity count it is one of the "others".
export const WOLF_TEAM_ROLES: readonly string[] = [
  'werewolf', 'wolf_cub', 'alpha_wolf', 'dire_wolf', 'virginia_wolf', 'sorceress', 'minion',
  // Caderneta-only wolves (no SQL mirror yet).
  'bad_wolf', 'fruit_brute', 'wolverine',
]

export const WINNER_VIEW: Record<Winner, { emoji: string; title: string }> = {
  soulmates_win: { emoji: '💕', title: 'O AMOR VENCEU!' },
  cult_win: { emoji: '🔮', title: 'O CULTO DOMINOU A VILA!' },
  tanner_win: { emoji: '👔', title: 'O CURTIDOR VENCEU' },
  vampires_win: { emoji: '🧛', title: 'OS VAMPIROS DOMINARAM A NOITE!' },
  wolves_win: { emoji: '🐺', title: 'VITÓRIA DO TIME DOS LOBOS' },
  lone_wolf_win: { emoji: '🐺', title: 'O LOBO SOLITÁRIO VENCEU!' },
  chupacabra_win: { emoji: '🦇', title: 'O CHUPACU VENCEU!' },
  villagers_win: { emoji: '🏆', title: 'VITÓRIA DO TIME DA VILA' },
}

/**
 * The Hoodlum's goal (alive, exactly 2 `hoodlum`-tagged players, both dead). It is NOT a game-ending
 * winner: the master decides whether to announce it, so the UI just shows a notice.
 */
export function hoodlumDone(players: readonly WinnerPlayer[]): WinnerPlayer | null {
  const targets = players.filter((p) => p.tags.includes('hoodlum'))
  if (targets.length !== 2 || !targets.every((p) => !p.alive)) return null
  return players.find((p) => p.alive && p.role === 'hoodlum') ?? null
}

export function wolfCounts(players: readonly WinnerPlayer[]): { alive: number; wolves: number; others: number } {
  let alive = 0
  let wolves = 0
  for (const p of players) {
    if (!p.alive) continue
    alive++
    if (WOLF_TEAM_ROLES.includes(p.role)) wolves++
  }
  return { alive, wolves, others: alive - wolves }
}

/**
 * Who has won, or null while the game goes on. Same order as the SQL:
 * last one standing > soulmates > cult > tanner > vampires > wolf team vs the rest.
 * Vampires (Caderneta-only, not in the SQL yet): only while no wolves live, they win once they are at least half of the living; while
 * vampires live the wolves cannot win by parity (they must wipe out the vampires too).
 *
 * Like the database trigger, it only fires once someone has died, and (a Caderneta
 * simplification) it says nothing when nobody is left alive.
 * Soulmates = exactly two players carry the `soulmate` tag, both alive, nobody else alive.
 * Cult = the leader is alive and every other living player carries the `cult` tag.
 * Tanner needs `lastLynchId`: the host must register the death as a lynch.
 */
export function computeWinner(players: readonly WinnerPlayer[], lastLynchId: string | null): Winner | null {
  if (players.every((p) => p.alive)) return null
  const { alive, wolves, others } = wolfCounts(players)
  if (alive === 0) return null

  const loneWolf = players.some((p) => p.alive && p.role === 'lone_wolf')
  const chupacabra = players.some((p) => p.alive && p.role === 'chupacabra')

  if (alive === 1 && loneWolf) return 'lone_wolf_win'
  if (alive === 1 && chupacabra) return 'chupacabra_win'

  const soulmates = players.filter((p) => p.tags.includes('soulmate'))
  if (alive === 2 && soulmates.length === 2 && soulmates.every((p) => p.alive)) return 'soulmates_win'

  if (
    players.some((p) => p.alive && p.role === 'cult_leader') &&
    players.every((p) => !p.alive || p.role === 'cult_leader' || p.tags.includes('cult'))
  ) {
    return 'cult_win'
  }

  if (lastLynchId && players.some((p) => p.id === lastLynchId && p.role === 'tanner' && !p.alive)) {
    return 'tanner_win'
  }

  const vampires = players.filter((p) => p.alive && p.role === 'vampire').length
  if (vampires > 0) {
    return wolves === 0 && vampires >= alive - vampires ? 'vampires_win' : null
  }

  if (wolves === 0) {
    if (loneWolf) return alive <= 2 ? 'lone_wolf_win' : null
    if (chupacabra) return alive <= 2 ? 'chupacabra_win' : null
    return 'villagers_win'
  }
  if (wolves >= others) return 'wolves_win'
  return null
}
