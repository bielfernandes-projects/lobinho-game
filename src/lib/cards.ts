export type Team = 'village' | 'wolf' | 'independent'

export interface CardDefinition {
  id: string
  name: string
  points: number
  description: string
  team: Team
}

export const ROLE_STYLE: Record<string, string> = {
  werewolf: 'bg-red-100 text-red-700 border-red-300',
  wolf_cub: 'bg-red-100 text-red-700 border-red-300',
  alpha_wolf: 'bg-red-200 text-red-800 border-red-400',
  lone_wolf: 'bg-orange-100 text-orange-700 border-orange-300',
  seer: 'bg-purple-100 text-purple-700 border-purple-300',
  aura_seer: 'bg-purple-100 text-purple-700 border-purple-300',
  witch: 'bg-pink-100 text-pink-700 border-pink-300',
  villager: 'bg-blue-100 text-blue-700 border-blue-300',
  lycan: 'bg-blue-100 text-blue-700 border-blue-300',
  mayor: 'bg-amber-100 text-amber-700 border-amber-300',
  prince: 'bg-cyan-100 text-cyan-700 border-cyan-300',
  tanner: 'bg-gray-200 text-gray-700 border-gray-400',
  priest: 'bg-emerald-100 text-emerald-700 border-emerald-300',
  bodyguard: 'bg-slate-100 text-slate-700 border-slate-300',
  cupid: 'bg-pink-100 text-pink-700 border-pink-300',
  cult_leader: 'bg-violet-100 text-violet-700 border-violet-300',
  mason: 'bg-emerald-100 text-emerald-700 border-emerald-300',
  pacifist: 'bg-sky-100 text-sky-700 border-sky-300',
  idiot: 'bg-amber-100 text-amber-700 border-amber-300',
  sorceress: 'bg-red-100 text-red-700 border-red-300',
  hunter: 'bg-orange-100 text-orange-700 border-orange-300',
  squire: 'bg-cyan-100 text-cyan-700 border-cyan-300',
  marksman: 'bg-red-100 text-red-700 border-red-300',
  diseased: 'bg-lime-100 text-lime-700 border-lime-300',
  cursed: 'bg-blue-100 text-blue-700 border-blue-300',
  doppelganger: 'bg-violet-100 text-violet-700 border-violet-300',
}

export const ROLE_LABEL: Record<string, string> = {
  werewolf: '🐺 Lobisomem',
  seer: '🔮 Vidente',
  aura_seer: '👁️ Vidente de Aura',
  witch: '🧙 Bruxa',
  villager: '🌿 Aldeão',
  lycan: '🌿 Licano',
  mayor: '👑 Prefeito',
  prince: '🤴 Príncipe',
  tanner: '👔 Curtidor',
  priest: '🙏 Padre',
  bodyguard: '🛡️ Guarda-costas',
  wolf_cub: '🐺 Filhote de Lobo',
  alpha_wolf: '🐺 Lobo Alfa',
  lone_wolf: '🐺 Lobo Solitário',
  cupid: '💘 Cupido',
  cult_leader: '🔮 Líder de Culto',
  mason: '🧱 Maçom',
  pacifist: '🕊️ Pacifista',
  idiot: '🤪 Idiota',
  sorceress: '🔮 Feiticeira',
  moderator: '🎙️ Mestre',
  hunter: '🔫 Caçador',
  squire: '🛡️ Escudeiro',
  marksman: '🎯 Atirador',
  diseased: '🤢 Doente',
  cursed: '🔮 Amaldiçoado',
  doppelganger: '🎭 Doppelgänger',
}

export const ROLE_TRANSLATION: Record<string, string> = {
  werewolf: 'Lobisomem',
  seer: 'Vidente',
  witch: 'Bruxa',
  villager: 'Aldeão',
  mayor: 'Prefeito',
  prince: 'Príncipe',
  tanner: 'Curtidor',
  lycan: 'Licano',
  priest: 'Padre',
  bodyguard: 'Guarda-costas',
  aura_seer: 'Vidente de Aura',
  cupid: 'Cupido',
  cult_leader: 'Líder de Culto',
  mason: 'Maçom',
  pacifist: 'Pacifista',
  idiot: 'Idiota',
  sorceress: 'Feiticeira',
  wolf_cub: 'Filhote de Lobo',
  lone_wolf: 'Lobo Solitário',
  alpha_wolf: 'Lobo Alfa',
  moderator: 'Mestre',
  hunter: 'Caçador',
  squire: 'Escudeiro',
  marksman: 'Atirador',
  diseased: 'Doente',
  cursed: 'Amaldiçoado',
  doppelganger: 'Doppelgänger',
}

