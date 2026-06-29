# Lobinho — A Werewolf Game Based

Jogo de dedução social multiplayer em tempo real, estilo Werewolf (Mafia), construído como **PWA** com **Next.js (App Router)** + **Supabase** + **Tailwind CSS** + **Framer Motion**.

---

## Índice

1. [Arquitetura](#1-arquitetura)
2. [Stack](#2-stack)
3. [Estrutura do Projeto](#3-estrutura-do-projeto)
4. [Fluxo do Jogo](#4-fluxo-do-jogo)
5. [Papéis (Roles)](#5-papéis-roles)
6. [Banco de Dados (Supabase)](#6-banco-de-dados-supabase)
7. [Migrações SQL](#7-migrações-sql)
8. [Componentes](#8-componentes)
9. [Hooks](#9-hooks)
10. [Timer](#10-timer)
11. [Segurança (RLS)](#11-segurança-rls)
12. [Deploy](#12-deploy)
13. [Desenvolvimento Local](#13-desenvolvimento-local)

---

## 1. Arquitetura

```
┌─────────────────┐     ┌──────────────┐     ┌────────────┐
│   Next.js PWA   │ ◄──► │   Supabase   │ ◄──► │  PostgreSQL │
│  (React + RSC)  │     │  (Realtime)   │     │  + RLS      │
└─────────────────┘     └──────────────┘     └────────────┘
```

- **Front-end**: React Server Components + Client Components. Toda lógica de jogo roda no cliente com estado sincronizado via Realtime.
- **Back-end**: Supabase como BaaS — auth anônima, banco PostgreSQL, Realtime subscriptions, RLS policies.
- **Sem servidor próprio**: Nenhuma API customizada; toda mutação é feita via RPC (Stored Procedures) no PostgreSQL.

---

## 2. Stack

| Camada         | Tecnologia                                  |
|----------------|---------------------------------------------|
| Framework      | Next.js 16 (App Router, Turbopack)          |
| Linguagem      | TypeScript (strict)                         |
| Estilização    | Tailwind CSS v4                             |
| Animação       | Framer Motion                               |
| Banco de Dados | Supabase (PostgreSQL)                       |
| Auth           | Supabase Anonymous Auth                     |
| Realtime       | Supabase Realtime (change data capture)     |
| ORM            | Supabase JS Client (lightweight)            |

---

## 3. Estrutura do Projeto

```
src/
├── app/
│   ├── layout.tsx          # Root layout (metadata, providers)
│   ├── page.tsx            # Tela de entrada (criar/entrar sala)
│   ├── globals.css         # Estilos globais Tailwind
│   ├── lobby/
│   │   └── [id]/
│   │       └── page.tsx    # Sala de espera (players, iniciar)
│   └── game/
│       └── [id]/
│           └── page.tsx    # Tela principal do jogo (phase-switch)
├── components/
│   ├── supabase-provider.tsx    # Provider do cliente Supabase
│   ├── reconnection-modal.tsx   # Modal de reconexão (3s debounce)
│   ├── flip-card.tsx            # Carta 3D press-and-hold
│   ├── player-list.tsx          # Lista de jogadores
│   ├── host-controls.tsx        # Botões de avanço do host
│   ├── night-phase.tsx          # Container da fase noturna
│   ├── werewolf-panel.tsx       # Ação do lobisomem
│   ├── seer-panel.tsx           # Ação da vidente
│   ├── witch-panel.tsx          # Ação da bruxa
│   ├── day-announcement.tsx     # Anúncio matinal (mortos)
│   ├── voting-panel.tsx         # Painel de votação
│   ├── timer-display.tsx        # Timer MM:SS com sincronia
│   └── host-timer-controls.tsx  # Controles do timer (host)
├── hooks/
│   ├── use-player.ts        # Hook do jogador atual
│   └── use-room.ts          # Hooks de sala/jogadores/game state
└── lib/
    ├── supabase/
    │   └── client.ts        # Cliente Supabase browser
    └── sql/
        ├── migration-002.sql
        ├── migration-003.sql
        ├── migration-004.sql
        └── migration-005.sql
```

---

## 4. Fluxo do Jogo

```
Entry → Lobby → Card Reveal → Night → Day → Vote → (repete ou fim)
```

### Fases em detalhe

1. **Entry** (`/`): Jogador cria sala (gera PIN de 4 dígitos) ou entra com PIN existente. Auth anônima automática.
2. **Lobby** (`/lobby/[id]`): Lista de jogadores com Presença (quem está online). Host vê botão "Iniciar Jogo".
3. **Card Reveal**: Cada jogador vê uma carta 3D com o logotipo. Deve pressionar e segurar por 3s para revelar seu papel secreto. A carta gira com `rotateY(180deg)` e `backface-visibility: hidden`.
4. **Night**: Subturnos:
   - Lobisomens escolhem vítima (maioria define)
   - Vidente investiga um jogador (resultado booleano imediato)
   - Bruxa decide usar poção da vida (salvar vítima dos lobos) e/ou poção da morte (envenenar alguém)
   - Host avança em 2 passos: `resolve_night_wolves` → (bruxa age) → `resolve_night`
5. **Day**: Anúncio de quem morreu (ou "Ninguém morreu"). Timer de discussão (host controla).
6. **Vote**: Jogadores votam em quem eliminar. Maioria absoluta (floor(vivos/2)+1) para linhçar. Empate = ninguém morre. Resultado fica visível durante a noite seguinte.
7. **Endgame**: Checado automaticamente via trigger após cada morte. Vitória dos lobisomens ou dos aldeões.

### Ciclo de host

O host (quem criou a sala) é o **único** que avança as fases. O botão `HostControls` muda dinamicamente conforme a fase:

| Fase         | Modo                  | RPC chamado         |
|--------------|-----------------------|---------------------|
| card_reveal  | `start`               | `start_game`        |
| night        | `resolve_night_wolves`| `resolve_night_wolves` |
| night (após) | `resolve_night`       | `resolve_night`     |
| day          | `advance`             | `advance_phase`     |
| vote         | `resolve_vote`        | `resolve_day_vote`  |

---

## 5. Papéis (Roles)

| Papel       | Ação na Noite                                    | Quantidade (padrão 8) |
|-------------|--------------------------------------------------|----------------------|
| 🐺 Werewolf | Escolher uma vítima (maioria dos votos dos lobos) | 2                    |
| 🔮 Seer     | Investigar um jogador (sabe se é lobo ou não)    | 1                    |
| 🧙 Witch    | Salvar vítima dos lobos e/ou envenenar alguém    | 1                    |
| 🌿 Villager | Nenhuma ação noturna, vota durante o dia         | 4                    |

A distribuição é definida pela RPC `start_game` na migration 002.

---

## 6. Banco de Dados (Supabase)

### Tabelas

| Tabela         | Descrição                                      |
|----------------|------------------------------------------------|
| `rooms`        | Salas (PIN, status, host_id, max_players)      |
| `players`      | Jogadores (room_id, user_id, role, is_alive)   |
| `game_state`   | Estado do jogo (current_phase, turn_index, timer) |
| `night_actions`| Ações noturnas (tipo, alvo, turno)             |
| `votes`        | Votos diurnos (voter, target, turno)           |
| `player_profiles` | View para consulta pública (sem role)       |

### Views

- `player_profiles`: Projeção segura de `players` sem o campo `role`.

### RPCs (Stored Procedures)

| RPC                  | Função                                            |
|----------------------|---------------------------------------------------|
| `start_game`         | Distribui papéis, cria `game_state`, seta `card_reveal` |
| `advance_phase`      | Avança `card_reveal→night` e `day→vote`           |
| `submit_night_action`| Registra ação noturna (valida papel + está vivo) |
| `resolve_night_wolves`| Fecha votação dos lobos, salva alvo, seta `wolves_resolved=true` |
| `resolve_night`      | Aplica mortes (lobo + veneno), avança para `day` |
| `resolve_day_vote`   | Conta votos, aplica lynch ou tie, avança para `night` |
| `check_game_over`    | Verifica condição de vitória, atualiza `rooms.status` |
| `get_player_roles`   | Retorna papel do jogador (apenas para ele mesmo) |
| `get_werewolf_teammates` | Retorna colegas lobisomens (apenas lobos)    |
| `start_timer`        | Inicia timer com duração definida pelo host      |
| `pause_timer`        | Pausa timer (congela `timer_remaining`)          |
| `resume_timer`       | Retoma timer (reatualiza `timer_started_at`)     |
| `reset_timer`        | Zera timer (remove todas as colunas de timer)    |

---

## 7. Migrações SQL

Todas as migrações estão em `src/lib/sql/`. **Execute em ordem**:

### Migration 002
- Adiciona `has_viewed_card` em `players`
- RPCs: `start_game`, `advance_phase`, `get_player_roles`
- Habilita Realtime para `players`, `game_state`

### Migration 003
- Tabelas: `night_actions`, `votes`
- RPCs: `submit_night_action`, `resolve_night`, `resolve_day_vote`, `check_game_over`
- Atualiza `start_game` para iniciar em `card_reveal`
- RLS nas novas tabelas

### Migration 004
- Bruxa: colunas `has_used_life_potion`, `has_used_death_potion` em `players`
- Colunas `wolves_resolved`, `last_vote_result` em `game_state`
- RPC: `resolve_night_wolves`
- Atualiza `submit_night_action`, `resolve_night`, `resolve_day_vote`
- Trigger `trg_check_game_over` em `players.is_alive`
- Estados de fim: `finished_villagers_win`, `finished_wolves_win`
- Tratamento de empate em votação

### Migration 005
- Timer: colunas `timer_duration`, `timer_remaining`, `is_timer_running`, `timer_started_at`
- RPCs: `start_timer`, `pause_timer`, `resume_timer`, `reset_timer`
- RLS nas RPCs (host-only + bounds check)

---

## 8. Componentes

### `supabase-provider.tsx`
Provider React que cria o cliente Supabase browser e o disponibiliza via contexto.

### `reconnection-modal.tsx`
Monitora o estado de conexão do Supabase Realtime. Se ficar desconectado por mais de 3 segundos, exibe modal "Reconectando..." com spinner. Quando reconecta, o modal some automaticamente.

### `flip-card.tsx`
Carta 3D com `perspective` e `rotateY`. Frente: logotipo "Lobinho" com `?`. Verso: papel do jogador + nome. Ativa via press-and-hold (touch) ou click-and-hold (mouse) por 3 segundos com indicador de progresso circular.

### `player-list.tsx`
Lista de jogadores na sala com indicador de online/offline (Presence). Host vê botão "Iniciar Jogo" quando há 4+ jogadores.

### `host-controls.tsx`
Barra de controle do host com 5 modos:
- `start`: Botão "Iniciar Jogo"
- `advance`: Botão "Avançar" (label customizável)
- `resolve_night_wolves`: Botão "Resolver Lobisomens"
- `resolve_night`: Botão "Resolver Noite"
- `resolve_vote`: Botão "Resolver Votação"

### `night-phase.tsx`
Container da fase noturna. Renderiza o painel correto baseado no papel do jogador e se `wolvesResolved` está true.

### `werewolf-panel.tsx`
Lista de jogadores vivos para o lobisomem escolher um alvo. Mostra colegas lobisomens (via `get_werewolf_teammates`). Botão "Confirmar" só ativo após selecionar. Mensagem de aguardo enquanto outros lobos não votaram.

### `seer-panel.tsx`
Input de busca + lista de jogadores vivos. Ao selecionar, chama `submit_night_action` com tipo `seer` e mostra resultado boolean imediato.

### `witch-panel.tsx`
Dois passos:
1. **Poção da Vida**: se há vítima dos lobos, pergunta se quer salvar. Botão "Salvar" ou "Deixar Morrer".
2. **Poção da Morte**: pergunta se quer envenenar alguém. Se sim, mostra lista de jogadores vivos. Botões "Envenenar" ou "Pular".

Os botões da bruxa somem (ficam disabled) após usar cada poção, e as flags persistem na tabela `players`.

### `day-announcement.tsx`
Lista de vítimas da noite com causa (lobisomem / veneno). Se ninguém morreu, mostra "Ninguém morreu durante a noite".

### `voting-panel.tsx`
Lista de jogadores vivos (exceto o próprio) com botões de voto. Desabilitado se o jogador está morto. Mostra "Aguardando..." após votar.

### `timer-display.tsx`
Display MM:SS sincronizado via Realtime.
- Quando rodando: decrementa localmente baseado em `timer_started_at + timer_remaining`
- Quando pausado: mostra valor congelado
- Em 00:00: texto vermelho pulsante + "⏰ Tempo Esgotado!"
- Usa `setInterval(200ms)` para smoothness

### `host-timer-controls.tsx`
Seletor de presets (1/2/3/5/10 min) + botões:
- **Iniciar**: chama `start_timer`
- **Pausar**: chama `pause_timer`
- **Retomar**: chama `resume_timer`
- **Resetar**: chama `reset_timer`

Apenas visível para o host.

---

## 9. Hooks

### `use-player.ts` (`useCurrentPlayer`)
- Escuta `players` via Realtime filtrando pelo `user_id` atual
- Retorna `Player` com `id`, `name`, `role`, `isHost`, `isAlive`, potion flags
- Lida com loading state (`player === null`)

### `use-room.ts`
- `useRoomPlayers(roomId)`: lista de `PlayerProfile` (sem role) via `player_profiles` view
- `useGameState(roomId)`: escuta `game_state` via Realtime. Retorna `GameStateRow` com:
  - `current_phase`, `turn_index`
  - `wolves_resolved`, `last_event`, `last_vote_result`
  - Timer fields: `timer_duration`, `timer_remaining`, `is_timer_running`, `timer_started_at`

---

## 10. Timer

O timer roda **sem server-side tick**. O servidor armazena apenas os metadados:

| Coluna             | Tipo        | Descrição                        |
|--------------------|-------------|----------------------------------|
| `timer_duration`   | `int`       | Duração total configurada (seg)  |
| `timer_remaining`  | `int`       | Tempo restante no segmento atual |
| `is_timer_running` | `bool`      | Se está rodando ou pausado       |
| `timer_started_at` | `timestamptz` | Momento em que foi iniciado/retomado |

**Cálculo local no cliente**:
```
remaining = timer_remaining - (Date.now() - timer_started_at) / 1000
```

Quando pausado, `timer_started_at` é null e `timer_remaining` contém o valor congelado.

Isso garante que **todos os clientes** (incluindo quem entrou no meio) vejam o mesmo valor.

---

## 11. Segurança (RLS)

Todas as tabelas têm **Row Level Security** ativado.

### Políticas principais

| Tabela         | Política                                    |
|----------------|---------------------------------------------|
| `rooms`        | Host pode update; leitura para qualquer um   |
| `players`      | INSERT se não excede max_players; SELECT sempre; UPDATE apenas host ou próprio jogador |
| `game_state`   | SELECT para jogadores da sala; UPDATE via RPC (host) |
| `night_actions`| SELECT apenas própria ação; INSERT se `role` permite e está vivo; UPDATE não permitido |
| `votes`        | INSERT se está vivo (check `is_alive`); UPDATE não permitido; SELECT para todos |

### Proteção de papéis
- A view `player_profiles` expõe `id`, `name`, `is_alive`, `is_host`, `has_viewed_card` — **nunca** o campo `role`.
- O papel só é visível para o próprio jogador via RPC `get_player_roles`.
- A RPC `get_werewolf_teammates` só retorna dados se o chamador for lobisomem.

---

## 12. Deploy

### Supabase
1. Crie um projeto em [supabase.com](https://supabase.com)
2. Ative **Anonymous sign-ins** em Authentication → Settings
3. Execute as migrations em ordem no SQL Editor
4. Ative Realtime para as tabelas `players`, `game_state`, `night_actions`, `votes`
5. Copie as credenciais (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) para `.env.local`

### Vercel / Next.js
1. Conecte o repositório na Vercel
2. Adicione `NEXT_PUBLIC_SUPABASE_URL` e `NEXT_PUBLIC_SUPABASE_ANON_KEY` nas Environment Variables
3. Deploy automático na branch `main`

---

## 13. Desenvolvimento Local

```bash
# Instalar dependências
npm install

# Copiar e configurar variáveis de ambiente
cp .env.example .env.local
# Edite .env.local com suas credenciais do Supabase

# Rodar dev server
npm run dev

# Build de produção
npm run build

# Lint
npm run lint
```

### Pré-requisitos
- Node.js 20+
- Projeto Supabase ativo
- `.env.local` com `NEXT_PUBLIC_SUPABASE_URL` e `NEXT_PUBLIC_SUPABASE_ANON_KEY`
