# Lobinho — Brand Guidelines v1.0

> **Last updated:** 2026-08-05
> **Status:** Live (implementado no app)
> **Source of truth:** este documento controla `assets/design-tokens.json` e `assets/design-tokens.css`.

---

## Quick Reference

| Element | Value |
|---------|-------|
| Nome | Lobinho — A Werewolf Game Based |
| Primary Color | #DC2626 Blood Red |
| Secondary Color | #CBD5E1 Moon Silver |
| Accent Color | #8B5CF6 Twilight Violet |
| Primary Font | Bebas Neue (display) + Geist (UI) |
| Voice | Sinistro, Direto, Divertido |

---

## 1. Brand Concept

### 1.1 O que é o Lobinho

O Lobinho é um **jogo de dedução social** estilo Werewolf (Lobisomem) jogado em **tempo real e multiplayer** como PWA. Um grupo de amigos (6 a 78 pessoas) cria uma sala com PIN, o host monta o cenário de papéis, e o clássico ciclo noite/dia roda com um sistema de **Tribunal** na fase diurna — tudo digital, sem narrador humano.

### 1.2 Posicionamento

> **Lobinho é o lobisomem de mesa sem papel e sem narrador.** Para amigos que querem jogar Werewolf a qualquer hora, em qualquer lugar, o Lobinho entrega a partida completa — cartas digitais, ações secretas noturnas e tribunal automático — na palma da mão, no celular ou no computador.

### 1.3 Missão

Levar a experiência de Werewolf para o mundo digital, removendo a fricção do jogo físico (cartas, narrador, contagem de votos) sem perder o coração do jogo: **blefe, leitura de pessoas e risadas à mesa**.

### 1.4 Visão

Um mundo onde qualquer roda de amigos joga Werewolf em 10 segundos de setup — sem impressão de cartas, sem dicionário de regras, sem ninguém "sabendo as regras".

### 1.5 Valor (Value Proposition)

Para grupos de amigos que querem jogar dedução social, o Lobinho é um jogo de Werewolf completo que **funciona sem narrador humano**: sorteiamento secreto de papéis, ações noturnas privadas, tribunal com votação automática e condições de vitória checadas pelo próprio sistema. Diferente de rodar no papel, o Lobinho **automatiza toda a mecânica** e ainda permite montar cenários customizados com dezenas de papéis oficiais.

### 1.6 Público

| Segmento | Dor | Mensagem | CTA |
|----------|-----|----------|-----|
| Grupos de amigos (6–78) | Querem jogar, mas ninguém quer narrar / aprender regras | "O narrador agora é o app." | Criar sala com PIN |
| Rodas de Werewolf de mesa | Jogo físico é lento e frágil | "Cartas, noite e tribunal em um só app." | Instalar o app |
| Fãs de social deduction | Cansados de setup e erros de conta | "O sistema conta os votos, declara o vencedor e nunca erra o limite." | Montar um cenário |

### 1.7 Elevator pitch

**10s:** O Lobinho é o jogo de lobisomem inteiro no celular — papéis secretos, noite com ação privada e tribunal com voto automático.

**30s:** Esquece papel e narrador. No Lobinho você cria uma sala, manda o PIN pros amigos, o host monta o cenário com os papéis que quiser e o jogo conduz tudo: sorteiamento, ações noturnas, mortes, votação e vitória. 6 a 78 jogadores, partida completa sem parar pra conferir regra.

---

## 2. Logo System

### 2.1 Mark (Primária)

O logo do Lobinho é um **"L" em Blood Red sobre um quadrado Midnight arredondado**.

- Fonte do "L": sugestão de desenho geométrico próprio (hastes retangulares com cantos arredondados) — **não** depende de fonte de sistema.
- Fundo: `#0A0A0A` (Midnight), cantos `rx` ≈ 12,5% do lado.
- Cor do "L": `#DC2626` (Blood Red).
- Fica consistente nos formatos: ícone do PWA (192/512 + maskable), favicon, tela inicial, cartas.