export const CARD_CATALOG: CardDefinition[] = [
  {
    id: 'werewolf',
    name: 'Werewolf',
    points: -6,
    team: 'wolf',
    description:
      'Toda noite, acorde com os lobos e escolham em conjunto alguém para eliminar.',
  },
  {
    id: 'seer',
    name: 'Seer',
    points: 7,
    team: 'village',
    description: 'Toda noite, escolha alguém para saber se é vila ou lobo.',
  },
  {
    id: 'witch',
    name: 'Witch',
    points: 4,
    team: 'village',
    description:
      'Uma vez por jogo, durante a noite, você pode usar poção da vida ou da morte.',
  },
  {
    id: 'villager',
    name: 'Villager',
    points: 1,
    team: 'village',
    description: 'Encontre os lobisomens e elimine-os.',
  },
  {
    id: 'mayor',
    name: 'Mayor',
    points: 2,
    team: 'village',
    description:
      'Seu voto no tribunal conta dobrado.',
  },
  {
    id: 'prince',
    name: 'Prince',
    points: 3,
    team: 'village',
    description:
      'Se a vila decidir te linchar, você revela sua identidade e sobrevive.',
  },
  {
    id: 'tanner',
    name: 'Tanner',
    points: -2,
    team: 'independent',
    description:
      'Você odeia seu trabalho. Você ganha o jogo se conseguir ser linchado pela vila.',
  },
  {
    id: 'lycan',
    name: 'Lycan',
    points: -1,
    team: 'village',
    description:
      'Você é da vila, mas tem sangue de lobo. A Vidente te enxerga como Lobisomem.',
  },
  {
    id: 'priest',
    name: 'Priest',
    points: 3,
    team: 'village',
    description:
      'Uma vez por jogo, escolha alguém para receber um escudo permanente. A próxima tentativa de matar essa pessoa (por lobos, bruxa ou tribunal) falhará e gastará a bênção.',
  },
  {
    id: 'bodyguard',
    name: 'Bodyguard',
    points: 3,
    team: 'village',
    description:
      'Toda noite, proteja um jogador. O escudo dura SÓ AQUELA NOITE e bloqueia lobos e poções. Não proteja o mesmo alvo 2x seguidas.',
  },
  {
    id: 'aura_seer',
    name: 'Aura Seer',
    points: 3,
    team: 'village',
    description:
      'Toda noite, descubra se um jogador tem um papel especial (não é Aldeão nem Lobisomem).',
  },
  {
    id: 'cupid',
    name: 'Cupid',
    points: -3,
    team: 'independent',
    description:
      'Na 1ª noite, escolha dois jogadores para serem almas gêmeas. Se um morrer, o outro morre de coração partido.',
  },
  {
    id: 'cult_leader',
    name: 'Cult Leader',
    points: 1,
    team: 'independent',
    description:
      'Toda noite, converta um jogador para o culto. Se todos os vivos estiverem no culto, você vence!',
  },
  {
    id: 'mason',
    name: 'Mason',
    points: 2,
    team: 'village',
    description: 'Na 1ª noite, acorde com os outros Maçons para se reconhecerem. Vocês são aliados secretos.',
  },
  {
    id: 'pacifist',
    name: 'Pacifist',
    points: 2,
    team: 'village',
    description: 'Você odeia violência. Seu voto no tribunal é SEMPRE pela absolvição (NÃO).',
  },
  {
    id: 'idiot',
    name: 'Idiot',
    points: 2,
    team: 'village',
    description: 'Você quer ver sangue. Seu voto no tribunal é SEMPRE pelo linchamento (SIM).',
  },
  {
    id: 'sorceress',
    name: 'Sorceress',
    points: -3,
    team: 'wolf',
    description: 'Toda noite, procure pela Vidente. Os lobos não sabem quem você é, e a Vidente te enxerga como Aldeão.',
  },
  {
    id: 'wolf_cub',
    name: 'Wolf Cub',
    points: -8,
    team: 'wolf',
    description:
      'Se você morrer, os lobos entram em frenesi e escolhem DUAS vítimas na noite seguinte.',
  },
  {
    id: 'lone_wolf',
    name: 'Lone Wolf',
    points: -5,
    team: 'independent',
    description:
      'Você acorda com os lobos, mas só vence o jogo se for o ÚLTIMO jogador vivo na mesa.',
  },
  {
    id: 'alpha_wolf',
    name: 'Alpha Wolf',
    points: -9,
    team: 'wolf',
    description:
      'Uma vez por jogo, você pode transformar a vítima dos lobos em um Lobisomem em vez de matá-la.',
  },
  {
    id: 'hunter',
    name: 'Hunter',
    points: 3,
    team: 'village',
    description:
      'Quando você morrer, pode atirar em um jogador. Sua vítima morre imediatamente antes de você.',
  },
  {
    id: 'squire',
    name: 'Squire',
    points: 1,
    team: 'village',
    description:
      'Se o Príncipe morrer, você assume seu lugar e se torna o novo Príncipe.',
  },
  {
    id: 'marksman',
    name: 'Marksman',
    points: 2,
    team: 'village',
    description:
      'Uma vez por jogo, durante o dia, você pode atirar em um jogador antes do tribunal.',
  },
  {
    id: 'diseased',
    name: 'Diseased',
    points: 3,
    team: 'village',
    description:
      'Se você for morto por lobos, eles não matam ninguém na noite seguinte.',
  },
  {
    id: 'cursed',
    name: 'Cursed',
    points: -3,
    team: 'village',
    description:
      'Se os lobos te atacarem, você não morre — se torna um Lobisomem na noite seguinte.',
  },
  {
    id: 'doppelganger',
    name: 'Doppelgänger',
    points: -2,
    team: 'independent',
    description:
      'Na 1ª noite, escolha um jogador. Se ele for morto, você assume secretamente esse papel. Enquanto seu alvo estiver vivo, você é do time dos Aldeões.',
  },
]
