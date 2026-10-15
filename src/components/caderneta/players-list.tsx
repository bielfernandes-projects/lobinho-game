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
              <div className="shrink-0 flex flex-col gap-1">
                {p.alive && state.view === 'day' && (
                  <button
                    type="button"
                    onClick={() => dispatch({ type: 'lynch', id: p.id })}
                    className="px-3 py-1.5 rounded-lg text-xs font-bold bg-red-950/30 border border-red-900/50 text-red-300 hover:bg-red-900/40 cursor-pointer transition-all"
                  >
                    ⚖️ Linchar
                  </button>
                )}
                <button
                  type="button"
                  onClick={() => dispatch({ type: 'setAlive', id: p.id, alive: !p.alive })}
                  className="px-3 py-1.5 rounded-lg text-xs font-bold bg-neutral-900 border border-neutral-800 text-neutral-400 hover:text-neutral-200 cursor-pointer transition-all"
                >
                  {p.alive ? '💀 Matar' : '❤️ Reviver'}
                </button>
              </div>
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
