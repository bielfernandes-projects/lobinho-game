// Night steps: the ONE table that says who wakes, when, in which order, and what they may do.
// Adding a night role = one entry here (plus its panel in renderNightPanel and its SQL).

// Roles that wake with the wolves (the 'wolves' step).
export const WOLF_ROLES = ['werewolf', 'wolf_cub', 'alpha_wolf', 'lone_wolf', 'dire_wolf', 'virginia_wolf']

/** Which nights a step happens on. */
export type NightRule = 'any' | 'first' | 'third' | 'not_first'

export interface NightStep {
  /** value stored in game_state.night_step */
  id: string
  /** player roles that make this step relevant (any of them alive in the game) */
  roles: string[]
  /** role whose colour styles the host button */
  styleRole: string
  /** short name shown in "Vez de acordar" */
  label: string
  /** host button text */
  wakeLabel: string
  when: NightRule
  /** night_actions.action_type values that mean "this step is done" */
  actions: string[]
}

// Array order IS the wake order (dependencies: the Witch after the wolves, etc.).
export const NIGHT_STEPS: NightStep[] = [
  { id: 'drunk', roles: ['drunk'], styleRole: 'drunk', label: '🍺 Bêbado', wakeLabel: '🍺 Acordar Bêbado', when: 'third', actions: [] },
  { id: 'masons', roles: ['mason'], styleRole: 'mason', label: '🧱 Maçons', wakeLabel: '🧱 Acordar Maçons', when: 'first', actions: [] },
  { id: 'cupid', roles: ['cupid'], styleRole: 'cupid', label: '💘 Cupido', wakeLabel: '💘 Acordar Cupido', when: 'first', actions: [] },
  { id: 'doppelganger', roles: ['doppelganger'], styleRole: 'doppelganger', label: '🎭 Doppelgänger', wakeLabel: '🎭 Acordar Doppelgänger', when: 'first', actions: ['doppelganger_select'] },
  { id: 'minion', roles: ['minion'], styleRole: 'minion', label: '😈 Lacaio', wakeLabel: '😈 Acordar Lacaio', when: 'first', actions: [] },
  { id: 'priest', roles: ['priest'], styleRole: 'priest', label: '🙏 Padre', wakeLabel: '🙏 Acordar Padre', when: 'any', actions: ['priest_bless'] },
  { id: 'bodyguard', roles: ['bodyguard'], styleRole: 'bodyguard', label: '🛡️ Guarda-costas', wakeLabel: '🛡️ Acordar Guarda-costas', when: 'any', actions: ['bodyguard_protect'] },
  { id: 'wolves', roles: WOLF_ROLES, styleRole: 'werewolf', label: '🐺 Lobisomens', wakeLabel: '🐺 Acordar Lobos', when: 'any', actions: ['werewolf_kill'] },
  { id: 'dire_wolf', roles: ['dire_wolf'], styleRole: 'dire_wolf', label: '🐺 Lobo Aproveitador', wakeLabel: '🐺 Acordar Lobo Aproveitador', when: 'first', actions: ['dire_wolf_companion'] },
  { id: 'virginia_wolf', roles: ['virginia_wolf'], styleRole: 'virginia_wolf', label: '🐺 Virginia Wolf', wakeLabel: '🐺 Acordar Virginia Wolf', when: 'first', actions: ['virginia_partner'] },
  { id: 'witch', roles: ['witch'], styleRole: 'witch', label: '🧪 Bruxa', wakeLabel: '🧪 Acordar Bruxa', when: 'not_first', actions: ['witch_save', 'witch_poison', 'witch_skip'] },
  { id: 'seer', roles: ['seer'], styleRole: 'seer', label: '🔮 Vidente', wakeLabel: '🔮 Acordar Vidente', when: 'any', actions: ['seer_investigate'] },
  { id: 'aura_seer', roles: ['aura_seer'], styleRole: 'aura_seer', label: '👁️ Vidente de Aura', wakeLabel: '👁️ Acordar Vidente de Aura', when: 'any', actions: ['aura_investigate'] },
  { id: 'sorceress', roles: ['sorceress'], styleRole: 'sorceress', label: '🔮 Feiticeira', wakeLabel: '🔮 Acordar Feiticeira', when: 'any', actions: ['sorceress_search'] },
  { id: 'chupacabra', roles: ['chupacabra'], styleRole: 'chupacabra', label: '🦇 Chupacu', wakeLabel: '🦇 Acordar Chupacu', when: 'any', actions: ['chupacabra_kill'] },
  { id: 'huntress', roles: ['huntress'], styleRole: 'huntress', label: '🏹 Caçadora', wakeLabel: '🏹 Acordar Caçadora', when: 'any', actions: ['huntress_kill'] },
  { id: 'old_witch', roles: ['old_witch'], styleRole: 'old_witch', label: '🤒 Bruxa Velha', wakeLabel: '🤒 Acordar Bruxa Velha', when: 'any', actions: ['old_witch_pox'] },
  { id: 'cult_leader', roles: ['cult_leader'], styleRole: 'cult_leader', label: '🔮 Líder de Culto', wakeLabel: '🔮 Acordar Líder de Culto', when: 'any', actions: ['cult_convert'] },
]

export const WAKE_ORDER = NIGHT_STEPS.map((s) => s.id)

export const STEP_TO_ACTION_TYPES: Record<string, string[]> = Object.fromEntries(
  NIGHT_STEPS.map((s) => [s.id, s.actions])
)

export const NIGHT_ROLE_LABELS: Record<string, string> = Object.fromEntries(
  NIGHT_STEPS.map((s) => [s.id, s.label])
)

/** Every player role that can matter at night (used to ask the database who is in the game). */
export const NIGHT_ROLES = [...new Set(NIGHT_STEPS.flatMap((s) => s.roles))]

export function stepHappensOnNight(step: NightStep, turnIndex: number): boolean {
  switch (step.when) {
    case 'first': return turnIndex === 1
    case 'third': return turnIndex === 3
    case 'not_first': return turnIndex !== 1
    default: return true
  }
}

/** Is this step relevant: its night is right and one of its roles is in the game. */
export function stepIsAvailable(step: NightStep, turnIndex: number, availableRoles: Set<string>): boolean {
  return stepHappensOnNight(step, turnIndex) && step.roles.some((r) => availableRoles.has(r))
}

interface NextStepArgs {
  turnIndex: number
  nightStep: string
  wolvesResolved: boolean
  availableRoles: Set<string>
  /** steps already finished tonight */
  acted: Set<string>
}

/** The step the host should wake next, or undefined when the night is ready to resolve. */
export function nextStepToWake({ turnIndex, nightStep, wolvesResolved, availableRoles, acted }: NextStepArgs): string | undefined {
  return NIGHT_STEPS.find((s) => {
    if (!stepIsAvailable(s, turnIndex, availableRoles)) return false
    if (s.id === 'wolves') return nightStep !== 'wolves' && !wolvesResolved
    if (acted.has(s.id)) return false
    return nightStep !== s.id
  })?.id
}
