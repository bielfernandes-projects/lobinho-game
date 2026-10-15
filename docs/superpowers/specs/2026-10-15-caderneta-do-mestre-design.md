# Caderneta do Mestre — Design

Trello: https://trello.com/c/DVFdnxOW/57-criar-um-hub-de-mestre ("Criar um Hub de Mestre", etiqueta Lobinho)
Data: 2026-10-15

## Objetivo

Um modo de jogo em que **só o celular do mestre é usado**. O app sorteia e entrega as cartas passando o celular de mão em mão, e depois vira a "caderneta" do mestre (ordem de despertar, vivos/mortos, anotações, cronômetro, strikes). A votação de linchamento é na mão (para cima/para baixo), como no jogo físico.

Esse modo passa a ser o **principal** da home. O jogo online (sala + PIN, cada um no seu celular) continua, como opção secundária.

## Fora de escopo (decisões já tomadas)

- "Hub de Mestre" para cartas físicas (o mestre anotar cartas que não estão no app): **descartado**, é feature desperdiçada.
- O nome "Impostor" **não aparece em nenhum lugar do app**. O modo se chama **Caderneta do Mestre**.
- Nada de Supabase, sala, PIN, conta ou migração nesse modo.
- O app **não resolve a noite**: não aplica proteção, poção, mortes em cadeia, caçador etc. O mestre registra o que aconteceu.
- ~~O app não declara vencedor~~ **Revisado depois do primeiro teste:** o app mostra um banner de vitória pela contagem dos vivos (espelho de `compute_winner`, em `src/lib/caderneta/winner.ts`); o jogo não acaba sozinho, o mestre decide encerrar. O cronômetro do dia é "Tempo da manhã" com 5 min por padrão.
- Não registra votos do tribunal.
- Nenhuma regra do jogo muda; é uma ferramenta de apoio. (`game_rules.md` só ganhou, na seção 13.4, o aviso de manter `winner.ts` em sincronia com `compute_winner`.)

## Mudança incluída: barra de pontuação fixa no construtor de cenário

O "termômetro" (Equilibrado / Vantagem da Aldeia / Vantagem dos Lobos + barra + soma de pontos) hoje rola junto com a página. Ele passa a ficar **fixo no topo da tela durante a rolagem**, para o mestre ver o equilíbrio enquanto escolhe as cartas.

- `position: sticky`, `top: env(safe-area-inset-top, 0px)`, `z-10`, fundo opaco (`bg-neutral-950`) para as cartas não aparecerem por trás, borda inferior sutil.
- Vale para o construtor online **e** para a montagem da Caderneta (os dois usam o mesmo componente, ver abaixo).
- Verificar na implementação que nenhum ancestral tem `overflow` que quebre o `sticky` (lobby `src/app/lobby/[id]/page.tsx`).
- Opcional, fácil de tirar: mostrar também `Cartas: x/N` dentro da barra fixa. Fica de fora a menos que você peça.

## Refactor necessário: `ScenarioCardPicker`

`ScenarioBuilder` hoje mistura a UI de escolher cartas com o Supabase (`roomId`, `start_game`, `rooms.update`). A Caderneta precisa da mesma UI de escolha. Em vez de duplicar ~250 linhas, extraio a parte de UI:

**`src/components/scenario-card-picker.tsx`** (novo, sem Supabase):
- Props: `playerCount`, `counts`, `onChange(counts)`, `drunkHidden`, `onDrunkHiddenChange`.
- Contém: termômetro **fixo**, botão "Resetar Cenário", lista agrupada por time (Vila, Lobos, Independentes) com +/− e ⓘ (`RoleInfoModal`), linha "Cartas: x/N", seletor do papel oculto do Bêbado (só aparece com `drunk > 0`).
- Persistência do `counts` fica no pai (hook `useScenarioCounts(storage)` em `src/hooks/`). **Revisado:** o modo online segue lembrando o último cenário (`localStorage`, `lobinho_last_scenario`); a Caderneta usa `sessionStorage` (`lobinho:caderneta:scenario`) e esquece ao fechar.

