import { test } from 'node:test'
import assert from 'node:assert/strict'
import { CARD_CATALOG } from '../cards.ts'
import {
  PRESETS, SAVED_MAX, describeCounts, parseSaved, removeScenario, sameCounts, saveScenario, summarize,
} from './presets.ts'

test('todo preset usa só papéis do catálogo e é equilibrado (-3..+3)', () => {
  const ids = new Set(CARD_CATALOG.map((c) => c.id))
  for (const p of PRESETS) {
    for (const id of Object.keys(p.counts)) assert.ok(ids.has(id), `${p.id}: papel ${id} não existe`)
    assert.equal(summarize(p.counts).balance, 'balanced', `${p.name} não está equilibrado`)
  }
})

test('presets têm pelo menos 6 cartas e os dois mínimos têm exatamente 6', () => {
  for (const p of PRESETS) assert.ok(summarize(p.counts).cards >= 6, p.name)
  assert.equal(summarize(PRESETS[0].counts).cards, 6)
  assert.equal(summarize(PRESETS[1].counts).cards, 6)
})

test('describeCounts agrupa repetidos e mostra inglês (português)', () => {
  const text = describeCounts({ villager: 4, werewolf: 2, seer: 1 })
  assert.ok(text.includes('2× Werewolf (Lobisomem)') && text.includes('4× Villager (Aldeão)') && text.includes('Seer (Vidente)'))
  assert.ok(!text.includes('1×'))
})

test('parseSaved descarta lixo, nomes longos e papéis desconhecidos', () => {
  assert.deepEqual(parseSaved(null), [])
  assert.deepEqual(parseSaved('{não é json'), [])
  assert.deepEqual(parseSaved('{"a":1}'), [])
  const ok = { name: 'Sexta', counts: { werewolf: 2, villager: 4 } }
  const raw = JSON.stringify([
    ok,
    { name: 'x', counts: { inexistente: 1 } },
    { name: '', counts: { seer: 1 } },
    { name: 'y', counts: { seer: -1 } },
    5,
  ])
  assert.deepEqual(parseSaved(raw), [ok])
})

test('saveScenario: nome vazio e zero cartas dão erro; mesmo nome sobrescreve; limite respeitado', () => {
  assert.ok(saveScenario([], '  ', { seer: 1 }).error)
  assert.ok(saveScenario([], 'A', { seer: 0 }).error)
  const a = saveScenario([], 'Sexta', { seer: 1, werewolf: 2 }).list
  const b = saveScenario(a, 'sexta', { seer: 2 }).list
  assert.equal(b.length, 1)
  assert.deepEqual(b[0].counts, { seer: 2 })
  let full = [] as ReturnType<typeof saveScenario>['list']
  for (let i = 0; i < SAVED_MAX; i++) full = saveScenario(full, `n${i}`, { seer: 1 }).list
  assert.ok(saveScenario(full, 'extra', { seer: 1 }).error)
  assert.equal(removeScenario(full, 'n0').length, SAVED_MAX - 1)
})

test('sameCounts: zero e ausente são iguais; quantidade diferente não', () => {
  assert.equal(sameCounts({ seer: 1, villager: 0 }, { seer: 1 }), true)
  assert.equal(sameCounts({ seer: 1 }, { seer: 2 }), false)
  assert.equal(sameCounts({}, { seer: 1 }), false)
})

test('tamanho de cada preset (guarda contra erro de conta ao editar a lista)', () => {
  const size = Object.fromEntries(PRESETS.map((p) => [p.id, summarize(p.counts).cards]))
  assert.deepEqual(size, {
    'minimo-2-lobos': 6, 'minimo-1-lobo': 6, classico: 8, 'com-amor': 8, rapido: 8,
    'guarda-costas': 10, cacada: 10, 'vila-animada': 12, caotico: 12,
  })
})
