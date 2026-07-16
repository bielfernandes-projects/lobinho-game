'use client'

import type { CardDefinition } from '@/lib/cards'

interface RoleInfoModalProps {
  open: boolean
  onClose: () => void
  card: CardDefinition | null
}

export function RoleInfoModal({ open, onClose, card }: RoleInfoModalProps) {
  if (!open || !card) return null

  return (
    <div
      className="fixed inset-0 z-[100] flex items-center justify-center bg-black/50 px-6"
      onClick={onClose}
    >
      <div
        className="w-full max-w-xs rounded-2xl border border-neutral-700 bg-neutral-900 p-6 text-center space-y-4"
        onClick={(e) => e.stopPropagation()}
      >
        <p className="text-neutral-200 text-lg font-bold">{card.name}</p>
        <p className="text-neutral-400 text-sm leading-relaxed">
          {card.description}
        </p>
        <button
          onClick={onClose}
          className="w-full py-2.5 rounded-xl text-xs font-medium tracking-wider text-neutral-500 border border-neutral-700 hover:text-neutral-300 hover:border-neutral-600 transition-all duration-200 cursor-pointer"
        >
          Fechar ✕
        </button>
      </div>
    </div>
  )
}