**`ScenarioBuilder`** (existente) passa a renderizar: blocos online (modo de revelação, Variante Fantasma) + `ScenarioCardPicker` + botão "Iniciar Jogo" (com `handleStart` igual ao de hoje). Comportamento online inalterado, só a barra fica fixa.

**`DRUNK_ALLOWED`** sai de `scenario-builder.tsx` para `src/lib/cards.ts` (exportado), para a Caderneta usar a mesma lista.

Isso desvia da abordagem "A pura" que combinamos (que não tocaria o online), mas é o menor jeito de não duplicar a UI e ainda entregar a barra fixa nos dois lugares. O risco no online é baixo: é extração sem mudança de lógica.

## Rota e home

- Nova rota `src/app/caderneta/page.tsx` (client component).
- `src/app/page.tsx`: botão principal grande **"Caderneta do Mestre"** (`router.push('/caderneta')`) com a frase: *"Um celular só, o mestre conduz. Cada jogador vê a própria carta sem precisar de conta."* Os campos de nome/PIN e os botões "Criar Sala" / "Entrar" descem para uma seção secundária "Jogar online, cada um no seu celular". Lógica online inalterada.
- Visual conforme `docs/brand-guidelines.md` (tokens `primary`, `midnight`, `surface`, Bebas Neue nos títulos, voz Sinistro/Direto/Divertido/Claro).

## Fluxo

`setup` → `deal` → `play` (e `ended`).

### 1. Montar (`setup`)
- Lista de jogadores: o mestre digita os nomes (um por vez, com remover). Nomes não vazios, únicos (ignorando maiúsculas), até 30 caracteres. O mestre não é jogador.
- `ScenarioCardPicker` com `playerCount` = nº de nomes.
- Botão **"Sortear e entregar cartas"** habilitado só se `totalCards === playerCount` e `6 ≤ playerCount ≤ 77` (mesma regra do online).
- Sorteio: embaralhamento Fisher-Yates das cartas (cada `id` repetido `count` vezes) atribuídas na ordem da lista. Se houver Bêbado, a carta reserva é a escolhida ou sorteada de `DRUNK_ALLOWED` (não conta como jogador).

### 2. Entregar cartas (`deal`)
Para cada jogador, na ordem da lista:
1. **Tela neutra:** "Passe o celular para *Nome*" + botão "Estou com o celular".
2. **Ver carta:** botão **"Segure para ver sua carta"**. Enquanto pressionado mostra o nome do papel e a descrição (`CARD_CATALOG`, **sem pontos**, como o `FlipCard`). Ao soltar, esconde na hora.
3. Depois de ter visto ao menos uma vez, aparece "Próximo". Última pessoa: "Devolver ao mestre".

Detalhes anti-espiada: bloquear o menu de contexto/callout do iOS no botão (mesmo tratamento do `FlipCard`: `onContextMenu` preventDefault, `[-webkit-touch-callout:none]`, `select-none`), esconder também no `pointercancel`/`visibilitychange`, e a tela neutra nunca mostra o papel.

Antes de entregar para o primeiro jogador há um "Refazer sorteio" (volta ao `setup` com o cenário preservado). Depois que a entrega começa, só dá para cancelar a partida inteira (volta ao `setup`).

### 3. Painel (`play`)
Duas visões, alternadas pelo botão de transição: **Noite** e **Dia**. Em cima, sempre: "Noite N" / "Dia N", total de vivos e a linha informativa lobos x demais.

