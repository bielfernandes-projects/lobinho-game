import { PhoneFrame } from './phone-frame'

// Os prints dependem da UI da Caderneta: se ela mudar muito, refazer public/landing/passo-N.png.
const STEPS = [
  {
    title: 'Monte a mesa',
    text: 'Digite os nomes e escolha as cartas. O termômetro mostra se o cenário está equilibrado.',
    image: '/landing/passo-1.png',
    alt: 'Tela de montagem com nomes dos jogadores e cartas do cenário',
  },
  {
    title: 'Passe o celular',
    text: 'Cada jogador segura a carta para ver o próprio papel. Soltou, esconde.',
    image: '/landing/passo-2.png',
    alt: 'Tela com a carta de costas e a instrução "segure a carta para ver"',
  },
  {
    title: 'Conduza a noite',
    text: 'A ordem de acordar fica pronta, e você anota quem cada papel escolheu.',
    image: '/landing/passo-3.png',
    alt: 'Painel da noite com a ordem de acordar e as anotações do Cupido',
  },
  {
    title: 'Veja quem venceu',
    text: 'O app conta os vivos e avisa o vencedor. Você decide quando encerrar.',
    image: '/landing/passo-4.png',
    alt: 'Painel com o banner de vitória',
  },
]

export function HowItWorks() {
  return (
    <section className="w-full max-w-5xl px-6 py-16">
      <h2 className="font-display text-4xl tracking-widest text-red-600 text-center mb-10">COMO FUNCIONA</h2>
      <ol className="grid gap-10 sm:grid-cols-2 lg:grid-cols-4">
        {STEPS.map((s, i) => (
          <li key={s.title} className="text-center space-y-3">
            <PhoneFrame src={s.image} alt={s.alt} />
            <h3 className="font-bold text-neutral-200">
              {i + 1}. {s.title}
            </h3>
            <p className="text-neutral-500 text-sm leading-relaxed max-w-xs mx-auto">{s.text}</p>
          </li>
        ))}
      </ol>
    </section>
  )
}
