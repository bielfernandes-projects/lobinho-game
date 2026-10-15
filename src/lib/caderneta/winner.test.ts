import { test } from 'node:test'
import assert from 'node:assert/strict'
import { computeWinner, wolfCounts, type WinnerPlayer } from './winner.ts'

let seq = 0
function p(role: string, alive = true, tags: string[] = []): WinnerPlayer {
  return { id: `p${seq++}`, role, alive, tags }
}

test('ninguém morreu ainda: sem vencedor (a checagem só dispara depois de uma morte)', () => {
  assert.equal(computeWinner([p('villager'), p('villager'), p('villager')], null), null)
})

test('sem lobos vivos: a Vila vence', () => {
  const players = [p('werewolf', false), p('seer'), p('villager'), p('villager')]
  assert.equal(computeWinner(players, null), 'villagers_win')
})

test('paridade: lobos >= demais vivos dá vitória dos lobos; antes disso o jogo segue', () => {
  assert.equal(computeWinner([p('werewolf'), p('villager'), p('seer', false)], null), 'wolves_win')
  assert.equal(
    computeWinner([p('werewolf'), p('werewolf'), p('villager'), p('villager'), p('villager'), p('seer', false)], null),
    null,
  )
})

test('Feiticeira e Lacaio contam como time dos lobos', () => {
  const players = [p('sorceress'), p('minion'), p('villager'), p('seer', false)]
  assert.deepEqual(wolfCounts(players), { alive: 3, wolves: 2, others: 1 })
  assert.equal(computeWinner(players, null), 'wolves_win')
})

test('Lobo Solitário não é do time dos lobos na contagem de paridade', () => {
  const players = [p('lone_wolf'), p('werewolf'), p('villager'), p('villager'), p('seer', false)]
  assert.deepEqual(wolfCounts(players), { alive: 4, wolves: 1, others: 3 })
  assert.equal(computeWinner(players, null), null)
})

test('Lobo Solitário: último vivo, ou 1x1 sem lobos; com 3 vivos o jogo segue', () => {
  assert.equal(computeWinner([p('lone_wolf'), p('villager', false)], null), 'lone_wolf_win')
  assert.equal(computeWinner([p('lone_wolf'), p('villager'), p('seer', false)], null), 'lone_wolf_win')
  assert.equal(computeWinner([p('lone_wolf'), p('villager'), p('seer'), p('witch', false)], null), null)
})

test('Chupacu: último vivo, ou 1x1 sem lobos; com 3 vivos o jogo segue', () => {
  assert.equal(computeWinner([p('chupacabra'), p('villager', false)], null), 'chupacabra_win')
  assert.equal(computeWinner([p('chupacabra'), p('villager'), p('seer', false)], null), 'chupacabra_win')
  assert.equal(computeWinner([p('chupacabra'), p('villager'), p('seer'), p('witch', false)], null), null)
})

test('almas gêmeas: sobram só as duas, mesmo de times diferentes (vence antes dos lobos)', () => {
  const players = [
    p('werewolf', true, ['soulmate']),
    p('villager', true, ['soulmate']),
    p('seer', false),
  ]
  assert.equal(computeWinner(players, null), 'soulmates_win')
})

test('almas gêmeas: com 3 vivos, ou com mais de 2 marcadas, não vale', () => {
  const three = [p('villager', true, ['soulmate']), p('villager', true, ['soulmate']), p('seer'), p('witch', false)]
  assert.notEqual(computeWinner(three, null), 'soulmates_win')
  const marked3 = [
    p('villager', true, ['soulmate']),
    p('villager', true, ['soulmate']),
    p('seer', false, ['soulmate']),
  ]
  assert.notEqual(computeWinner(marked3, null), 'soulmates_win')
})

test('culto: líder vivo e todos os outros vivos no culto', () => {
  const win = [p('cult_leader'), p('villager', true, ['cult']), p('seer', true, ['cult']), p('witch', false)]
  assert.equal(computeWinner(win, null), 'cult_win')
  const not = [p('cult_leader'), p('villager', true, ['cult']), p('seer'), p('witch', false)]
  assert.notEqual(computeWinner(not, null), 'cult_win')
})

test('Curtidor: só vence se foi linchado (não por outra morte)', () => {
  const tanner = p('tanner', false)
  const players = [tanner, p('werewolf'), p('villager'), p('villager'), p('villager')]
  assert.equal(computeWinner(players, tanner.id), 'tanner_win')
  assert.equal(computeWinner(players, null), null)
})

test('todos mortos: sem vencedor', () => {
  assert.equal(computeWinner([p('villager', false), p('werewolf', false)], null), null)
})