### 2.2 Variantes

| Variante | Uso |
|----------|-----|
| **Mark (ícone)** | Ícone do app, favicon, avatar, cartas. |
| **Wordmark** | "LOBINHO" em Bebas Neue, uppercase, tracking largo, Blood Red ou branco sobre fundo escuro. |
| **Lockup (opcional)** | Mark + wordmark lado a lado para telas de boas-vindas/sobre. |

### 2.3 Espaço de respiro

Mínimo de espaço limpo ao redor do mark = **altura da letra "L"**.

### 2.4 Tamanhos mínimos

| Contexto | Mínimo |
|----------|--------|
| Mark digital | 24px |
| Mark como ícone de app | 192px (asset), 24px (renderizado) |
| Wordmark | 80px de largura |

### 2.5 Don'ts

- Não distorcer, rotacionar ou inclinar.
- Não trocar a cor do "L" fora da paleta (Blood Red; em fundo escuro pode ser branco).
- Não adicionar sombras, gradientes ou brilhos fora dos drop-shadows padronizados de UI.
- Não recortar ou alterar proporções.
- Não colocar sobre fundos movimentados sem contraste.

### 2.6 Arquivos-fonte

- `public/icon-192x192.svg`, `public/icon-512x512.svg` — SVGs vetoriais do mark.
- `public/icon-192x192.png`, `public/icon-512x512.png`, `public/icon-maskable-*.png` — PNGs do PWA.

---

## 3. Color Palette

> O jogo roda em **tema escuro**. Blood Red sobre Midnight é a identidade; Moon Silver e Twilight Violet apoiam hierarquia e mistério.

### Primary Colors

| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| Blood Red | #DC2626 | rgb(220,38,38) | CTAs, wordmark, ícones de lobo, erros, destaque |
| Blood Red Dark | #991B1B | rgb(153,27,27) | Hover/active de ações primárias, bordas fortes |
| Blood Red Light | #F87171 | rgb(248,113,113) | Texto vermelho pequeno sobre fundo escuro, glows |

### Secondary Colors

| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| Moon Silver | #CBD5E1 | rgb(203,213,225) | Texto de destaque claro, ícones, toques de "noite gelada" |
| Moon Silver Dark | #64748B | rgb(100,116,139) | Bordas prata, texto secundário frio |
| Moon Silver Light | #F1F5F9 | rgb(241,245,249) | Títulos claros sobre dark |

### Accent Colors

| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| Twilight Violet | #8B5CF6 | rgb(139,92,246) | Time independente, papéis "especiais", mistério |
| Twilight Violet Dark | #7C3AED | rgb(124,58,237) | Hover do accent |
| Twilight Violet Light | #A78BFA | rgb(167,139,250) | Texto accent sobre fundo escuro |

### Neutral Palette

| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| Midnight | #0A0A0A | rgb(10,10,10) | Fundo de página |
| Surface | #171717 | rgb(23,23,23) | Cards, painéis |
| Surface Raised | #262626 | rgb(38,38,38) | Elementos elevados, modais |
| Border | #262626 | rgb(38,38,38) | Bordas, divisores (neutral-800) |
| Text Primary | #E5E5E5 | rgb(229,229,229) | Títulos e texto principal |
| Text Secondary | #A3A3A3 | rgb(163,163,163) | Subtítulos, legenda |
| Text Muted | #737373 | rgb(115,115,115) | Placeholder, texto desabilitado |

### Semantic Colors

| State | Hex | Usage |
|-------|-----|-------|
| Success | #22C55E | "Ninguém morreu", absolvição, positivo |
| Warning | #F59E0B | Avisos, fim de jogo, tempo acabando |
| Error / Danger | #DC2626 | Erros, mortes, ações destrutivas |
| Info | #3B82F6 | Informação neutra, time da vila |

