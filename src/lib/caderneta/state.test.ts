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
