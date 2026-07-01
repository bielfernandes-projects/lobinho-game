export interface CardDefinition {
  id: string
  name: string
  points: number
  description: string
}

export const CARD_CATALOG: CardDefinition[] = [
  {
    id: 'werewolf',
    name: 'Lobisomem',
    points: -6,
    description:
      'Toda noite, acorde com os lobos e escolham em conjunto alguém para eliminar.',
  },
  {
    id: 'seer',
    name: 'Vidente',
    points: 7,
    description: 'Toda noite, escolha alguém para saber se é vila ou lobo.',
  },
  {
    id: 'witch',
    name: 'Bruxa',
    points: 4,
    description:
      'Uma vez por jogo, durante a noite, você pode usar poção da vida ou da morte.',
  },
  {
    id: 'villager',
    name: 'Aldeão',
    points: 1,
    description: 'Encontre os lobisomens e elimine-os.',
  },
]