### Team Colors (paleta de jogo)

| Team | Hex | Uso |
|------|-----|-----|
| Village (Aldeia) | #3B82F6 | Identificação de time vila |
| Wolf (Lobisomem) | #DC2626 | Identificação de time lobo |
| Independent | #8B5CF6 | Identificação de time independente |

Os chips de papel (`ROLE_STYLE` em `src/lib/cards.ts`) seguem essas famílias com tons 100/700 e bordas 300 — a paleta de roles NÃO muda com o tema.

### Accessibility

- `Text Primary #E5E5E5` sobre `Midnight #0A0A0A`: **~15:1** (AAA).
- `Moon Silver #CBD5E1` sobre `#0A0A0A`: **~11:1** (AAA).
- `Blood Red Light #F87171` sobre `#0A0A0A`: **~5,2:1** (AA) — usar para texto vermelho pequeno.
- Botão primário `#991B1B` + texto branco: **~6,5:1** (AA).
- `Blood Red #DC2626` sobre `#0A0A0A` (~4:1) — **só para texto grande/display** (AA large).
- Todos os elementos interativos devem atender WCAG 2.1 AA.

---

## 4. Typography

### 4.1 Font Stack

```css
--font-display: 'Bebas Neue', 'Geist', sans-serif;      /* wordmark, títulos de fase */
--font-sans: 'Geist', system-ui, -apple-system, sans-serif;  /* UI */
--font-mono: 'Geist Mono', ui-monospace, monospace;      /* PIN, timers, códigos */
```

- **Bebas Neue** (display, peso único 400): palavra-marca "LOBINHO", títulos de fase, números grandes de PIN. Uppercase + `tracking-widest`.
- **Geist** (UI): todo o corpo da interface, botões, listas, painéis.
- **Geist Mono** (mono): PIN da sala, contadores, timers.

### 4.2 Type Scale

| Element | Font | Weight | Size (Desktop/Mobile) | Line Height |
|---------|------|--------|----------------------|-------------|
| Wordmark | Bebas Neue | 400 | 72px / 48px | 0.9 |
| H1 (fase) | Bebas Neue | 400 | 40px / 32px | 0.95 |
| H2 (cartas) | Geist | 700 | 24px / 20px | 1.2 |
| H3 (painéis) | Geist | 600 | 18px / 16px | 1.3 |
| Body | Geist | 400 | 16px / 16px | 1.5 |
| Small | Geist | 400 | 14px / 14px | 1.5 |
| Caption | Geist | 400 | 12px / 12px | 1.4 |
| Mono (PIN) | Geist Mono | 700 | 30px / 30px | 1 |

### 4.3 Carregamento

Bebas Neue via `next/font/google` em `src/app/layout.tsx` (variável `--font-bebas-neue`). Geist e Geist Mono já são carregados via `next/font/google`.

### 4.4 Regras

- Wordmark/títulos de fase: **sempre** uppercase com tracking largo.
- Nunca usar Bebas Neue para parágrafos longos — display só.
- Corpo sempre em Geist, com a escala acima.

---

## 5. Voice & Tone

> Idioma padrão da interface: **pt-BR**. Nomes de papéis em inglês quando forem o nome oficial da carta (ex.: "Werewolf"), com tradução entre parênteses em tooltips.

### 5.1 Personalidade

| Traço | Descrição |
|-------|-----------|
| **Sinistro** | Brinca com o tema: a noite, a lua, o uivo. Mistério sem sangue de verdade. |
| **Direto** | Instruções acionáveis, sem rodeios. O jogador sempre sabe o que fazer. |
| **Divertido** | Leveza de festa. Risadas e suspense caminham juntos. |
| **Claro** | Zero jargão técnico. O tribunal e as regras se explicam sozinhos. |

### 5.2 Voice Chart

