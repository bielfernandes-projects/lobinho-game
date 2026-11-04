// When to offer "install the app". Pure: run directly by `node --test`.

export type InstallMode = 'ios' | 'native'

/** iPhone/iPad/iPod, including iPadOS asking for the desktop site (a Mac that has a touch screen). */
export function isIosUa(ua: string, hasTouch: boolean): boolean {
  return /iPad|iPhone|iPod/.test(ua) || (ua.includes('Macintosh') && hasTouch)
}

/**
 * - `ios`: Safari never fires `beforeinstallprompt`, so we show the "Add to Home Screen" steps.
 * - `native`: Android with the browser's install prompt available (it only fires when not installed yet).
 * - `null`: already running as the installed app, or not a phone (desktop, or Android without the prompt).
 */
export function installMode(o: {
  standalone: boolean
  ua: string
  hasTouch: boolean
  installable: boolean
}): InstallMode | null {
  if (o.standalone) return null
  if (isIosUa(o.ua, o.hasTouch)) return 'ios'
  if (/Android/i.test(o.ua) && o.installable) return 'native'
  return null
}
