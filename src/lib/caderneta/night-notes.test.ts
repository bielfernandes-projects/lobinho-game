import { test } from 'node:test'
import assert from 'node:assert/strict'
import { wolvesStepNotes } from './night-notes.ts'

const pl = (role: string, alive = true) => ({ id: role + alive, role, alive, tags: [] as string[] })

test('Lobo Alfa vivo lembra da regra da expansão; morto não', () => {
  assert.ok(wolvesStepNotes([pl('alpha_wolf'), pl('villager')], 2).some((n) => n.includes('depois que um Lobisomem')))
  assert.equal(wolvesStepNotes([pl('alpha_wolf', false), pl('werewolf')], 2).length, 0)
})

test('Lobo Mau vivo lembra dos 2 adjacentes; morto não', () => {
  assert.equal(wolvesStepNotes([pl('bad_wolf'), pl('villager')], 1).length, 1)
  assert.equal(wolvesStepNotes([pl('bad_wolf', false), pl('werewolf')], 1).length, 0)
})

test('Lobo Vegetariano só some das noites 2+ se houver outros lobos', () => {
  assert.equal(wolvesStepNotes([pl('fruit_brute'), pl('werewolf')], 1).length, 0)
  assert.equal(wolvesStepNotes([pl('fruit_brute'), pl('werewolf')], 2).length, 1)
  assert.equal(wolvesStepNotes([pl('fruit_brute'), pl('villager')], 2).length, 0)
})

test('Wolverine como último lobo não mata', () => {
  assert.equal(wolvesStepNotes([pl('wolverine'), pl('villager')], 2).length, 1)
  assert.equal(wolvesStepNotes([pl('wolverine'), pl('werewolf')], 2).length, 0)
})