| Trait | We Are | We Are Not |
|-------|--------|------------|
| Sinistro | Dramático, atmosférico ("A lua está cheia...") | Gótico pesado, gore, assustador de verdade |
| Direto | "Escolha uma vítima", "Seu voto foi contado" | Vago, burocrático, técnico |
| Divertido | "O narrador agora é o app", "Vila em pânico" | Cringe, memes forçados, infantil |
| Claro | Regras e estados sempre visíveis | Jargão, siglas, "error 406" cru |

### 5.3 Tone by Context

| Contexto | Tom | Exemplo |
|----------|-----|---------|
| Boas-vindas / Marketing | Provocativo, convidativo | "A noite começa com um PIN." |
| Fase noturna | Suspense | "Os lobos estão acordados..." |
| Fase diurna / Tribunal | Sóbrio, formal-ritual | "A vila decide o destino do acusado." |
| Anúncio de morte | Sério, direto | "Ninguém acordou esta manhã." |
| Sucesso | Breve, celebrado | "Ninguém morreu — a vila respira." |
| Erro | Calmo, orientado a solução | "Não deu para conectar. Tente de novo." |
| Erro de RPC | Curto, sem detalhe técnico | "Algo deu errado. O host tenta de novo." |
| Aviso | Curto, urgente | "Tempo esgotado!" |
| Expulsão | Firme, sem drama | "Você foi removido da sala." |

### 5.4 Termos proibidos

| Evitar | Por quê |
|--------|---------|
| "Revolucionário", "Melhor do mundo" | Exagero de marketing, sem prova |
| "Seamless", "synergy", "alavancar" | Jargão corporativo |
| "Erro 406", códigos de erro crus | Quebra o tom; o app nunca deve exibir erro técnico ao jogador |
| Gore / violência gráfica em texto | Jogo de festa, não filme de terror |
| Gíria datada ("zika", "mó dahora") | Envelhece mal e quebra a neutralidade |

### 5.5 Sample Rewrites

| Antes (genérico) | Depois (Lobinho) |
|------------------|------------------|
| "Ocorreu um erro ao criar a sala" | "A lua não alinhou. Tente criar a sala de novo." |
| "Aguardando..." | "A noite está calma... aguardando os lobos." |
| "Vitória!" | "🏁 Os lobos venceram — a vila não resistiu." |

> Regra prática: se uma frase parecer que poderia sair de um sistema de banco, ela precisa ser reescrita para o tom do Lobinho. **Suspense nas transições, clareza nas ações.**

---

## 6. Imagery & Iconography

### 6.1 Estilo de arte

- **Tema:** noite de lua cheia, floresta escura, atmosfera de suspense suave.
- **Tratamento:** fotografia/arte com paleta escura (Midnight) e acento Blood Red (lua, olhos, sangue de tinta).
- **Mood:** místico, dramático, mas limpo — nunca aterrorizante nem gore.
- **Ilustrações:** silhuetas geométricas (lobo, lua, floresta), cantos arredondados, formas faceted como nas fases de exploração de logo.
- **Fundos:** gradientes radiais de `#161622 → #0c0c14 → #070709` (ex.: cartão de noite) ou papel quente claro para materiais de impressão.

### 6.2 Iconografia atual (emoji)

O jogo usa **emojis como ícones** em papéis, fases e ações (🐺 🌙 🔮 ⚖️ ☠️). Regras:

- Um emoji por elemento, sem combos.
- Emoji consistente com a família de cor do elemento (ex.: time lobo usa vermelho, time vila usa azul).
- Papéis têm emoji fixo em `ROLE_LABEL` — **não mudar sem mudar em todos os lugares** (catálogo, painéis, log do host, tooltips).

### 6.3 Futuro (ícones SVG)

Se forem introduzidos ícones vetoriais: linha fina (stroke 1,5–2px), cantos 2–4px, **outline** em Moon Silver com variante preenchida em Blood Red. Base 24px.

---

## 7. Design Components

