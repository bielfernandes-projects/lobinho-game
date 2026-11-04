# Landing page + tutorial rápido — Design

Data: 2026-11-04 · Status: aguardando revisão

## Objetivo

Quem não conhece o app (chega por link de amigo, rede social ou indicação) entende em segundos o que é, vê como funciona e toca em **Começar**. O tutorial rápido é a seção "Como funciona" da própria landing, em 4 passos com prints reais. Não há tour dentro do app.

## Decisões já tomadas

- A landing vira a página `/`. O app (Caderneta do Mestre) continua em `/caderneta`, sem mudanças.
- Página única de rolagem, estática, em PT-BR. Sem dependência nova e sem animação de rolagem.
- O tutorial usa **prints reais** do app em molduras de celular.
- O modo online continua escondido: só o link discreto sublinhado no rodapé (`/online`).
- O manifest do PWA passa a abrir em `/caderneta` (`start_url`), para o app instalado pular a landing.

## Estrutura da página

1. **Hero**: logo, título "LOBINHO" (Bebas Neue), promessa curta ("O mestre de Werewolf no seu bolso"), uma linha de apoio, botão grande **Começar** (`/caderneta`) e o `InstallButton` existente.
2. **Como funciona** (4 passos, cada um com título curto, 1–2 frases e um print):
   1. Monte a mesa: nomes dos jogadores e cenário (tela de montagem).
   2. Passe o celular: cada um segura a carta para ver o próprio papel (tela "Vez de NOME").
   3. Conduza a noite: ordem de acordar e anotações de quem foi escolhido (painel da noite).
   4. Veja quem venceu: o app conta os vivos e avisa o vencedor (banner de vitória).
3. **Por que usar** (3 cartões): um celular só e sem conta; mais de 40 papéis com termômetro de equilíbrio do cenário; noite organizada e conexões anotadas por você.
4. **Chamada final**: repete o botão **Começar**.
5. **Rodapé**: `SupportFooter` ("Ajude o Dev") e o link "Jogar online (criar ou entrar em uma sala)".

## Componentes e arquivos

- `src/app/page.tsx`: reescrito como a landing (componente de servidor, sem estado). Hoje é a home enxuta; o conteúdo atual (logo, botão, instalar, apoio, link online) é reaproveitado.
- `src/components/landing/phone-frame.tsx`: moldura de celular (borda arredondada + `next/image`), usada nos 4 passos. Uma responsabilidade: enquadrar um print.
- `src/components/landing/how-it-works.tsx`: lista dos 4 passos (array local de `{ title, text, image, alt }`).
- `public/landing/passo-1.png` … `passo-4.png`: prints reais.
- `public/manifest.json` e `public/site.webmanifest`: `start_url` de `/` para `/caderneta`.
- `docs/architecture.md`: entrada nova.

## Prints

- Gerados do app em **build de produção** (`next build` + `next start`; o `next dev` entra em loop de HMR neste ambiente com OneDrive), pelo Chrome em viewport 390×844.
- Partida de exemplo com nomes fictícios e cenário equilibrado (ex.: 8 jogadores com Vidente, Bruxa, Cupido, 2 Lobos…).
- Telas: montagem (com nomes + cartas), "Vez de NOME" com a carta de costas, painel da noite 1 com as dicas de anotação, banner de vitória.
- Salvos como PNG otimizados (largura 390–780 px) e carregados com `next/image` (`sizes` pequeno, `loading="lazy"` abaixo da dobra).
- Os prints envelhecem se a UI mudar: ficam registrados em `docs/architecture.md` como dependência da landing.

## Visual e tom

- Identidade existente: fundo `midnight`, vermelho `primary`, `font-display` (Bebas Neue), tokens em `globals.css`; texto no tom do `docs/brand-guidelines.md` (sinistro, direto, divertido, claro).
- Mobile primeiro (a maioria chega por celular); em telas largas, os 4 passos viram grade de 2×2 ou 4 colunas com `max-w` contido.
- Acessibilidade básica: um `h1`, `h2` por seção, `alt` descritivo nos prints, contraste AA nos textos, botões com área de toque grande.
- Metadados: `title` e `description` da página atualizados para a proposta de valor (sem mexer no resto do `layout.tsx`).

## Fora de escopo

- Tour guiado dentro da Caderneta.
- Seções de papéis/FAQ, depoimentos, vídeo, analytics, i18n.
- Mudanças no app, no banco ou no modo online.

## Verificação

- `npx tsc --noEmit` e `npm test` continuam passando (não há lógica nova).
- No Chrome, em build de produção: `/` em 390 px e em desktop sem rolagem horizontal; **Começar** leva a `/caderneta`; o link online leva a `/online`; prints carregam; `manifest.json` tem `start_url` `/caderneta`.
- Sem teste unitário novo (conteúdo estático); a checagem é visual.

## Riscos

- **PWA já instalado**: o `start_url` só é relido quando o navegador atualiza o manifest; quem já instalou pode continuar abrindo em `/` por um tempo. Aceitável: a landing tem o botão **Começar** logo no topo.
- **Prints desatualizados** quando a UI mudar: refazer manualmente (4 imagens).