**Lista de jogadores** (sempre visível, recolhível):
- Nome, carta (o mestre vê todas, com a cor de `ROLE_STYLE`), alternador **vivo/morto**.
- **Etiquetas fixas** (liga/desliga): alma gêmea, protegido, culto, varíola, abençoado, companheiro.
- **Nota livre** curta (até 140 caracteres).
- **"Trocar papel"**: seleciona qualquer carta do catálogo. Cobre Amaldiçoado convertido, infecção do Alfa, Doppelgänger, Escudeiro→Príncipe, Bêbado sóbrio etc. Mudar o papel recalcula a lista de despertar.

**Noite N:**
- Lista de despertar gerada por `NIGHT_STEPS`/`stepIsAvailable(step, turn, rolesInGame)`, na ordem de `NIGHT_STEPS`. `rolesInGame` = papéis atuais de **todos** os jogadores, vivos ou mortos (como no online, em que o mestre pode "acordar" mortos para disfarçar).
- Cada passo mostra o label, os nomes de quem tem o papel (e se está morto), e o botão "Feito". O primeiro não feito fica destacado (mesma lógica de `nextStepToWake`, com `acted` = passos marcados e `nightStep` vazio).
- O passo `wolves` não depende de resolução: é um passo comum, "feito" pelo mestre.
- Passo do **Bêbado** (3ª noite): mostra "Papel oculto: *X*" e o botão "Revelar e trocar papel" (aplica `setRole`).
- Botão **"Amanhecer"** (habilitado após todos os passos feitos, ou a qualquer momento com confirmação) passa para o Dia, mantendo `turn`.

**Dia N:**
- `VoteTimerPanel` (já independente de Supabase) para o cronômetro de debate.
- **Strikes** locais 0–3 por jogador vivo (+/−). No 3º strike abre confirmação "Eliminar *Nome*?"; confirmar marca como morto.
- Botão **"Anoitecer"** → `turn + 1`, `doneSteps` vazio, visão Noite.

**Encerrar partida:** botão no menu do painel (com confirmação) → tela final com o papel de todos, o banner do vencedor (se houver) e "Nova partida".

Fora do painel nada é bloqueado: o mestre pode marcar vivo/morto, etiquetas e trocar papel a qualquer hora.

## Estado local

Arquivo `src/lib/caderneta/state.ts` (TypeScript puro, **sem imports com alias `@/`**, para rodar em teste direto no Node; usa imports relativos):

```ts
type Phase = 'setup' | 'deal' | 'play' | 'ended'
type Tag = 'soulmate' | 'protected' | 'cult' | 'pox' | 'blessed' | 'companion'

interface CadernetaPlayer {
  id: string
  name: string
  role: string            // id de CARD_CATALOG
  alive: boolean
  tags: Tag[]
  note: string
  strikes: number         // 0..3
}

interface CadernetaState {
  v: 1
  phase: Phase
  names: string[]                       // fase setup
  players: CadernetaPlayer[]            // após o sorteio
  drunkHiddenRole: string | null
  dealIndex: number
  view: 'night' | 'day'
  turn: number                          // noite/dia N, começa em 1
  doneSteps: string[]
}
```

Reducer puro com ações: `setNames`, `deal` (recebe o sorteio já pronto, para o reducer ficar determinístico e testável), `nextDeal`, `cancel`, `toggleAlive`, `toggleTag`, `setNote`, `setRole`, `markStepDone`, `toNight`, `toDay`, `addStrike`, `removeStrike`, `end`, `reset`.

Funções puras exportadas: `drawRoles(counts, names, rng)` (Fisher-Yates com `rng` injetável), `rolesInGame(state)`, `aliveCounts(state)`.

Persistência: hook `useCaderneta()` (`src/hooks/use-caderneta.ts`) com `useReducer`, hidratação de `sessionStorage` (`lobinho:caderneta:v1`) em `useEffect` (evita mismatch de SSR), gravação a cada mudança, tudo em `try/catch`. Estado inválido ou de outra versão é descartado. **Revisado:** a partida só vive enquanto a aba/app está aberto (recarregar mantém; fechar zera). "← Início" e 30 min sem mexer (só em `setup` e `ended`) apagam jogadores e cenário e voltam para a home. "Nova partida" na tela final volta à montagem **mantendo** jogadores e cenário.