> Specs dark-theme. Classes Tailwind usadas hoje já são a implementação; estes tokens são a referência.

### 7.1 Buttons

| Type | Background | Text | Radius |
|------|------------|------|--------|
| Primary | `#991B1B` (red-700), hover `#b91c1c` | Branco | rounded-xl/2xl |
| Secondary | Transparente, borda red-700 | red-400/500 | rounded-xl |
| Ghost | Transparente, borda neutral-800 | neutral-500, hover neutral-400 | rounded-xl |

### 7.2 Cards / Painéis

- Fundo: `Surface #171717` ou `bg-neutral-900`; sobrepondo, `bg-neutral-950/90`.
- Borda: `neutral-800`, raio `rounded-xl`/`rounded-2xl`.
- Elevação: `shadow-lg shadow-black/40`, sem blur excessivo.

### 7.3 Inputs

- Fundo `neutral-900`, borda `neutral-800`.
- Foco: `ring-2 ring-red-700 border-red-800` (voz do brand: o vermelho marca interação).
- Placeholder: `neutral-600`.

### 7.4 Estados semânticos

- Success: verde `#22C55E` + `🌅/✔️`.
- Warning: amarelo `#F59E0B`.
- Error: vermelho `#DC2626`/`#F87171` com instrução de retry.
- Timer esgotado: red-600 pulsante com glow `rgba(220,38,38,0.6)`.

### 7.5 Spacing

| Token | Valor | Uso |
|-------|-------|-----|
| xs | 4px | Espaços internos |
| sm | 8px | Elementos compactos |
| md | 16px | Padrão |
| lg | 24px | Seções |
| xl | 32px | Gaps grandes |
| 2xl | 48px | Divisores de seção |

---

## 8. AI Image Generation

### 8.1 Base prompt

Sempre prefixar prompts de geração de imagem com:

```
A dark werewolf party-game atmosphere: deep midnight black (#0A0A0A) background,
a full blood-red moon (#DC2626), soft cinematic moonlight, subtle film grain,
clean geometric silhouettes of a wolf. Moody, mysterious and playful — never
gory or horror-graphic. Brand colors: #DC2626 red, #CBD5E1 silver, #0A0A0A black.
```

### 8.2 Style keywords

| Categoria | Keywords |
|-----------|----------|
| **Lighting** | full-moon glow, cinematic backlight, soft vignette |
| **Mood** | mysterious, suspenseful, playful dread |
| **Composition** | centered mark, rule of thirds on moon, clean negative space |
| **Treatment** | high contrast, desaturated blacks, single red accent |
| **Aesthetic** | modern, minimal, geometric, editorial |

### 8.3 Mood descriptors

- Lua cheia vermelha sobre preto profundo
- Silhueta de lobo em contra-luz
- Neblina fria e prata (Moon Silver)
- Vinheta de filme com grão sutil

### 8.4 Visual don'ts

| Evitar | Motivo |
|--------|--------|
| Sangue em excesso / gore | Foge do tom de festa |
| Cores fora da paleta | Quebra identidade |
| Excesso de detalhes | Perde legibilidade no app |

### 8.5 Example prompts

**Hero / capa:**
```
Full-moon night: a huge blood-red (#DC2626) moon over a black forest silhouette,
thin silver fog (#CBD5E1), cinematic backlight, subtle film grain. Minimal,
geometric, modern. A werewolf party game key art. No text.
```

**Social post:**
```
Tight close-up of the Lobinho "L" mark — red (#DC2626) on midnight black
(#0A0A0A) rounded square — with a faint red moon glow behind. Clean, centered,
high contrast, minimal. No text.
```

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-08-05 | Versão inicial. Conceito, posicionamento, logo ("L" red), paleta (Blood Red / Moon Silver / Twilight Violet), tipografia (Bebas Neue + Geist), voz/tom pt-BR, componentes, prompt pack de imagem. |
