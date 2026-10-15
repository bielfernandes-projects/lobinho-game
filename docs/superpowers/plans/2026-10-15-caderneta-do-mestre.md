# Caderneta do Mestre Implementation Plan

> **Nota (histórico):** este é o plano da entrega inicial. Depois dos testes do usuário houve três revisões que **não** estão refletidas nos blocos de código abaixo: (1) vencedor pela contagem dos vivos (`src/lib/caderneta/winner.ts`, botão "Linchar", `WinnerBanner`) e cronômetro "Tempo da manhã" de 5 min; (2) a partida e o cenário da Caderneta passaram de `localStorage` para `sessionStorage`, com reset por "← Início" e por 30 min de inatividade (`src/hooks/use-idle-reset.ts`), e "Nova partida" mantendo jogadores e cenário; (3) o campo de nome mantém o foco (teclado aberto) ao adicionar. O estado final está descrito em `docs/architecture.md` e na spec.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Entregar o modo "Caderneta do Mestre" (um celular só, sem Supabase) como modo principal da home, mais a barra de pontuação fixa no construtor de cenário.

**Architecture:** Rota nova `/caderneta` com estado local num reducer puro (`src/lib/caderneta/state.ts`) persistido em `localStorage`. A UI de escolher cartas é extraída do `ScenarioBuilder` para `ScenarioCardPicker` (sem Supabase), compartilhado entre o modo online e a Caderneta, e é nele que a barra de pontuação fica `sticky`. Lógica pura testada com `node --test` (Node 24 roda `.ts` direto).

**Tech Stack:** Next.js 16 (App Router, webpack), React 19, Tailwind 4, TypeScript, `node:test`. Sem dependência nova.

**Spec:** `docs/superpowers/specs/2026-10-15-caderneta-do-mestre-design.md`

## Global Constraints

- Idioma de toda a UI e das mensagens: PT-BR, com acentuação correta.
- O nome "Impostor" **não pode aparecer** em nenhum texto, nome de arquivo, classe ou comentário do app.
- Nada de Supabase, sala, PIN ou migração no modo Caderneta. Sem `supabase db push`.
- Jogadores: mínimo 6, máximo 77 (mesma regra do online). Nome: até 30 caracteres, único (sem diferenciar maiúsculas). Nota: até 140 caracteres. Strikes: 0 a 3.
- Equilíbrio: soma < -3 = "Vantagem dos Lobos"; soma > 3 = "Vantagem da Aldeia"; entre -3 e 3 = "Equilibrado".
- `localStorage`: chave de partida `lobinho:caderneta:v1`; chave de cenário (já existente, compartilhada) `lobinho_last_scenario`. Todo acesso dentro de `try/catch`.
- Arquivos em `src/lib/` importados pelos testes usam **imports relativos com extensão `.ts`** (nada de alias `@/`); por isso `allowImportingTsExtensions` entra no `tsconfig.json`.
- Seguir `AGENTS.md`: atualizar `docs/architecture.md` antes do commit final; commit + push; deploy da Vercel é automático.
- Não alterar a lógica do jogo online (`start_game`, `rooms.update`, tribunal etc.).
- Visual: tokens e voz da marca (`docs/brand-guidelines.md`): `bg-midnight`, `bg-primary`, `font-display`, neutros escuros.

---

## File Structure

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `tsconfig.json` | modificar | `allowImportingTsExtensions` |
| `package.json` | modificar | script `test` |
| `src/lib/cards.ts` | modificar | exportar `DRUNK_ALLOWED` |
| `src/lib/scenario.ts` | criar | contagens, pontos, equilíbrio, validação (puro) |
| `src/lib/scenario.test.ts` | criar | testes de `scenario.ts` |
| `src/lib/caderneta/state.ts` | criar | tipos, reducer, sorteio, seletores, sanitização (puro) |
| `src/lib/caderneta/state.test.ts` | criar | testes de `state.ts` |
| `src/hooks/use-scenario-counts.ts` | criar | contagens do cenário persistidas |
| `src/hooks/use-caderneta.ts` | criar | reducer + persistência da partida |
| `src/components/scenario-card-picker.tsx` | criar | UI de cartas + termômetro fixo |
| `src/components/scenario-builder.tsx` | modificar | usa o picker (online inalterado) |
| `src/components/caderneta/setup-screen.tsx` | criar | nomes + cenário + sorteio |
| `src/components/caderneta/deal-screen.tsx` | criar | passa-o-celular + segurar para ver |
| `src/components/caderneta/players-list.tsx` | criar | lista de jogadores do painel |
| `src/components/caderneta/night-steps-list.tsx` | criar | lista de despertar |
| `src/components/caderneta/day-tools.tsx` | criar | cronômetro + strikes |
| `src/components/caderneta/play-panel.tsx` | criar | painel do mestre |
| `src/components/caderneta/end-screen.tsx` | criar | tela final |
| `src/app/caderneta/page.tsx` | criar | rota |
| `src/app/page.tsx` | modificar | Caderneta como modo principal |
| `docs/architecture.md` | modificar | entrada da mudança |

---

### Task 1: Infra de testes e módulo `scenario.ts`

**Files:**
- Modify: `tsconfig.json` (adicionar `allowImportingTsExtensions`)
- Modify: `package.json` (script `test`)
- Modify: `src/lib/cards.ts` (exportar `DRUNK_ALLOWED`)
- Create: `src/lib/scenario.ts`
- Test: `src/lib/scenario.test.ts`

**Interfaces:**
- Produces (`src/lib/scenario.ts`):
  - `MIN_PLAYERS = 6`, `MAX_PLAYERS = 77`
  - `type ScenarioCounts = Record<string, number>`
  - `type Balance = 'wolves' | 'balanced' | 'village'`
  - `emptyCounts(): ScenarioCounts`
  - `countCards(counts): number`
  - `totalPoints(counts): number`
  - `balanceOf(points: number): Balance`
  - `isValidScenario(counts, playerCount: number): boolean`
  - `rolesFromCounts(counts): string[]` (ordem do catálogo, um item por carta)
- Produces (`src/lib/cards.ts`): `DRUNK_ALLOWED: string[]`

- [ ] **Step 1: Habilitar imports `.ts` e o script de teste**

Em `tsconfig.json`, dentro de `compilerOptions`, depois de `"isolatedModules": true,` adicionar:

```json
    "allowImportingTsExtensions": true,
```

Em `package.json`, em `scripts`, depois de `"lint": "eslint"` (trocar a vírgula) adicionar:

```json
    "lint": "eslint",
    "test": "node --test \"src/lib/**/*.test.ts\""
```

- [ ] **Step 2: Mover `DRUNK_ALLOWED` para `cards.ts`**

Ao final de `src/lib/cards.ts` adicionar (lista idêntica à de `scenario-builder.tsx`):

```ts
// Reserve roles the Drunk may become: none with a crucial action on nights 1-2 (official recommendation).
export const DRUNK_ALLOWED = [
  'villager', 'werewolf', 'wolf_cub', 'alpha_wolf', 'hunter', 'prince', 'mayor', 'lycan', 'tanner',
  'pacifist', 'idiot', 'squire', 'marksman', 'diseased', 'cursed', 'martyr', 'tough_guy', 'huntress',
  'apprentice_seer',
]
```

(A remoção da cópia em `scenario-builder.tsx` acontece na Task 3.)

- [ ] **Step 3: Escrever o teste que falha**

`src/lib/scenario.test.ts`:

```ts
import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  balanceOf,
  countCards,
  emptyCounts,
  isValidScenario,
  rolesFromCounts,
  totalPoints,
} from './scenario.ts'

test('cenário vazio tem zero cartas e zero pontos', () => {
  assert.equal(countCards(emptyCounts()), 0)
  assert.equal(totalPoints(emptyCounts()), 0)
})

test('totalPoints soma os pontos do catálogo', () => {
  // seer +7, werewolf -6 (x2)
  assert.equal(totalPoints({ ...emptyCounts(), seer: 1, werewolf: 2 }), -5)
})

test('balanceOf respeita os limites -3 e 3', () => {
  assert.equal(balanceOf(-4), 'wolves')
  assert.equal(balanceOf(-3), 'balanced')
  assert.equal(balanceOf(0), 'balanced')
  assert.equal(balanceOf(3), 'balanced')
  assert.equal(balanceOf(4), 'village')
})

test('isValidScenario exige cartas == jogadores e 6..77', () => {
  const six = { ...emptyCounts(), villager: 4, werewolf: 1, seer: 1 }
  assert.equal(isValidScenario(six, 6), true)
  assert.equal(isValidScenario(six, 7), false)
  const five = { ...emptyCounts(), villager: 3, werewolf: 1, seer: 1 }
  assert.equal(isValidScenario(five, 5), false)
})

test('rolesFromCounts segue a ordem do catálogo, uma entrada por carta', () => {
  const roles = rolesFromCounts({ ...emptyCounts(), villager: 2, seer: 1, werewolf: 1 })
  assert.deepEqual(roles, ['werewolf', 'seer', 'villager', 'villager'])
})
```

- [ ] **Step 4: Rodar e ver falhar**

Run: `npm test`
Expected: FAIL com `Cannot find module './scenario.ts'` (ou `ERR_MODULE_NOT_FOUND`).

- [ ] **Step 5: Implementar `scenario.ts`**

`src/lib/scenario.ts`:

```ts
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
```

- [ ] **Step 6: Rodar e ver passar**

Run: `npm test`
Expected: PASS, 5 testes. Rodar também `npx tsc --noEmit` e esperar sem erros novos.

- [ ] **Step 7: Commit**

```bash
git add tsconfig.json package.json src/lib/cards.ts src/lib/scenario.ts src/lib/scenario.test.ts
git commit -m "feat: scenario maths module, node test runner"
```

---

### Task 2: Reducer e sorteio da Caderneta (`state.ts`)

**Files:**
- Create: `src/lib/caderneta/state.ts`
- Test: `src/lib/caderneta/state.test.ts`

