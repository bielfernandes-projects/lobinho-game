'use client'

import { useState, useCallback, useRef } from 'react'
import { motion } from 'framer-motion'
import Image from 'next/image'

interface FlipCardProps {
  playerName: string
  role: string
  description?: string
  points?: number
  onFirstFlip?: () => void
}

export function FlipCard({ playerName, role, description, points, onFirstFlip }: FlipCardProps) {
  const [isFlipped, setIsFlipped] = useState(false)
  const hasFiredRef = useRef(false)

  const handlePointerDown = useCallback(() => {
    setIsFlipped(true)

    if (!hasFiredRef.current) {
      hasFiredRef.current = true
      onFirstFlip?.()
    }
  }, [onFirstFlip])

  const handlePointerUp = useCallback(() => {
    setIsFlipped(false)
  }, [])

  const handlePointerLeave = useCallback(() => {
    setIsFlipped(false)
  }, [])

  /*
   * Wake Lock API:
   *   const wakeLock = await navigator.wakeLock.request('screen');
   * Chamar em handlePointerDown, liberar em handlePointerUp.
   * Sugestao: guardar wakeLock em uma ref.
   */

  return (
    <div className="perspective-[1000px] w-56 h-80 select-none">
      <motion.div
        className="relative w-full h-full cursor-pointer"
        style={{ transformStyle: 'preserve-3d' }}
        animate={{ rotateY: isFlipped ? 180 : 0 }}
        transition={{ duration: isFlipped ? 0.6 : 0.05, ease: 'easeInOut' }}
        onPointerDown={handlePointerDown}
        onPointerUp={handlePointerUp}
        onPointerLeave={handlePointerLeave}
      >
        {/* Frente — costas da carta */}
        <div
          className="absolute inset-0 overflow-hidden rounded-2xl"
          style={{ backfaceVisibility: 'hidden' }}
        >
          <Image
            src="/verse-card.jpeg"
            alt=""
            fill
            sizes="224px"
            priority
            className="object-cover"
          />
        </div>

        {/* Verso — revela a role */}
        <div
          className="absolute inset-0 rounded-2xl border-2 border-red-600 bg-gradient-to-br from-neutral-950 via-red-950 to-neutral-900 flex flex-col items-center justify-center gap-3 p-6"
          style={{ backfaceVisibility: 'hidden', transform: 'rotateY(180deg)' }}
        >
          <span className="text-neutral-400 text-xs uppercase tracking-widest select-none">
            {playerName}
          </span>
          <div className="w-16 h-0.5 bg-red-800/60 rounded-full" />
          <span className="text-red-500 text-2xl font-bold text-center select-none">
            {role}
          </span>
          {description && (
            <>
              <div className="w-16 h-0.5 bg-red-800/30 rounded-full" />
              <p className="text-neutral-500 text-[10px] leading-relaxed text-center select-none">
                {description}
              </p>
            </>
          )}

        </div>
      </motion.div>
    </div>
  )
}
