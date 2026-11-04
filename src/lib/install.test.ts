import { test } from 'node:test'
import assert from 'node:assert/strict'
import { installMode, isIosUa } from './install.ts'

const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1'
const IPAD_DESKTOP = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15'
const ANDROID = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/120.0 Mobile Safari/537.36'
const DESKTOP = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0 Safari/537.36'

test('iOS: iPhone e iPad (inclusive iPadOS em modo desktop, que tem toque); Mac sem toque não', () => {
  assert.equal(isIosUa(IPHONE, true), true)
  assert.equal(isIosUa(IPAD_DESKTOP, true), true)
  assert.equal(isIosUa(IPAD_DESKTOP, false), false)
})

test('iOS no navegador mostra o passo a passo; instalado (standalone) não mostra nada', () => {
  assert.equal(installMode({ standalone: false, ua: IPHONE, hasTouch: true, installable: false }), 'ios')
  assert.equal(installMode({ standalone: true, ua: IPHONE, hasTouch: true, installable: false }), null)
})

test('Android só mostra quando o navegador oferece a instalação; instalado não mostra', () => {
  assert.equal(installMode({ standalone: false, ua: ANDROID, hasTouch: true, installable: true }), 'native')
  assert.equal(installMode({ standalone: false, ua: ANDROID, hasTouch: true, installable: false }), null)
  assert.equal(installMode({ standalone: true, ua: ANDROID, hasTouch: true, installable: true }), null)
})

test('desktop não recebe o pop-up, mesmo podendo instalar', () => {
  assert.equal(installMode({ standalone: false, ua: DESKTOP, hasTouch: false, installable: true }), null)
})