**Interfaces:**
- Consumes: `ScenarioCounts`, `rolesFromCounts`, `MAX_PLAYERS` de `../scenario.ts`; `CARD_CATALOG`, `DRUNK_ALLOWED` de `../cards.ts`; `NIGHT_STEPS`, `stepIsAvailable`, `type NightStep` de `../night-steps.ts`.
- Produces (`src/lib/caderneta/state.ts`):
  - tipos `Phase`, `View`, `Tag`, `CadernetaPlayer`, `CadernetaState`, `Action`, `Rng`
  - `TAGS: { id: Tag; label: string }[]`, `MAX_STRIKES = 3`, `NAME_MAX = 30`, `NOTE_MAX = 140`
  - `initialState(): CadernetaState`
  - `reducer(state, action): CadernetaState`
  - `drawRoles(counts, rng?): string[]`
  - `pickDrunkRole(hasDrunk: boolean, choice: string, rng?): string | null`
  - `addName(names, raw): { names: string[]; error: string | null }`
  - `rolesInGame(state): Set<string>`, `nightSteps(state): NightStep[]`, `nextStepId(state): string | undefined`
  - `aliveCounts(state): { alive: number; wolves: number; others: number }`
  - `sanitizeState(raw: unknown): CadernetaState | null`
- `Action` (união exata):
  `{type:'load', state}` · `{type:'reset'}` · `{type:'setNames', names: string[]}` · `{type:'deal', roles: string[], drunkHiddenRole: string | null}` · `{type:'nextDeal'}` · `{type:'cancel'}` · `{type:'setAlive', id, alive: boolean}` · `{type:'toggleTag', id, tag: Tag}` · `{type:'setNote', id, note: string}` · `{type:'setRole', id, role: string}` · `{type:'toggleStep', step: string}` · `{type:'toNight'}` · `{type:'toDay'}` · `{type:'addStrike', id}` · `{type:'removeStrike', id}` · `{type:'end'}`

- [ ] **Step 1: Escrever os testes que falham**

`src/lib/caderneta/state.test.ts`:

```ts
import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  addName,
  aliveCounts,
  drawRoles,
  initialState,
  nextStepId,
  nightSteps,
  pickDrunkRole,
  reducer,
  sanitizeState,
  type CadernetaState,
} from './state.ts'
import { emptyCounts, rolesFromCounts } from '../scenario.ts'

/** Builds a state already in `play` with the given roles (names P0, P1, ...). */
function played(roles: string[]): CadernetaState {
  let s = initialState()
  s = reducer(s, { type: 'setNames', names: roles.map((_, i) => `P${i}`) })
  s = reducer(s, { type: 'deal', roles, drunkHiddenRole: null })
  for (let i = 0; i < roles.length; i++) s = reducer(s, { type: 'nextDeal' })
  return s
}

const SIX = ['werewolf', 'seer', 'villager', 'villager', 'villager', 'villager']

test('drawRoles usa cada carta exatamente uma vez e é determinístico com rng fixo', () => {
  const counts = { ...emptyCounts(), werewolf: 1, seer: 1, villager: 4 }
  const seq = () => {
    let n = 0
    return () => ((n = (n * 7 + 3) % 11) / 11)
  }
  const a = drawRoles(counts, seq())
  const b = drawRoles(counts, seq())
  assert.deepEqual(a, b)
  assert.deepEqual([...a].sort(), [...rolesFromCounts(counts)].sort())
})

test('pickDrunkRole: sem bêbado é null, escolha explícita vale, sorteio vem da lista', () => {
  assert.equal(pickDrunkRole(false, 'random'), null)
  assert.equal(pickDrunkRole(true, 'hunter'), 'hunter')
  assert.equal(pickDrunkRole(true, 'random', () => 0), 'villager')
})

test('addName: apara, rejeita vazio, duplicado, longo e excesso', () => {
  assert.deepEqual(addName([], '  Ana  '), { names: ['Ana'], error: null })
  assert.equal(addName(['Ana'], '   ').error, 'Digite um nome')
  assert.equal(addName(['Ana'], 'ana').error, 'Esse nome já está na lista')
  assert.match(addName([], 'x'.repeat(31)).error ?? '', /Máximo de 30/)
  const full = Array.from({ length: 77 }, (_, i) => `N${i}`)
  assert.match(addName(full, 'Extra').error ?? '', /Máximo de 77/)
})

test('fluxo setup -> deal -> play', () => {
  let s = initialState()
  s = reducer(s, { type: 'setNames', names: ['A', 'B', 'C', 'D', 'E', 'F'] })
  const wrong = reducer(s, { type: 'deal', roles: ['seer'], drunkHiddenRole: null })
  assert.equal(wrong.phase, 'setup')
  s = reducer(s, { type: 'deal', roles: SIX, drunkHiddenRole: null })
  assert.equal(s.phase, 'deal')
  assert.equal(s.players[0].role, 'werewolf')
  for (let i = 0; i < 5; i++) s = reducer(s, { type: 'nextDeal' })
  assert.equal(s.phase, 'deal')
  assert.equal(s.dealIndex, 5)
  s = reducer(s, { type: 'nextDeal' })
  assert.equal(s.phase, 'play')
  assert.equal(s.turn, 1)
  assert.equal(s.view, 'night')
})

test('cancel volta ao setup preservando os nomes', () => {
  const s = reducer(played(SIX), { type: 'cancel' })
  assert.equal(s.phase, 'setup')
  assert.equal(s.names.length, 6)
  assert.equal(s.players.length, 0)
})

test('toDay / toNight: noite seguinte soma turn e limpa passos', () => {
  let s = played(SIX)
  s = reducer(s, { type: 'toggleStep', step: 'seer' })
  assert.deepEqual(s.doneSteps, ['seer'])
  s = reducer(s, { type: 'toDay' })
  assert.equal(s.view, 'day')
  assert.equal(s.turn, 1)
  s = reducer(s, { type: 'toNight' })
  assert.equal(s.view, 'night')
  assert.equal(s.turn, 2)
  assert.deepEqual(s.doneSteps, [])
})

test('strikes ficam entre 0 e 3', () => {
  let s = played(SIX)
  for (let i = 0; i < 5; i++) s = reducer(s, { type: 'addStrike', id: 'p0' })
  assert.equal(s.players[0].strikes, 3)
  for (let i = 0; i < 5; i++) s = reducer(s, { type: 'removeStrike', id: 'p0' })
  assert.equal(s.players[0].strikes, 0)
})

test('setRole ignora papel inválido; toggleTag liga e desliga; nota é cortada', () => {
  let s = played(SIX)
  s = reducer(s, { type: 'setRole', id: 'p2', role: 'nao_existe' })
  assert.equal(s.players[2].role, 'villager')
  s = reducer(s, { type: 'setRole', id: 'p2', role: 'witch' })
  assert.equal(s.players[2].role, 'witch')
  s = reducer(s, { type: 'toggleTag', id: 'p1', tag: 'pox' })
  assert.deepEqual(s.players[1].tags, ['pox'])
  s = reducer(s, { type: 'toggleTag', id: 'p1', tag: 'pox' })
  assert.deepEqual(s.players[1].tags, [])
  s = reducer(s, { type: 'setNote', id: 'p1', note: 'x'.repeat(200) })
  assert.equal(s.players[1].note.length, 140)
})

test('passos da noite: noite 1 tem Maçom/Cupido e não tem Bruxa; noite 2 inverte', () => {
  const roles = ['mason', 'cupid', 'witch', 'werewolf', 'seer', 'villager']
  let s = played(roles)
  const ids1 = nightSteps(s).map((x) => x.id)
  assert.deepEqual(ids1, ['masons', 'cupid', 'wolves', 'seer'])
  s = reducer(reducer(s, { type: 'toDay' }), { type: 'toNight' })
  const ids2 = nightSteps(s).map((x) => x.id)
  assert.deepEqual(ids2, ['wolves', 'witch', 'seer'])
})

test('passo do Bêbado só aparece na 3ª noite', () => {
  let s = played(['drunk', 'werewolf', 'seer', 'villager', 'villager', 'villager'])
  for (let n = 1; n < 3; n++) s = reducer(reducer(s, { type: 'toDay' }), { type: 'toNight' })
  assert.equal(s.turn, 3)
  assert.equal(nightSteps(s)[0].id, 'drunk')
})

test('nextStepId segue a ordem e pula os feitos', () => {
  let s = played(['mason', 'cupid', 'witch', 'werewolf', 'seer', 'villager'])
  assert.equal(nextStepId(s), 'masons')
  s = reducer(s, { type: 'toggleStep', step: 'masons' })
  assert.equal(nextStepId(s), 'cupid')
  for (const step of ['cupid', 'wolves', 'seer']) s = reducer(s, { type: 'toggleStep', step })
  assert.equal(nextStepId(s), undefined)
})

test('aliveCounts separa lobos dos demais', () => {
  let s = played(['werewolf', 'werewolf', 'seer', 'villager', 'villager', 'villager'])
  assert.deepEqual(aliveCounts(s), { alive: 6, wolves: 2, others: 4 })
  s = reducer(s, { type: 'setAlive', id: 'p0', alive: false })
  assert.deepEqual(aliveCounts(s), { alive: 5, wolves: 1, others: 4 })
})

test('sanitizeState: ida e volta por JSON e rejeição de lixo', () => {
  const s = played(SIX)
  assert.deepEqual(sanitizeState(JSON.parse(JSON.stringify(s))), s)
  assert.equal(sanitizeState(null), null)
  assert.equal(sanitizeState({ ...s, v: 2 }), null)
  assert.equal(sanitizeState({ ...s, phase: 'xyz' }), null)
  assert.equal(
    sanitizeState({ ...s, players: [{ ...s.players[0], role: 'nao_existe' }, ...s.players.slice(1)] }),
    null,
  )
  assert.equal(sanitizeState({ ...s, phase: 'deal', dealIndex: 99 }), null)
})
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `npm test`
Expected: FAIL com `Cannot find module './state.ts'`.

- [ ] **Step 3: Implementar `state.ts`**

`src/lib/caderneta/state.ts`:

```ts
// Caderneta do Mestre: pure state + reducer. No React, no Supabase.
// Relative `.ts` imports on purpose: this file is run directly by `node --test`.
import { CARD_CATALOG, DRUNK_ALLOWED } from '../cards.ts'
import { NIGHT_STEPS, stepIsAvailable, type NightStep } from '../night-steps.ts'
import { MAX_PLAYERS, rolesFromCounts, type ScenarioCounts } from '../scenario.ts'

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
}

