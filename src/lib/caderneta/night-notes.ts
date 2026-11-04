// Reminders the master needs while waking the wolves (Caderneta-only wolf cards).
// Pure: run directly by `node --test`.
import { WOLF_TEAM_ROLES, type WinnerPlayer } from './winner.ts'

export function wolvesStepNotes(players: readonly WinnerPlayer[], turn: number): string[] {
  const alive = players.filter((p) => p.alive)
  const has = (role: string) => alive.some((p) => p.role === role)
  const wolfTeamAlive = alive.filter((p) => WOLF_TEAM_ROLES.includes(p.role))
  const notes: string[] = []

  if (has('bad_wolf')) notes.push('🐺 Lobo Mau vivo: os lobos podem eliminar 2 jogadores adjacentes.')
  if (has('fruit_brute') && turn > 1) {
    const others = wolfTeamAlive.some((p) => p.role !== 'fruit_brute')
    if (others) notes.push('🍎 Lobo Vegetariano não acorda esta noite (há outros lobos).')
  }
  if (wolfTeamAlive.length === 1 && wolfTeamAlive[0].role === 'wolverine') {
    notes.push('🐾 Wolverine é o último lobo: ele não consegue eliminar ninguém esta noite.')
  }
  return notes
}
