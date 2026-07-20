import { CARD_CATALOG } from './cards'

export type RevealMode = 'total' | 'team' | 'hidden'

const TEAM_LABELS: Record<string, string> = {
  village: 'Time da Vila',
  wolf: 'Time dos Lobos',
  independent: 'Facção Independente',
}

export function getRevealedRoleText(roleId: string, revealMode: RevealMode): string {
  const card = CARD_CATALOG.find((c) => c.id === roleId)

  if (revealMode === 'total') {
    return card?.name ?? roleId
  }

  if (revealMode === 'team') {
    if (!card) return roleId
    return card.team === 'village' ? 'Era da Vila' : 'Não era da Vila'
  }

  return 'Identidade Oculta'
}
