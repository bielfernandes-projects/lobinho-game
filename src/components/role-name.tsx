import { ROLE_LABEL, roleNameParts } from '@/lib/cards'

/** "Werewolf (Lobisomem)" with the Portuguese name smaller; `emoji` puts the role icon in front. */
export function RoleName({ id, emoji = false }: { id: string; emoji?: boolean }) {
  const { en, pt } = roleNameParts(id)
  const icon = emoji ? ROLE_LABEL[id]?.split(' ')[0] : undefined
  return (
    <>
      {icon && `${icon} `}
      {en}
      {pt && <span className="text-[0.75em] opacity-70 font-normal"> ({pt})</span>}
    </>
  )
}