export type Action =
  | { type: 'load'; state: CadernetaState }
  | { type: 'reset' }
  | { type: 'setNames'; names: string[] }
  | { type: 'deal'; roles: string[]; drunkHiddenRole: string | null }
  | { type: 'nextDeal' }
  | { type: 'cancel' }
  | { type: 'setAlive'; id: string; alive: boolean }
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
    case 'setAlive':
      return mapPlayer(state, action.id, (p) => ({ ...p, alive: action.alive }))
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
        ? { ...state, view: 'night', turn: state.turn + 1, doneSteps: [] }
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

export function aliveCounts(state: CadernetaState): { alive: number; wolves: number; others: number } {
  const team = new Map(CARD_CATALOG.map((c) => [c.id, c.team]))
  let alive = 0
  let wolves = 0
  for (const p of state.players) {
    if (!p.alive) continue
    alive++
    if (team.get(p.role) === 'wolf') wolves++
  }
  return { alive, wolves, others: alive - wolves }
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
  }
}
```

- [ ] **Step 4: Rodar e ver passar**

Run: `npm test`
Expected: PASS (testes de `scenario` e de `state`). Rodar `npx tsc --noEmit`; esperar sem erros novos.

- [ ] **Step 5: Commit**

```bash
git add src/lib/caderneta
git commit -m "feat: caderneta state module (reducer, draw, selectors) with tests"
```

---

### Task 3: `ScenarioCardPicker` com termômetro fixo + refactor do `ScenarioBuilder`

**Files:**
- Create: `src/hooks/use-scenario-counts.ts`
- Create: `src/components/scenario-card-picker.tsx`
- Modify: `src/components/scenario-builder.tsx` (reescrever)

**Interfaces:**
- Consumes: `ScenarioCounts`, `emptyCounts`, `countCards`, `totalPoints`, `balanceOf`, `isValidScenario`, `rolesFromCounts`, `MIN_PLAYERS`, `MAX_PLAYERS` de `@/lib/scenario`; `CARD_CATALOG`, `DRUNK_ALLOWED`, `type CardDefinition` de `@/lib/cards`.
- Produces:
  - `useScenarioCounts(): readonly [ScenarioCounts, Dispatch<SetStateAction<ScenarioCounts>>]`
  - `<ScenarioCardPicker playerCount counts onChange drunkHidden onDrunkHiddenChange />`

- [ ] **Step 1: Criar o hook de contagens**

`src/hooks/use-scenario-counts.ts`:

```ts
'use client'

import { useEffect, useState } from 'react'
import { emptyCounts, type ScenarioCounts } from '@/lib/scenario'

// Same key the online builder has always used, so the last scenario is shared by both modes.
const STORAGE_KEY = 'lobinho_last_scenario'

export function useScenarioCounts() {
  const [counts, setCounts] = useState<ScenarioCounts>(emptyCounts)
  const [hydrated, setHydrated] = useState(false)

  // Read after mount (not in the initializer) so server and client render the same first frame.
  useEffect(() => {
    try {
      const saved = localStorage.getItem(STORAGE_KEY)
      if (saved) setCounts({ ...emptyCounts(), ...JSON.parse(saved) })
    } catch {}
    setHydrated(true)
  }, [])

  useEffect(() => {
    if (!hydrated) return
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(counts))
    } catch {}
  }, [counts, hydrated])

  return [counts, setCounts] as const
}
```

- [ ] **Step 2: Criar o picker com o termômetro `sticky`**

`src/components/scenario-card-picker.tsx`:

```tsx
'use client'

import { useState } from 'react'
import { CARD_CATALOG, DRUNK_ALLOWED, type CardDefinition } from '@/lib/cards'
import { RoleInfoModal } from '@/components/role-info-modal'
import {
  MAX_PLAYERS,
  MIN_PLAYERS,
  balanceOf,
  countCards,
  emptyCounts,
  isValidScenario,
  totalPoints,
  type ScenarioCounts,
} from '@/lib/scenario'

interface ScenarioCardPickerProps {
  playerCount: number
  counts: ScenarioCounts
  onChange: (counts: ScenarioCounts) => void
  drunkHidden: string
  onDrunkHiddenChange: (value: string) => void
}

const BALANCE_VIEW = {
  wolves: { label: '🐺 Vantagem dos Lobos', text: 'text-red-400', bar: 'bg-red-500' },
  balanced: { label: '⚖️ Equilibrado', text: 'text-yellow-400', bar: 'bg-yellow-500' },
  village: { label: '🌿 Vantagem da Aldeia', text: 'text-emerald-400', bar: 'bg-emerald-500' },
} as const

const GROUPS = [
  { key: 'village', label: '🌿 Time da Vila', color: 'text-emerald-500' },
  { key: 'wolf', label: '🐺 Time dos Lobos', color: 'text-red-500' },
  { key: 'independent', label: '⚖️ Independentes', color: 'text-purple-500' },
] as const