## Componentes novos

| Arquivo | Papel |
|---|---|
| `src/app/caderneta/page.tsx` | Rota; escolhe a tela pela `phase` |
| `src/components/caderneta/setup-screen.tsx` | Nomes + `ScenarioCardPicker` + sorteio |
| `src/components/caderneta/players-list.tsx` | Lista de jogadores do painel (vivo/morto, etiquetas, nota, trocar papel) |
| `src/lib/scenario.ts` | Contas puras do cenário (contagem, pontos, equilíbrio, validação) |
| `src/components/caderneta/deal-screen.tsx` | Passa-o-celular + segurar para ver |
| `src/components/caderneta/play-panel.tsx` | Cabeçalho, lista de jogadores, alternância Noite/Dia |
| `src/components/caderneta/night-steps-list.tsx` | Lista de despertar |
| `src/components/caderneta/day-tools.tsx` | Cronômetro + strikes |
| `src/components/caderneta/end-screen.tsx` | Papéis finais |
| `src/components/scenario-card-picker.tsx` | UI de cartas + termômetro fixo (compartilhado) |
| `src/hooks/use-caderneta.ts`, `src/hooks/use-scenario-counts.ts` | Estado/persistência |
| `src/lib/caderneta/state.ts` | Reducer e funções puras |

`StrikePanel` (online) não é reutilizado (está preso ao Supabase). O strike local é um bloco pequeno dentro de `day-tools.tsx`.

## Erros e casos de borda

- `sessionStorage` indisponível ou corrompido: o modo funciona em memória e começa em `setup`.
- Recarregar durante a entrega: volta no mesmo `dealIndex`, na tela neutra (nunca na carta aberta).
- Nome duplicado ou vazio: bloqueia o botão de sortear, com mensagem curta.
- Cenário sem Lobo ou sem Vidente: aviso não bloqueante (a regra 11.3 recomenda ao menos um de cada), o termômetro continua.
- Remover/adicionar jogador depois do sorteio não existe; para mudar, "Cancelar partida".

## Testes

Sem runner configurado hoje. Node 24 roda `.ts` direto, então: `node --test src/lib/caderneta/state.test.ts` (módulo `node:test`, sem dependência nova), registrado como script `"test": "node --test src/lib/caderneta/"` em `package.json`. Cobre:
- `drawRoles`: todas as cartas usadas exatamente uma vez, `rng` determinístico, Bêbado com reserva fora dos jogadores.
- Reducer: avanço setup→deal→play, `nextDeal` até o fim, `toDay`/`toNight` incrementando `turn`, strikes limitados a 0–3, `setRole`, `toggleTag` idempotente, estado inválido descartado.
- `rolesInGame` e a seleção de passos da noite (via `stepIsAvailable`) para as noites 1, 2 e 3 (Maçom/Cupido só na 1; Bruxa não na 1; Bêbado na 3).

Os componentes são verificados manualmente (sticky do termômetro, segurar-para-ver, refresh no meio da partida) em celular e `next build --webpack` + `eslint` nos arquivos tocados.

## Documentação e deploy

- Antes de commitar: entrada nova em `docs/architecture.md` (commit, motivo, arquivos). `game_rules.md` só ganha o aviso da seção 13.4 (espelho `winner.ts`).
- Sem migração de banco (a regra de `supabase db push` não se aplica).
- Commit + push; o deploy na Vercel é automático.
- Pré-voo da Supabase CLI (regra do AGENTS.md) não é necessário para esta mudança, já que não toca o banco.

## Pontos em aberto

Nenhum bloqueante. Ajustáveis na revisão: incluir `Cartas: x/N` na barra fixa; lista de etiquetas fixas; limite de 140 caracteres da nota.
