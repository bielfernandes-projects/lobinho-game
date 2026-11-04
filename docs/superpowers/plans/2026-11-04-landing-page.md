# Landing page + tutorial rápido Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transformar `/` numa landing estática em PT-BR com tutorial de 4 passos (prints reais) e fazer o PWA abrir em `/caderneta`.

**Architecture:** `src/app/page.tsx` vira um componente de servidor que compõe `HowItWorks` (4 passos) e `PhoneFrame` (moldura + `next/image`). Os prints ficam em `public/landing/`. Sem lógica nova, sem dependência nova.

**Tech Stack:** Next.js 16 (App Router), Tailwind (tokens `midnight`, `primary`, `font-display`), `next/image`.

**Spec:** `docs/superpowers/specs/2026-11-04-landing-page-design.md`

## Global Constraints

- Idioma: PT-BR, com acentuação correta; tom sinistro/direto/divertido/claro (`docs/brand-guidelines.md`).
- Sem dependência nova e sem animação de rolagem; página estática (componente de servidor, sem `'use client'`).
- O modo online continua só como link discreto sublinhado no rodapé (`/online`).
- Um `h1`, `h2` por seção, `alt` descritivo nos prints, sem rolagem horizontal em 390 px.
- Prints: build de produção (`next build` + `next start`), viewport 390×844, nomes fictícios.
- Antes de commitar: atualizar `docs/architecture.md`. Commit + push ao fim; deploy da Vercel é automático.

---

### Task 1: Prints reais do app

**Files:**
- Create: `public/landing/passo-1.png`, `passo-2.png`, `passo-3.png`, `passo-4.png`

**Produces:** 4 PNGs (largura 390 px reais, até ~150 KB cada) com os nomes acima.

- [ ] **Step 1:** `npm run build` e `npm start` (porta 3000) em segundo plano.
- [ ] **Step 2:** No Chrome (viewport 390×844), abrir `/caderneta`, adicionar 8 nomes fictícios (Ana, Bruno, Carla, Diego, Elisa, Fábio, Gabi, Hugo) e montar o cenário: 1 Vidente, 1 Bruxa, 1 Cupido, 2 Lobisomens, 3 Aldeões.
- [ ] **Step 3:** Capturar: (1) montagem com nomes e cartas; (2) "Vez de NOME" com a carta de costas; (3) painel da noite 1 com a dica do Cupido; (4) painel com o banner de vitória (matar os 2 lobos).
- [ ] **Step 4:** Salvar como `public/landing/passo-N.png`; conferir tamanho; parar o servidor.
- [ ] **Step 5:** Commit: `git add public/landing && git commit -m "docs: screenshots for the landing page"`.

### Task 2: Componentes e página

**Files:**
- Create: `src/components/landing/phone-frame.tsx`
- Create: `src/components/landing/how-it-works.tsx`
- Modify: `src/app/page.tsx`

**Interfaces:**
- Produces: `PhoneFrame({ src, alt }: { src: string; alt: string })`; `HowItWorks()` sem props.

- [ ] **Step 1:** Criar `phone-frame.tsx`:

```tsx
import Image from 'next/image'

export function PhoneFrame({ src, alt }: { src: string; alt: string }) {
  return (
    <div className="relative mx-auto w-48 aspect-[390/844] rounded-[2rem] border-4 border-neutral-800 bg-neutral-900 overflow-hidden shadow-lg shadow-red-900/20">
      <Image src={src} alt={alt} fill sizes="192px" className="object-cover" />
    </div>
  )
}
```

- [ ] **Step 2:** Criar `how-it-works.tsx` com o array dos 4 passos e a grade (1 coluna no celular, 2 em `sm`, 4 em `lg`):

```tsx
import { PhoneFrame } from './phone-frame'

const STEPS = [
  { title: 'Monte a mesa', text: 'Digite os nomes e escolha as cartas. O termômetro mostra se o cenário está equilibrado.', image: '/landing/passo-1.png', alt: 'Tela de montagem com nomes dos jogadores e cartas do cenário' },
  { title: 'Passe o celular', text: 'Cada jogador segura a carta para ver o próprio papel. Soltou, esconde.', image: '/landing/passo-2.png', alt: 'Tela com a carta de costas e a instrução "segure a carta para ver"' },
  { title: 'Conduza a noite', text: 'A ordem de acordar fica pronta, e você anota quem cada papel escolheu.', image: '/landing/passo-3.png', alt: 'Painel da noite com a ordem de acordar e as anotações do Cupido' },
  { title: 'Veja quem venceu', text: 'O app conta os vivos e avisa o vencedor. Você decide quando encerrar.', image: '/landing/passo-4.png', alt: 'Painel com o banner de vitória' },
]

export function HowItWorks() {
  return (
    <section className="w-full max-w-5xl px-6 py-16">
      <h2 className="font-display text-4xl tracking-widest text-red-600 text-center mb-10">COMO FUNCIONA</h2>
      <ol className="grid gap-10 sm:grid-cols-2 lg:grid-cols-4">
        {STEPS.map((s, i) => (
          <li key={s.title} className="text-center space-y-3">
            <PhoneFrame src={s.image} alt={s.alt} />
            <h3 className="font-bold text-neutral-200">{i + 1}. {s.title}</h3>
            <p className="text-neutral-500 text-sm leading-relaxed max-w-xs mx-auto">{s.text}</p>
          </li>
        ))}
      </ol>
    </section>
  )
}
```

- [ ] **Step 3:** Reescrever `src/app/page.tsx`: hero (logo, `h1` LOBINHO, promessa "O mestre de Werewolf no seu bolso", linha de apoio, botão **Começar** → `/caderneta`, `InstallButton`), `<HowItWorks />`, seção "Por que usar" (3 cartões: "Um celular só, sem conta"; "Mais de 40 papéis, com termômetro de equilíbrio"; "Noite organizada, conexões anotadas"), chamada final com **Começar**, rodapé com `SupportFooter` e o link sublinhado "Jogar online (criar ou entrar em uma sala)" → `/online`. Adicionar `export const metadata = { title: 'Lobinho — o mestre de Werewolf no seu bolso', description: '...' }`.
- [ ] **Step 4:** `npx tsc --noEmit` (esperado: sem erros) e `npm test` (esperado: 41 passando).
- [ ] **Step 5:** Commit: `git add src && git commit -m "feat: landing page with 4-step tutorial"`.

### Task 3: PWA, verificação e docs

**Files:**
- Modify: `public/manifest.json`, `public/site.webmanifest` (`"start_url": "/caderneta"`)
- Modify: `docs/architecture.md`

- [ ] **Step 1:** Trocar `start_url` nos dois manifests para `/caderneta`.
- [ ] **Step 2:** Build de produção + Chrome: `/` em 390 px e em desktop sem rolagem horizontal; prints carregam; **Começar** → `/caderneta`; link online → `/online`; `/manifest.json` com o novo `start_url`.
- [ ] **Step 3:** Entrada em `docs/architecture.md` (landing, `start_url`, prints como dependência da UI, arquivos tocados).
- [ ] **Step 4:** Commit + push: `git add -A && git commit -m "feat: PWA opens on /caderneta; docs for the landing" && git push`.