export function ScenarioCardPicker({
  playerCount,
  counts,
  onChange,
  drunkHidden,
  onDrunkHiddenChange,
}: ScenarioCardPickerProps) {
  const [modalCard, setModalCard] = useState<CardDefinition | null>(null)

  const totalCards = countCards(counts)
  const points = totalPoints(counts)
  const isValid = isValidScenario(counts, playerCount)
  const view = BALANCE_VIEW[balanceOf(points)]
  const maxBar = playerCount * Math.max(...CARD_CATALOG.map((c) => Math.abs(c.points)))
  const barPercent = maxBar > 0 ? Math.min(100, Math.abs(points) / (maxBar / 50)) : 0

  function setCount(id: string, delta: number) {
    onChange({ ...counts, [id]: Math.max(0, (counts[id] ?? 0) + delta) })
  }

  return (
    <div className="space-y-4">
      {(counts.drunk ?? 0) > 0 && (
        <div className="rounded-xl border border-amber-900/40 bg-amber-950/10 px-4 py-3 space-y-2">
          <p className="text-amber-500 text-[10px] uppercase tracking-widest font-bold">
            🍺 Papel oculto do Bêbado (carta reserva)
          </p>
          <select
            value={drunkHidden}
            onChange={(e) => onDrunkHiddenChange(e.target.value)}
            className="w-full bg-neutral-900 border border-neutral-800 rounded-lg px-3 py-2 text-sm text-neutral-300"
          >
            <option value="random">🎲 Sortear</option>
            {CARD_CATALOG.filter((c) => DRUNK_ALLOWED.includes(c.id)).map((c) => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </select>
          <p className="text-neutral-600 text-[10px] leading-tight">
            Não conta como jogador. Ele vira esse papel na 3ª noite; a Vidente já vê esse papel antes.
          </p>
        </div>
      )}

      {/* Termômetro: fica fixo no topo enquanto a lista de cartas rola. */}
      <div className="sticky top-[env(safe-area-inset-top,0px)] z-10 bg-midnight pt-1 pb-2">
        <div className="rounded-xl border border-neutral-800 bg-neutral-900 px-4 py-3 space-y-1.5">
          <p className={`text-xs font-bold tracking-wider uppercase ${view.text}`}>{view.label}</p>
          <div className="flex items-center gap-2">
            <div className="flex-1 h-1.5 rounded-full bg-neutral-800 overflow-hidden flex">
              <div
                className={`h-full rounded-full transition-all duration-300 ${view.bar} ${points < 0 ? 'ml-auto' : ''}`}
                style={{ width: `${barPercent}%` }}
              />
            </div>
            <span className="text-neutral-500 text-xs font-mono min-w-[4ch] text-right">{points}</span>
          </div>
        </div>
      </div>

      <button
        type="button"
        onClick={() => onChange(emptyCounts())}
        className="w-full rounded-xl border border-neutral-800 bg-neutral-900/60 px-4 py-3 text-sm text-neutral-400 hover:text-neutral-200 hover:border-neutral-700 transition-all cursor-pointer text-center"
      >
        ↺ Resetar Cenário
      </button>

      {GROUPS.map((group) => {
        const cards = CARD_CATALOG.filter((c) => c.team === group.key)
        if (cards.length === 0) return null
        return (
          <div key={group.key}>
            <div className={`px-1 py-2 text-xs font-bold tracking-wider uppercase ${group.color}`}>
              {group.label}
            </div>
            <div className="space-y-2">
              {cards.map((card) => {
                const count = counts[card.id] ?? 0
                return (
                  <div
                    key={card.id}
                    className="flex items-center gap-3 px-4 py-2.5 rounded-xl border border-neutral-800 bg-neutral-900/50"
                  >
                    <span className="flex-1 text-sm font-medium text-neutral-300 truncate flex items-center gap-2">
                      {card.name}
                      <span
                        className={`text-xs font-mono ${
                          card.points > 0 ? 'text-emerald-500' : card.points < 0 ? 'text-red-500' : 'text-yellow-500'
                        }`}
                      >
                        [{card.points > 0 ? '+' : ''}{card.points}]
                      </span>
                    </span>

                    <button
                      type="button"
                      onClick={() => setModalCard(card)}
                      aria-label={`Sobre ${card.name}`}
                      className="text-neutral-600 hover:text-neutral-400 text-xs transition-colors cursor-pointer"
                    >
                      ⓘ
                    </button>

                    <div className="flex items-center gap-1.5">
                      <button
                        type="button"
                        onClick={() => setCount(card.id, -1)}
                        disabled={count === 0}
                        aria-label={`Menos ${card.name}`}
                        className="w-6 h-6 rounded-md bg-neutral-800 text-neutral-400 hover:bg-neutral-700 hover:text-neutral-200 disabled:opacity-30 disabled:cursor-not-allowed text-sm font-bold transition-all cursor-pointer flex items-center justify-center"
                      >
                        −
                      </button>
                      <span className="w-6 text-center text-sm font-mono text-neutral-200">{count}</span>
                      <button
                        type="button"
                        onClick={() => setCount(card.id, 1)}
                        aria-label={`Mais ${card.name}`}
                        className="w-6 h-6 rounded-md bg-neutral-800 text-neutral-400 hover:bg-neutral-700 hover:text-neutral-200 text-sm font-bold transition-all cursor-pointer flex items-center justify-center"
                      >
                        +
                      </button>
                    </div>
                  </div>
                )
              })}
            </div>
          </div>
        )
      })}

      <div className="flex items-center justify-between px-1">
        <p className={`text-xs font-mono ${isValid ? 'text-emerald-500' : 'text-neutral-600'}`}>
          Cartas: {totalCards}/{playerCount} {isValid ? '✅' : ''}
        </p>
        {playerCount < MIN_PLAYERS && <p className="text-red-500 text-[10px]">Mínimo {MIN_PLAYERS} jogadores</p>}
        {playerCount > MAX_PLAYERS && <p className="text-red-500 text-[10px]">Máximo {MAX_PLAYERS} jogadores</p>}
      </div>

      <RoleInfoModal open={modalCard !== null} onClose={() => setModalCard(null)} card={modalCard} />
    </div>
  )
}
```

- [ ] **Step 3: Reescrever `ScenarioBuilder` usando o picker (comportamento online idêntico)**

Substituir o arquivo `src/components/scenario-builder.tsx` inteiro por:

```tsx
'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { CARD_CATALOG, DRUNK_ALLOWED } from '@/lib/cards'
import { ScenarioCardPicker } from '@/components/scenario-card-picker'
import { useScenarioCounts } from '@/hooks/use-scenario-counts'
import { isValidScenario, rolesFromCounts } from '@/lib/scenario'
import type { RevealMode } from '@/lib/reveal'

interface ScenarioBuilderProps {
  roomId: string
  playerCount: number
}

export function ScenarioBuilder({ roomId, playerCount }: ScenarioBuilderProps) {
  const [counts, setCounts] = useScenarioCounts()
  const [revealMode, setRevealMode] = useState<RevealMode>('team')
  const [drunkHidden, setDrunkHidden] = useState('random')
  const [ghostVariant, setGhostVariant] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const supabase = createClient()

  const isValid = isValidScenario(counts, playerCount)

  async function handleStart() {
    if (!isValid) return
    setBusy(true)
    setError('')

    const roles = rolesFromCounts(counts)

    const hiddenRole =
      (counts.drunk ?? 0) > 0
        ? drunkHidden === 'random'
          ? DRUNK_ALLOWED[Math.floor(Math.random() * DRUNK_ALLOWED.length)]
          : drunkHidden
        : null

    const { error: revealError } = await supabase
      .from('rooms')
      .update({
        reveal_mode: revealMode,
        drunk_hidden_role: hiddenRole,
        ghost_enabled: ghostVariant && (counts.ghost ?? 0) === 0,
      })
      .eq('id', roomId)
    if (revealError) {
      setError(revealError.message)
      setBusy(false)
      return
    }

    const { error: e } = await supabase.rpc('start_game', {
      p_room_id: roomId,
      p_roles: roles,
    })
    if (e) {
      setError(e.message)
      setBusy(false)
    }
  }

  return (
    <div className="w-full max-w-sm mx-auto mt-6 space-y-4">
      {/* Header */}
      <div className="flex items-center gap-2">
        <h2 className="text-neutral-400 text-xs uppercase tracking-widest">
          Construir Cenário
        </h2>
        <span className="flex-1 h-px bg-neutral-800" />
      </div>

      {/* Configurações da Partida */}
      <div className="rounded-xl border border-neutral-800 bg-neutral-900/60 px-4 py-3 space-y-2">
        <p className="text-neutral-500 text-[10px] uppercase tracking-widest font-bold">
          Configurações da Partida
        </p>
        <div className="space-y-1.5">
          {[
            { value: 'total' as const, label: '🃏 Revelação Total', desc: 'Todos os papéis são revelados exatamente como são.' },
            { value: 'team' as const, label: '👥 Apenas Time Vila', desc: 'Mostra se a vítima era da Vila ou não.' },
            { value: 'hidden' as const, label: '❓ Identidade Oculta', desc: 'Nenhuma informação sobre a identidade é revelada.' },
          ].map((opt) => (
            <label
              key={opt.value}
              className={`flex items-start gap-3 px-3 py-2 rounded-lg cursor-pointer transition-colors ${
                revealMode === opt.value
                  ? 'bg-red-900/20 border border-red-800/40'
                  : 'bg-neutral-900/40 border border-transparent hover:bg-neutral-800/40'
              }`}
            >
              <input
                type="radio"
                name="revealMode"
                value={opt.value}
                checked={revealMode === opt.value}
                onChange={() => setRevealMode(opt.value)}
                className="mt-0.5 accent-red-600 cursor-pointer"
              />
              <div className="flex flex-col">
                <span className="text-neutral-300 text-sm font-medium">{opt.label}</span>
                <span className="text-neutral-600 text-[10px] leading-tight">{opt.desc}</span>
              </div>
            </label>
          ))}
        </div>
      </div>

      <label className="flex items-start gap-3 rounded-xl border border-neutral-800 bg-neutral-900/60 px-4 py-3 cursor-pointer">
        <input
          type="checkbox"
          checked={ghostVariant && (counts.ghost ?? 0) === 0}
          disabled={(counts.ghost ?? 0) > 0}
          onChange={(e) => setGhostVariant(e.target.checked)}
          className="mt-0.5 accent-red-600 cursor-pointer"
        />
        <div className="flex flex-col">
          <span className="text-neutral-300 text-sm font-medium">👻 Variante Fantasma</span>
          <span className="text-neutral-600 text-[10px] leading-tight">
            {(counts.ghost ?? 0) > 0
              ? 'A carta do Fantasma está no cenário (ela tem prioridade).'
              : 'O primeiro jogador a morrer vira Fantasma: mantém o time e escreve uma letra por dia.'}
          </span>
        </div>
      </label>

      <ScenarioCardPicker
        playerCount={playerCount}
        counts={counts}
        onChange={setCounts}
        drunkHidden={drunkHidden}
        onDrunkHiddenChange={setDrunkHidden}
      />

      {/* Botão Iniciar */}
      <button
        onClick={handleStart}
        disabled={!isValid || busy}
        className="w-full py-4 rounded-2xl font-bold text-lg tracking-wider bg-red-700 text-white hover:bg-red-600 active:bg-red-800 disabled:opacity-40 disabled:cursor-not-allowed shadow-lg shadow-red-900/40 transition-all duration-200 cursor-pointer disabled:animate-none"
      >
        {busy ? 'Iniciando...' : 'Iniciar Jogo'}
      </button>

      {error && (
        <p className="text-red-500 text-xs text-center">{error}</p>
      )}
    </div>
  )
}
```

Observação: `CARD_CATALOG` não é mais usado em `scenario-builder.tsx`; remover do import se o lint reclamar (o bloco acima já não o importa).

- [ ] **Step 4: Verificar tipos e lint dos arquivos tocados**

Run: `npx tsc --noEmit && npx eslint src/components/scenario-builder.tsx src/components/scenario-card-picker.tsx src/hooks/use-scenario-counts.ts`
Expected: sem erros de tipo. Se o ESLint apontar `react-hooks/set-state-in-effect` no hook, manter o padrão (é leitura de `localStorage` após montar, necessária contra mismatch de hidratação) e acrescentar `// eslint-disable-next-line react-hooks/set-state-in-effect -- reads localStorage after mount to keep SSR and client first frame identical` na linha do `setCounts`/`setHydrated`.

- [ ] **Step 5: Verificação manual do sticky (online)**

Run: `npm run dev`, abrir a página de lobby de uma sala (como host, com ≥6 jogadores não é necessário: o construtor aparece para o host), rolar a lista de cartas.
Expected: o termômetro (Equilibrado/Vantagem…) permanece colado no topo durante a rolagem, com fundo opaco e as cartas passando por baixo. Se não colar, procurar ancestral com `overflow` em `src/app/lobby/[id]/page.tsx` e corrigir (preferir remover o `overflow` a trocar a estratégia).

- [ ] **Step 6: Commit**

```bash
git add src/hooks/use-scenario-counts.ts src/components/scenario-card-picker.tsx src/components/scenario-builder.tsx
git commit -m "feat: sticky balance bar via shared ScenarioCardPicker"
```

---

### Task 4: Hook de persistência, tela de montagem, tela de entrega e rota

**Files:**
- Create: `src/hooks/use-caderneta.ts`
- Create: `src/components/caderneta/setup-screen.tsx`
- Create: `src/components/caderneta/deal-screen.tsx`
- Create: `src/app/caderneta/page.tsx`

**Interfaces:**
- Consumes: tudo de `@/lib/caderneta/state` (Task 2), `useScenarioCounts`, `ScenarioCardPicker` (Task 3).
- Produces:
  - `useCaderneta(): { state: CadernetaState; dispatch: Dispatch<Action>; hydrated: boolean }`
  - `<SetupScreen state dispatch />`
  - `<DealScreen player isLast onNext />`

- [ ] **Step 1: Hook de persistência da partida**

`src/hooks/use-caderneta.ts`:

```ts
'use client'

import { useEffect, useReducer, useState } from 'react'
import { initialState, reducer, sanitizeState } from '@/lib/caderneta/state'

const STORAGE_KEY = 'lobinho:caderneta:v1'

export function useCaderneta() {
  const [state, dispatch] = useReducer(reducer, undefined, initialState)
  const [hydrated, setHydrated] = useState(false)

  useEffect(() => {
    try {
      const raw = localStorage.getItem(STORAGE_KEY)
      if (raw) {
        const saved = sanitizeState(JSON.parse(raw))
        if (saved) dispatch({ type: 'load', state: saved })
      }
    } catch {}
    setHydrated(true)
  }, [])

  useEffect(() => {
    if (!hydrated) return
    try {
      const blank = state.phase === 'setup' && state.names.length === 0
      if (blank) localStorage.removeItem(STORAGE_KEY)
      else localStorage.setItem(STORAGE_KEY, JSON.stringify(state))
    } catch {}
  }, [state, hydrated])

  return { state, dispatch, hydrated }
}
```

- [ ] **Step 2: Tela de montagem**

`src/components/caderneta/setup-screen.tsx`:

```tsx
'use client'

import { useState, type Dispatch, type FormEvent } from 'react'
import { CARD_CATALOG } from '@/lib/cards'
import { ScenarioCardPicker } from '@/components/scenario-card-picker'
import { useScenarioCounts } from '@/hooks/use-scenario-counts'
import { isValidScenario } from '@/lib/scenario'
import {
  NAME_MAX,
  addName,
  drawRoles,
  pickDrunkRole,
  type Action,
  type CadernetaState,
} from '@/lib/caderneta/state'

interface SetupScreenProps {
  state: CadernetaState
  dispatch: Dispatch<Action>
}

export function SetupScreen({ state, dispatch }: SetupScreenProps) {
  const [counts, setCounts] = useScenarioCounts()
  const [drunkHidden, setDrunkHidden] = useState('random')
  const [nameInput, setNameInput] = useState('')
  const [error, setError] = useState('')

  const playerCount = state.names.length
  const valid = isValidScenario(counts, playerCount)
  const wolfCards = CARD_CATALOG.filter((c) => c.team === 'wolf').reduce(
    (sum, c) => sum + (counts[c.id] ?? 0),
    0,
  )
  const warnings: string[] = []
  if (wolfCards === 0) warnings.push('Sem lobos no cenário.')
  if ((counts.seer ?? 0) === 0) warnings.push('Sem Vidente no cenário.')

  function handleAdd(e: FormEvent) {
    e.preventDefault()
    const result = addName(state.names, nameInput)
    if (result.error) {
      setError(result.error)
      return
    }
    setError('')
    setNameInput('')
    dispatch({ type: 'setNames', names: result.names })
  }

  function handleRemove(name: string) {
    dispatch({ type: 'setNames', names: state.names.filter((n) => n !== name) })
  }

  function handleDeal() {
    if (!valid) return
    dispatch({
      type: 'deal',
      roles: drawRoles(counts),
      drunkHiddenRole: pickDrunkRole((counts.drunk ?? 0) > 0, drunkHidden),
    })
  }

  return (
    <div className="space-y-6">
      <header className="text-center space-y-1">
        <h1 className="font-display text-4xl tracking-widest text-red-600">CADERNETA DO MESTRE</h1>
        <p className="text-neutral-500 text-xs">
          Digite os jogadores, escolha as cartas e passe o celular de mão em mão.
        </p>
      </header>

      <section className="space-y-3">
        <h2 className="text-neutral-400 text-xs uppercase tracking-widest">Jogadores ({playerCount})</h2>
        <form onSubmit={handleAdd} className="flex gap-2">
          <input
            type="text"
            value={nameInput}
            maxLength={NAME_MAX}
            onChange={(e) => {
              setNameInput(e.target.value)
              setError('')
            }}
            placeholder="Nome do jogador"
            className="flex-1 px-4 py-3 rounded-xl text-sm bg-neutral-900 border border-neutral-800 text-neutral-200 placeholder-neutral-600 focus:outline-none focus:ring-2 focus:ring-red-700 focus:border-red-800 transition-all"
          />
          <button
            type="submit"
            className="px-4 rounded-xl font-bold text-sm bg-primary hover:bg-primary-hover active:bg-primary-active text-white cursor-pointer transition-all"
          >
            Adicionar
          </button>
        </form>
        {error && <p className="text-red-500 text-xs">{error}</p>}
        {state.names.length > 0 && (
          <ul className="flex flex-wrap gap-2">
            {state.names.map((name) => (
              <li
                key={name}
                className="flex items-center gap-2 pl-3 pr-1 py-1 rounded-full border border-neutral-800 bg-neutral-900/60 text-sm text-neutral-300"
              >
                {name}
                <button
                  type="button"
                  onClick={() => handleRemove(name)}
                  aria-label={`Remover ${name}`}
                  className="w-6 h-6 rounded-full text-neutral-500 hover:text-neutral-200 hover:bg-neutral-800 cursor-pointer"
                >
                  ×
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="space-y-3">
        <h2 className="text-neutral-400 text-xs uppercase tracking-widest">Cenário</h2>
        <ScenarioCardPicker
          playerCount={playerCount}
          counts={counts}
          onChange={setCounts}
          drunkHidden={drunkHidden}
          onDrunkHiddenChange={setDrunkHidden}
        />
      </section>

      {warnings.length > 0 && (
        <p className="text-amber-500 text-xs text-center">{warnings.join(' ')} Dá para jogar assim mesmo.</p>
      )}

      <button
        type="button"
        onClick={handleDeal}
        disabled={!valid}
        className="w-full py-4 rounded-2xl font-bold text-lg tracking-wider bg-red-700 text-white hover:bg-red-600 active:bg-red-800 disabled:opacity-40 disabled:cursor-not-allowed shadow-lg shadow-red-900/40 transition-all duration-200 cursor-pointer"
      >
        Sortear e entregar cartas
      </button>
    </div>
  )
}
```

- [ ] **Step 3: Tela de entrega das cartas**

`src/components/caderneta/deal-screen.tsx`:

```tsx
'use client'

import { useEffect, useState } from 'react'
import Image from 'next/image'
import { CARD_CATALOG, ROLE_LABEL, ROLE_STYLE } from '@/lib/cards'
import type { CadernetaPlayer } from '@/lib/caderneta/state'

interface DealScreenProps {
  player: CadernetaPlayer
  isLast: boolean
  onNext: () => void
}

type Step = 'handoff' | 'view' | 'return'

// Render with `key={dealIndex}` so each player starts from the neutral hand-off screen.
export function DealScreen({ player, isLast, onNext }: DealScreenProps) {
  const [step, setStep] = useState<Step>('handoff')
  const [holding, setHolding] = useState(false)
  const [seen, setSeen] = useState(false)
  const card = CARD_CATALOG.find((c) => c.id === player.role)

  // Never leave the card face up if the tab is hidden or loses focus.
  useEffect(() => {
    const hide = () => setHolding(false)
    document.addEventListener('visibilitychange', hide)
    window.addEventListener('blur', hide)
    return () => {
      document.removeEventListener('visibilitychange', hide)
      window.removeEventListener('blur', hide)
    }
  }, [])

  if (step === 'handoff') {
    return (
      <div className="min-h-[70dvh] flex flex-col items-center justify-center gap-8 text-center">
        <p className="text-neutral-500 text-xs uppercase tracking-widest">Passe o celular para</p>
        <p className="font-display text-6xl tracking-widest text-red-600 break-words max-w-full">{player.name}</p>
        <button
          type="button"
          onClick={() => setStep('view')}
          className="w-full max-w-xs py-4 rounded-2xl font-bold tracking-wider bg-primary hover:bg-primary-hover active:bg-primary-active text-white shadow-lg shadow-red-900/30 cursor-pointer transition-all"
        >
          Estou com o celular
        </button>
      </div>
    )
  }

  if (step === 'return') {
    return (
      <div className="min-h-[70dvh] flex flex-col items-center justify-center gap-8 text-center">
        <p className="font-display text-5xl tracking-widest text-red-600">ENTREGUE AO MESTRE</p>
        <p className="text-neutral-500 text-sm">Todos já viram a carta. Devolva o celular ao mestre.</p>
        <button
          type="button"
          onClick={onNext}
          className="w-full max-w-xs py-4 rounded-2xl font-bold tracking-wider bg-primary hover:bg-primary-hover active:bg-primary-active text-white shadow-lg shadow-red-900/30 cursor-pointer transition-all"
        >
          Sou o mestre
        </button>
      </div>
    )
  }

  return (
    <div className="min-h-[70dvh] flex flex-col items-center justify-center gap-6 text-center">
      <p className="text-neutral-400 text-sm">
        <span className="text-neutral-200 font-bold">{player.name}</span>, segure a carta para ver.
      </p>

      <div
        className="relative w-64 aspect-[7/10] rounded-2xl overflow-hidden border border-neutral-800 touch-none select-none [-webkit-touch-callout:none] cursor-pointer"
        onPointerDown={(e) => {
          try {
            e.currentTarget.setPointerCapture(e.pointerId)
          } catch {}
          setHolding(true)
          setSeen(true)
        }}
        onPointerUp={() => setHolding(false)}
        onPointerCancel={() => setHolding(false)}
        onLostPointerCapture={() => setHolding(false)}
        onContextMenu={(e) => e.preventDefault()}
      >
        {holding ? (
          <div className="absolute inset-0 bg-neutral-900 p-5 flex flex-col items-center justify-center gap-4">
            <span
              className={`px-3 py-1.5 rounded-lg border text-lg font-bold ${ROLE_STYLE[player.role] ?? 'bg-neutral-200 text-neutral-800 border-neutral-400'}`}
            >
              {ROLE_LABEL[player.role] ?? player.role}
            </span>
            <p className="text-neutral-300 text-sm leading-relaxed">{card?.description}</p>
          </div>
        ) : (
          <Image
            src="/verse-card.jpeg"
            alt=""
            fill
            sizes="256px"
            draggable={false}
            className="object-cover pointer-events-none select-none [-webkit-touch-callout:none]"
          />
        )}
      </div>

      {seen && !holding && (
        <button
          type="button"
          onClick={() => (isLast ? setStep('return') : onNext())}
          className="w-full max-w-xs py-3.5 rounded-2xl font-bold tracking-wider bg-primary hover:bg-primary-hover active:bg-primary-active text-white shadow-lg shadow-red-900/30 cursor-pointer transition-all"
        >
          {isLast ? 'Devolver ao mestre' : 'Próximo'}
        </button>
      )}
    </div>
  )
}
```

- [ ] **Step 4: Rota (por ora só montagem e entrega; painel entra na Task 5)**

`src/app/caderneta/page.tsx`:

```tsx
'use client'

import Link from 'next/link'
import { useCaderneta } from '@/hooks/use-caderneta'
import { SetupScreen } from '@/components/caderneta/setup-screen'
import { DealScreen } from '@/components/caderneta/deal-screen'

export default function CadernetaPage() {
  const { state, dispatch, hydrated } = useCaderneta()

  if (!hydrated) return <main className="min-h-dvh" />

  const dealing = state.phase === 'deal' ? state.players[state.dealIndex] : undefined

  return (
    <main className="mx-auto w-full max-w-sm min-h-dvh px-4 py-6">
      {state.phase === 'setup' && (
        <>
          <Link href="/" className="inline-block mb-4 text-neutral-500 hover:text-neutral-300 text-xs">
            ← Início
          </Link>
          <SetupScreen state={state} dispatch={dispatch} />
        </>
      )}
      {dealing && (
        <DealScreen
          key={state.dealIndex}
          player={dealing}
          isLast={state.dealIndex === state.players.length - 1}
          onNext={() => dispatch({ type: 'nextDeal' })}
        />
      )}
    </main>
  )
}
```

- [ ] **Step 5: Verificação manual**

Run: `npx tsc --noEmit`, depois `npm run dev` e abrir `http://localhost:3000/caderneta` no Chrome.
Expected: adicionar 6 nomes (duplicado e vazio são recusados); o botão "Sortear" só habilita com 6 cartas escolhidas; o termômetro fica fixo na rolagem; ao sortear aparece "Passe o celular para *Nome*"; "Estou com o celular" mostra o verso da carta; segurar mostra o papel e soltar esconde; "Próximo" só aparece depois de ver; o último passa por "Entregue ao mestre". Recarregar no meio da entrega volta à tela neutra do mesmo jogador.

- [ ] **Step 6: Commit**

```bash
git add src/hooks/use-caderneta.ts src/components/caderneta/setup-screen.tsx src/components/caderneta/deal-screen.tsx src/app/caderneta/page.tsx
git commit -m "feat: caderneta setup and card dealing screens"
```

---

### Task 5: Painel do mestre e tela final

**Files:**
- Create: `src/components/caderneta/players-list.tsx`
- Create: `src/components/caderneta/night-steps-list.tsx`
- Create: `src/components/caderneta/day-tools.tsx`
- Create: `src/components/caderneta/play-panel.tsx`
- Create: `src/components/caderneta/end-screen.tsx`
- Modify: `src/app/caderneta/page.tsx`

**Interfaces:**
- Consumes: `Action`, `CadernetaState`, `TAGS`, `MAX_STRIKES`, `NOTE_MAX`, `aliveCounts`, `nightSteps`, `nextStepId` de `@/lib/caderneta/state`; `VoteTimerPanel` de `@/components/vote-timer-panel`; `CARD_CATALOG`, `ROLE_LABEL`, `ROLE_STYLE`, `ROLE_TRANSLATION` de `@/lib/cards`.
- Produces: `<PlayPanel state dispatch />`, `<EndScreen state dispatch />`.

- [ ] **Step 1: Lista de jogadores**

`src/components/caderneta/players-list.tsx`:

```tsx
'use client'

import { useState, type Dispatch } from 'react'
import { CARD_CATALOG, ROLE_LABEL, ROLE_STYLE, ROLE_TRANSLATION } from '@/lib/cards'
import { NOTE_MAX, TAGS, type Action, type CadernetaState } from '@/lib/caderneta/state'

interface PlayersListProps {
  state: CadernetaState
  dispatch: Dispatch<Action>
}

export function PlayersList({ state, dispatch }: PlayersListProps) {
  const [openId, setOpenId] = useState<string | null>(null)

  return (
    <section className="space-y-2">
      <h2 className="text-neutral-400 text-xs uppercase tracking-widest">Jogadores</h2>
      {state.players.map((p) => {
        const open = openId === p.id
        const tagEmojis = TAGS.filter((t) => p.tags.includes(t.id)).map((t) => t.label.split(' ')[0])
        return (
          <div
            key={p.id}
            className={`rounded-xl border border-neutral-800 bg-neutral-900/50 ${p.alive ? '' : 'opacity-60'}`}
          >
            <div className="flex items-center gap-2 px-3 py-2.5">
              <button
                type="button"
                onClick={() => setOpenId(open ? null : p.id)}
                aria-expanded={open}
                className="flex-1 min-w-0 text-left cursor-pointer"
              >
                <span
                  className={`block truncate text-sm font-medium ${
                    p.alive ? 'text-neutral-200' : 'text-neutral-500 line-through'
                  }`}
                >
                  {p.name}
                </span>
                <span
                  className={`inline-block mt-1 px-2 py-0.5 rounded-md border text-[11px] font-medium ${
                    ROLE_STYLE[p.role] ?? ''
                  }`}
                >
                  {ROLE_LABEL[p.role] ?? p.role}
                </span>
                {tagEmojis.length > 0 && (
                  <span className="ml-2 text-[11px] text-neutral-500">{tagEmojis.join(' ')}</span>
                )}
                {p.note && <span className="block mt-1 truncate text-[11px] text-neutral-600">{p.note}</span>}
              </button>
              <button
                type="button"
                onClick={() => dispatch({ type: 'setAlive', id: p.id, alive: !p.alive })}
                className="shrink-0 px-3 py-1.5 rounded-lg text-xs font-bold bg-neutral-900 border border-neutral-800 text-neutral-400 hover:text-neutral-200 cursor-pointer transition-all"
              >
                {p.alive ? '💀 Matar' : '❤️ Reviver'}
              </button>
            </div>

            {open && (
              <div className="border-t border-neutral-800 px-3 py-3 space-y-3">
                <div className="flex flex-wrap gap-1.5">
                  {TAGS.map((t) => {
                    const on = p.tags.includes(t.id)
                    return (
                      <button
                        key={t.id}
                        type="button"
                        onClick={() => dispatch({ type: 'toggleTag', id: p.id, tag: t.id })}
                        aria-pressed={on}
                        className={`px-2.5 py-1 rounded-full border text-[11px] cursor-pointer transition-all ${
                          on
                            ? 'bg-red-900/30 border-red-800/60 text-red-300'
                            : 'bg-neutral-900 border-neutral-800 text-neutral-500 hover:text-neutral-300'
                        }`}
                      >
                        {t.label}
                      </button>
                    )
                  })}
                </div>

                <input
                  type="text"
                  value={p.note}
                  maxLength={NOTE_MAX}
                  onChange={(e) => dispatch({ type: 'setNote', id: p.id, note: e.target.value })}
                  placeholder="Nota (ex.: protegido pelo guarda-costas)"
                  className="w-full px-3 py-2 rounded-lg text-xs bg-neutral-900 border border-neutral-800 text-neutral-300 placeholder-neutral-600 focus:outline-none focus:border-red-800"
                />

                <label className="flex items-center gap-2 text-[11px] text-neutral-500">
                  Trocar papel
                  <select
                    value={p.role}
                    onChange={(e) => dispatch({ type: 'setRole', id: p.id, role: e.target.value })}
                    className="flex-1 bg-neutral-900 border border-neutral-800 rounded-lg px-2 py-1.5 text-xs text-neutral-300"
                  >
                    {CARD_CATALOG.map((c) => (
                      <option key={c.id} value={c.id}>
                        {ROLE_TRANSLATION[c.id] ?? c.name}
                      </option>
                    ))}
                  </select>
                </label>
              </div>
            )}
          </div>
        )
      })}
    </section>
  )
}
```

- [ ] **Step 2: Lista de despertar**

`src/components/caderneta/night-steps-list.tsx`:

```tsx
'use client'

import { useState, type Dispatch } from 'react'
import { ROLE_TRANSLATION } from '@/lib/cards'
import { nextStepId, nightSteps, type Action, type CadernetaState } from '@/lib/caderneta/state'

interface NightStepsListProps {
  state: CadernetaState
  dispatch: Dispatch<Action>
}

export function NightStepsList({ state, dispatch }: NightStepsListProps) {
  const [confirming, setConfirming] = useState(false)
  const steps = nightSteps(state)
  const next = nextStepId(state)
  const pending = steps.filter((s) => !state.doneSteps.includes(s.id)).length

  function handleDawn() {
    if (pending > 0 && !confirming) {
      setConfirming(true)
      return
    }
    setConfirming(false)
    dispatch({ type: 'toDay' })
  }

  function revealDrunk() {
    const hidden = state.drunkHiddenRole
    if (!hidden) return
    for (const p of state.players) {
      if (p.role === 'drunk') dispatch({ type: 'setRole', id: p.id, role: hidden })
    }
    dispatch({ type: 'toggleStep', step: 'drunk' })
  }

  return (
    <section className="space-y-3">
      <h2 className="text-neutral-400 text-xs uppercase tracking-widest">Ordem para acordar</h2>
      {steps.length === 0 ? (
        <p className="text-neutral-600 text-sm text-center py-3">Ninguém acorda nesta noite.</p>
      ) : (
        <ol className="space-y-2">
          {steps.map((step) => {
            const done = state.doneSteps.includes(step.id)
            const holders = state.players.filter((p) => step.roles.includes(p.role))
            const isNext = step.id === next
            return (
              <li
                key={step.id}
                className={`rounded-xl border px-4 py-3 space-y-2 ${
                  isNext
                    ? 'border-red-700 bg-red-950/20 animate-pulse'
                    : 'border-neutral-800 bg-neutral-900/50'
                } ${done ? 'opacity-50' : ''}`}
              >
                <div className="flex items-center gap-3">
                  <span className={`flex-1 text-sm font-medium ${done ? 'line-through text-neutral-500' : 'text-neutral-200'}`}>
                    {step.label}
                  </span>
                  <button
                    type="button"
                    onClick={() => dispatch({ type: 'toggleStep', step: step.id })}
                    className="px-3 py-1.5 rounded-lg text-xs font-bold bg-neutral-900 border border-neutral-800 text-green-400 hover:bg-green-900/30 cursor-pointer transition-all"
                  >
                    {done ? '↺ Desfazer' : '✓ Feito'}
                  </button>
                </div>
                <p className="text-[11px] text-neutral-500">
                  {holders.map((p) => (p.alive ? p.name : `${p.name} †`)).join(', ')}
                </p>
                {step.id === 'drunk' && state.drunkHiddenRole && (
                  <div className="flex items-center gap-2">
                    <span className="flex-1 text-[11px] text-amber-500">
                      Papel oculto: {ROLE_TRANSLATION[state.drunkHiddenRole] ?? state.drunkHiddenRole}
                    </span>
                    <button
                      type="button"
                      onClick={revealDrunk}
                      className="px-3 py-1.5 rounded-lg text-xs font-bold bg-amber-950/30 border border-amber-900/50 text-amber-400 cursor-pointer"
                    >
                      Revelar e trocar papel
                    </button>
                  </div>
                )}
              </li>
            )
          })}
        </ol>
      )}

      <button
        type="button"
        onClick={handleDawn}
        className="w-full py-3.5 rounded-2xl font-bold tracking-wider bg-primary hover:bg-primary-hover active:bg-primary-active text-white shadow-lg shadow-red-900/30 cursor-pointer transition-all"
      >
        {confirming ? `Faltam ${pending} passo(s). Amanhecer mesmo?` : '☀️ Amanhecer'}
      </button>
    </section>
  )
}
```

- [ ] **Step 3: Ferramentas do dia (cronômetro e strikes)**

`src/components/caderneta/day-tools.tsx`:

```tsx
'use client'

import { useState, type Dispatch } from 'react'
import { VoteTimerPanel } from '@/components/vote-timer-panel'
import { MAX_STRIKES, type Action, type CadernetaState } from '@/lib/caderneta/state'

interface DayToolsProps {
  state: CadernetaState
  dispatch: Dispatch<Action>
}

export function DayTools({ state, dispatch }: DayToolsProps) {
  const [pendingKill, setPendingKill] = useState<string | null>(null)
  const alive = state.players.filter((p) => p.alive)
  const target = state.players.find((p) => p.id === pendingKill)

  return (
    <section className="space-y-4">
      <VoteTimerPanel />

      <div className="space-y-2">
        <h2 className="text-neutral-400 text-xs uppercase tracking-widest">Strikes</h2>
        {alive.map((p) => (
          <div
            key={p.id}
            className="flex items-center gap-2 px-3 py-2 rounded-xl border border-neutral-800 bg-neutral-900/50"
          >
            <span className="flex-1 truncate text-sm text-neutral-300">{p.name}</span>
            <span className="text-xs font-mono text-neutral-500 w-10 text-center">
              {p.strikes}/{MAX_STRIKES}
            </span>
            <button
              type="button"
              onClick={() => dispatch({ type: 'removeStrike', id: p.id })}
              disabled={p.strikes === 0}
              aria-label={`Tirar strike de ${p.name}`}
              className="w-7 h-7 rounded-md bg-neutral-800 text-neutral-400 hover:bg-neutral-700 disabled:opacity-30 disabled:cursor-not-allowed font-bold cursor-pointer"
            >
              −
            </button>
            {p.strikes >= MAX_STRIKES ? (
              <button
                type="button"
                onClick={() => setPendingKill(p.id)}
                aria-label={`Eliminar ${p.name}`}
                className="w-7 h-7 rounded-md bg-red-900/40 text-red-300 hover:bg-red-900/60 font-bold cursor-pointer"
              >
                ☠️
              </button>
            ) : (
              <button
                type="button"
                onClick={() => {
                  dispatch({ type: 'addStrike', id: p.id })
                  if (p.strikes + 1 >= MAX_STRIKES) setPendingKill(p.id)
                }}
                aria-label={`Dar strike em ${p.name}`}
                className="w-7 h-7 rounded-md bg-neutral-800 text-neutral-400 hover:bg-neutral-700 font-bold cursor-pointer"
              >
                +
              </button>
            )}
          </div>
        ))}
      </div>

      {target && (
        <div className="rounded-xl border border-red-800 bg-red-950/30 px-4 py-3 space-y-3 text-center">
          <p className="text-sm text-neutral-200">
            Eliminar <span className="font-bold">{target.name}</span> com 3 strikes?
          </p>
          <div className="flex gap-3">
            <button
              type="button"
              onClick={() => {
                dispatch({ type: 'setAlive', id: target.id, alive: false })
                setPendingKill(null)
              }}
              className="flex-1 py-2.5 rounded-xl text-sm font-bold bg-red-700 text-white hover:bg-red-600 cursor-pointer"
            >
              Eliminar
            </button>
            <button
              type="button"
              onClick={() => setPendingKill(null)}
              className="flex-1 py-2.5 rounded-xl text-sm font-bold border border-neutral-700 text-neutral-300 hover:bg-neutral-800 cursor-pointer"
            >
              Manter
            </button>
          </div>
        </div>
      )}

      <button
        type="button"
        onClick={() => dispatch({ type: 'toNight' })}
        className="w-full py-3.5 rounded-2xl font-bold tracking-wider bg-primary hover:bg-primary-hover active:bg-primary-active text-white shadow-lg shadow-red-900/30 cursor-pointer transition-all"
      >
        🌙 Anoitecer
      </button>
    </section>
  )
}
```

- [ ] **Step 4: Painel e tela final**

`src/components/caderneta/play-panel.tsx`:

```tsx
'use client'

import { useState, type Dispatch } from 'react'
import { aliveCounts, type Action, type CadernetaState } from '@/lib/caderneta/state'
import { DayTools } from './day-tools'
import { NightStepsList } from './night-steps-list'
import { PlayersList } from './players-list'

interface PlayPanelProps {
  state: CadernetaState
  dispatch: Dispatch<Action>
}

export function PlayPanel({ state, dispatch }: PlayPanelProps) {
  const { alive, wolves, others } = aliveCounts(state)
  const [confirm, setConfirm] = useState<'end' | 'cancel' | null>(null)

  return (
    <div className="space-y-6">
      <header className="text-center space-y-1">
        <h1 className="font-display text-5xl tracking-widest text-red-600">
          {state.view === 'night' ? `NOITE ${state.turn}` : `DIA ${state.turn}`}
        </h1>
        <p className="text-neutral-500 text-xs">
          {alive} vivos · 🐺 {wolves} × {others} demais
        </p>
      </header>

      {state.view === 'night' ? (
        <NightStepsList key={state.turn} state={state} dispatch={dispatch} />
      ) : (
        <DayTools state={state} dispatch={dispatch} />
      )}

      <PlayersList state={state} dispatch={dispatch} />

      <footer className="space-y-2 pt-2 border-t border-neutral-800">
        {confirm ? (
          <div className="rounded-xl border border-neutral-700 px-4 py-3 space-y-3 text-center">
            <p className="text-sm text-neutral-300">
              {confirm === 'end'
                ? 'Encerrar a partida e revelar os papéis?'
                : 'Cancelar a partida e voltar à montagem? O sorteio atual se perde.'}
            </p>
            <div className="flex gap-3">
              <button
                type="button"
                onClick={() => {
                  dispatch({ type: confirm === 'end' ? 'end' : 'cancel' })
                  setConfirm(null)
                }}
                className="flex-1 py-2.5 rounded-xl text-sm font-bold bg-red-700 text-white hover:bg-red-600 cursor-pointer"
              >
                Confirmar
              </button>
              <button
                type="button"
                onClick={() => setConfirm(null)}
                className="flex-1 py-2.5 rounded-xl text-sm font-bold border border-neutral-700 text-neutral-300 hover:bg-neutral-800 cursor-pointer"
              >
                Voltar
              </button>
            </div>
          </div>
        ) : (
          <div className="flex gap-3">
            <button
              type="button"
              onClick={() => setConfirm('end')}
              className="flex-1 py-2.5 rounded-xl text-xs font-bold border border-neutral-800 text-neutral-400 hover:text-neutral-200 cursor-pointer"
            >
              Encerrar partida
            </button>
            <button
              type="button"
              onClick={() => setConfirm('cancel')}
              className="flex-1 py-2.5 rounded-xl text-xs font-bold border border-neutral-800 text-neutral-500 hover:text-neutral-300 cursor-pointer"
            >
              Cancelar partida
            </button>
          </div>
        )}
      </footer>
    </div>
  )
}
```

`src/components/caderneta/end-screen.tsx`:

```tsx
'use client'

import type { Dispatch } from 'react'
import { ROLE_LABEL, ROLE_STYLE } from '@/lib/cards'
import type { Action, CadernetaState } from '@/lib/caderneta/state'

interface EndScreenProps {
  state: CadernetaState
  dispatch: Dispatch<Action>
}

export function EndScreen({ state, dispatch }: EndScreenProps) {
  return (
    <div className="space-y-6">
      <header className="text-center space-y-1">
        <h1 className="font-display text-5xl tracking-widest text-red-600">FIM DE JOGO</h1>
        <p className="text-neutral-500 text-xs">Os papéis de todos, na partida que acabou.</p>
      </header>

      <ul className="space-y-2">
        {state.players.map((p) => (
          <li
            key={p.id}
            className="flex items-center gap-3 px-4 py-3 rounded-xl border border-neutral-800 bg-neutral-900/50"
          >
            <span className={`flex-1 truncate text-sm ${p.alive ? 'text-neutral-200' : 'text-neutral-500 line-through'}`}>
              {p.name}
            </span>
            <span className={`px-2 py-0.5 rounded-md border text-[11px] font-medium ${ROLE_STYLE[p.role] ?? ''}`}>
              {ROLE_LABEL[p.role] ?? p.role}
            </span>
          </li>
        ))}
      </ul>

      <button
        type="button"
        onClick={() => dispatch({ type: 'reset' })}
        className="w-full py-4 rounded-2xl font-bold text-lg tracking-wider bg-red-700 text-white hover:bg-red-600 active:bg-red-800 shadow-lg shadow-red-900/40 cursor-pointer transition-all"
      >
        Nova partida
      </button>
    </div>
  )
}
```

- [ ] **Step 5: Ligar o painel e a tela final na rota**

Em `src/app/caderneta/page.tsx`, adicionar os imports e as duas linhas de renderização. Resultado final do arquivo:

```tsx
'use client'

import Link from 'next/link'
import { useCaderneta } from '@/hooks/use-caderneta'
import { SetupScreen } from '@/components/caderneta/setup-screen'
import { DealScreen } from '@/components/caderneta/deal-screen'
import { PlayPanel } from '@/components/caderneta/play-panel'
import { EndScreen } from '@/components/caderneta/end-screen'

export default function CadernetaPage() {
  const { state, dispatch, hydrated } = useCaderneta()

  if (!hydrated) return <main className="min-h-dvh" />

  const dealing = state.phase === 'deal' ? state.players[state.dealIndex] : undefined

  return (
    <main className="mx-auto w-full max-w-sm min-h-dvh px-4 py-6">
      {state.phase === 'setup' && (
        <>
          <Link href="/" className="inline-block mb-4 text-neutral-500 hover:text-neutral-300 text-xs">
            ← Início
          </Link>
          <SetupScreen state={state} dispatch={dispatch} />
        </>
      )}
      {dealing && (
        <DealScreen
          key={state.dealIndex}
          player={dealing}
          isLast={state.dealIndex === state.players.length - 1}
          onNext={() => dispatch({ type: 'nextDeal' })}
        />
      )}
      {state.phase === 'play' && <PlayPanel state={state} dispatch={dispatch} />}
      {state.phase === 'ended' && <EndScreen state={state} dispatch={dispatch} />}
    </main>
  )
}
```

- [ ] **Step 6: Verificação manual**

Run: `npx tsc --noEmit && npx eslint src/components/caderneta src/app/caderneta src/hooks/use-caderneta.ts`, depois `npm run dev` e percorrer `/caderneta` do início ao fim com um cenário que tenha Maçom, Cupido, Bruxa, Lobo, Vidente, Bêbado.
Expected: noite 1 lista Maçons, Cupido, Lobos, Vidente (sem Bruxa), com o próximo pulsando e os nomes de quem tem o papel; "Amanhecer" com passos pendentes pede confirmação; o dia mostra cronômetro e strikes, o 3º strike abre "Eliminar?"; "Anoitecer" vai para a noite 2 e a Bruxa aparece; na noite 3 aparece o Bêbado com "Revelar e trocar papel"; marcar vivo/morto, etiquetas, nota e "Trocar papel" funcionam; recarregar a página no meio mantém tudo; "Encerrar partida" mostra os papéis e "Nova partida" volta à montagem.

- [ ] **Step 7: Commit**

```bash
git add src/components/caderneta src/app/caderneta
git commit -m "feat: caderneta play panel (night order, day tools, players) and end screen"
```

---

### Task 6: Home com a Caderneta como modo principal

**Files:**
- Modify: `src/app/page.tsx` (imports e o bloco de JSX a partir de `<div className="w-full flex flex-col gap-4">`)

**Interfaces:**
- Consumes: rota `/caderneta` (Task 5). Lógica online (`handleCriarSala`, `handleEntrar`, `handleKeyDown`, estados) permanece intacta.

- [ ] **Step 1: Importar `Link`**

Em `src/app/page.tsx`, depois de `import Image from 'next/image'` adicionar:

```tsx
import Link from 'next/link'
```

- [ ] **Step 2: Inserir o botão principal e o cabeçalho da seção online**

Substituir exatamente este trecho:

```tsx
        <div className="w-full flex flex-col gap-4">
          <input
            type="text"
            placeholder="Nome do Jogador"
```

por:

```tsx
        <div className="w-full flex flex-col gap-4">
          <Link
            href="/caderneta"
            className="
              w-full py-4 rounded-2xl font-bold text-base tracking-wider text-center
              bg-primary hover:bg-primary-hover active:bg-primary-active text-white
              shadow-lg shadow-red-900/30
              transition-all duration-200
            "
          >
            Caderneta do Mestre
          </Link>
          <p className="text-neutral-500 text-xs text-center leading-relaxed">
            Um celular só, o mestre conduz. Cada jogador vê a própria carta sem precisar de conta.
          </p>

          <div className="flex items-center gap-2 mt-4">
            <span className="flex-1 h-px bg-neutral-800" />
            <h2 className="text-neutral-500 text-[10px] uppercase tracking-widest">Jogar online</h2>
            <span className="flex-1 h-px bg-neutral-800" />
          </div>
          <p className="text-neutral-600 text-[11px] text-center">
            Cada um no seu celular, com sala e código.
          </p>

          <input
            type="text"
            placeholder="Nome do Jogador"
```

- [ ] **Step 3: Verificação**

Run: `npx tsc --noEmit`, `npm run dev`, abrir `http://localhost:3000/`.
Expected: "Caderneta do Mestre" é o botão grande e principal, com a frase explicativa; abaixo, a seção "Jogar online" com nome, PIN, "Criar Sala" e "Entrar" funcionando como antes; o botão da Caderneta leva a `/caderneta`.

- [ ] **Step 4: Commit**

```bash
git add src/app/page.tsx
git commit -m "feat: make Caderneta do Mestre the primary mode on the home screen"
```

---

### Task 7: Documentação, verificação final e push

**Files:**
- Modify: `docs/architecture.md` (entrada nova no topo, antes da primeira entrada `<current>`)
- Modify: `docs/superpowers/specs/2026-10-15-caderneta-do-mestre-design.md` (tabela de componentes: acrescentar `players-list.tsx` e `src/lib/scenario.ts`)

- [ ] **Step 1: Rodar todas as verificações**

Run:
```bash
npm test
npx tsc --noEmit
npx eslint src/lib/scenario.ts src/lib/caderneta src/hooks src/components/scenario-card-picker.tsx src/components/scenario-builder.tsx src/components/caderneta src/app/caderneta src/app/page.tsx
npm run build
```
Expected: testes passam; sem erros de tipo; lint sem erros novos nos arquivos tocados (os 45 erros pré-existentes são de outros arquivos); `next build --webpack` compila. Se o build falhar só na pré-renderização por `.env.local` ilegível (OneDrive, já documentado em `architecture.md`), registrar isso e seguir, pois produção usa as variáveis da Vercel.

- [ ] **Step 2: Registrar em `docs/architecture.md`**

Inserir logo abaixo do parágrafo de Overview (antes de `### \`<current>\` — Role groups...`), preenchendo `<HASH>` com o hash do commit da Task 3 (`git log --oneline`):

```markdown
### `<current>` — Caderneta do Mestre (modo de 1 celular) + termômetro fixo (commits `<HASH>`…)

- **Novo modo principal** na home: `/caderneta`. Um celular só, sem Supabase, sem sala/PIN/conta. Fluxo: montar (nomes + cenário) → entregar cartas (passa-o-celular; **segurar para ver**, ao soltar esconde; verso com `verse-card.jpeg`; tela "Entregue ao mestre" no fim) → painel do mestre (Noite N: ordem de despertar de `NIGHT_STEPS`/`stepIsAvailable`, com nomes de quem tem cada papel; Dia N: `VoteTimerPanel` + strikes locais 0–3 com confirmação de eliminação; lista de jogadores com vivo/morto, etiquetas, nota e "Trocar papel") → tela final com os papéis. O app **não resolve a noite nem declara vencedor** (caderneta inteligente); só mostra lobos × demais vivos. O nome do modo na UI é "Caderneta do Mestre".
- **Estado**: `src/lib/caderneta/state.ts` (TS puro: reducer, `drawRoles` Fisher-Yates com `rng` injetável, seletores, `sanitizeState`) + `src/hooks/use-caderneta.ts` (persistência em `localStorage` `lobinho:caderneta:v1`, hidratação após montar, estado corrompido/de outra versão é descartado).
- **Termômetro fixo**: a barra Equilibrado/Vantagem da Aldeia/Vantagem dos Lobos agora é `sticky` no topo durante a rolagem (fundo opaco, respeita `safe-area-inset-top`). Para valer nos dois modos, a UI de escolher cartas saiu do `ScenarioBuilder` para `src/components/scenario-card-picker.tsx` (sem Supabase); o `ScenarioBuilder` manteve a parte online (modo de revelação, Variante Fantasma, `start_game`) sem mudança de lógica. Contagens do cenário em `src/hooks/use-scenario-counts.ts` (mesma chave `lobinho_last_scenario`); contas puras em `src/lib/scenario.ts`; `DRUNK_ALLOWED` foi para `src/lib/cards.ts`.
- **Testes**: primeiro runner do repo — `npm test` (`node --test`, Node 24 roda `.ts` direto, sem dependência). `tsconfig.json` ganhou `allowImportingTsExtensions` porque os módulos puros usam imports relativos `.ts`. Cobertura: `src/lib/scenario.test.ts`, `src/lib/caderneta/state.test.ts`.
- **Sem banco**: nenhuma migração, `game_rules.md` não muda.
- **Files**: `src/app/caderneta/page.tsx`, `src/app/page.tsx`, `src/components/caderneta/*`, `src/components/scenario-card-picker.tsx`, `src/components/scenario-builder.tsx`, `src/hooks/use-caderneta.ts`, `src/hooks/use-scenario-counts.ts`, `src/lib/caderneta/state.ts`, `src/lib/scenario.ts`, `src/lib/cards.ts`, `tsconfig.json`, `package.json`, `docs/superpowers/{specs,plans}/`.
```

- [ ] **Step 3: Atualizar a tabela de componentes da spec**

Na spec, na tabela "Componentes novos", acrescentar as linhas:

```markdown
| `src/components/caderneta/players-list.tsx` | Lista de jogadores do painel (vivo/morto, etiquetas, nota, trocar papel) |
| `src/lib/scenario.ts` | Contas puras do cenário (contagem, pontos, equilíbrio, validação) |
```

- [ ] **Step 4: Commit da documentação e push**

```bash
git add docs
git commit -m "docs: architecture entry, spec and plan for Caderneta do Mestre"
git push
```
Expected: push para `origin master`; a Vercel faz o deploy sozinha (não redeployar manualmente).

- [ ] **Step 5: Trello**

Mover o card https://trello.com/c/DVFdnxOW/57-criar-um-hub-de-mestre para a lista adequada **somente se o usuário pedir**; caso contrário apenas informar que a task está entregue.
```

## Self-Review (feito ao escrever)

- **Cobertura da spec:** home principal (Task 6); rota e fluxo setup/deal/play/ended (Tasks 4–5); estado e persistência (Tasks 2 e 4); termômetro fixo e `ScenarioCardPicker` (Task 3); `DRUNK_ALLOWED` em `cards.ts` (Task 1); testes `node --test` (Tasks 1–2); docs/architecture (Task 7); sem Supabase/migração (restrições globais). Bêbado (reserva + revelar/trocar) em `pickDrunkRole` e `NightStepsList`. Aviso de cenário sem lobo/Vidente em `SetupScreen`. Anti-espiada (callout iOS, `pointercancel`, `visibilitychange`, tela neutra, "Entregue ao mestre") em `DealScreen`. Encerrar/Cancelar com confirmação em `PlayPanel`.
- **Placeholders:** nenhum; o único valor a preencher é o hash do commit na entrada da documentação (Task 7, Step 2), obtido de `git log`.
- **Consistência de tipos:** `Action`, `CadernetaState`, `CadernetaPlayer`, `ScenarioCounts` e as assinaturas de `drawRoles`/`pickDrunkRole`/`addName` são as mesmas em `state.ts`, nos testes e nos componentes; os ids de jogador (`p0`…) usados nos testes batem com o reducer (`p${i}`).
