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
