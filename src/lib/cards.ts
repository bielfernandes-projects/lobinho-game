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
  {
    id: 'mayor',
    name: 'Prefeito',
    points: 2,
    description:
      'Seu voto no tribunal conta dobrado.',
  },
  {
    id: 'prince',
    name: 'Príncipe',
    points: 3,
    description:
      'Se a vila decidir te linchar, você revela sua identidade e sobrevive.',
  },
  {
    id: 'tanner',
    name: 'Curtidor',
    points: -2,
    description:
      'Você odeia seu trabalho. Você ganha o jogo se conseguir ser linchado pela vila.',
  },
  {
    id: 'lycan',
    name: 'Licano',
    points: -1,
    description:
      'Você é da vila, mas tem sangue de lobo. A Vidente te enxerga como Lobisomem.',
  },
]
